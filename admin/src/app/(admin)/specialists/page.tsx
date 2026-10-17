'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { pkr } from '@/lib/format';
import type { AdminSpecialist, DeleteResult, NewSpecialistResult, Role } from '@/lib/types';
import { Badge, Card, Notice, Spinner } from '@/components/ui';

const TYPES: { value: Role; label: string }[] = [
  { value: 'doctor', label: 'Doctor' },
  { value: 'nutritionist', label: 'Nutritionist' },
  { value: 'trainer', label: 'Trainer' },
];
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/** All specialists: add one directly, or delete one (which cancels their future appointments and tells the patients). */
export default function SpecialistsPage() {
  const [list, setList] = useState<AdminSpecialist[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [type, setType] = useState<Role>('doctor');
  const [specialty, setSpecialty] = useState('');
  const [video, setVideo] = useState('2500');
  const [chat, setChat] = useState('1500');
  const [years, setYears] = useState('0');
  const [emergency, setEmergency] = useState(false);
  const [days, setDays] = useState<number[]>([1, 2, 3, 4, 5]);
  const [start, setStart] = useState('09:00');
  const [end, setEnd] = useState('17:00');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<NewSpecialistResult | null>(null);
  const [copied, setCopied] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setList((await api<{ specialists: AdminSpecialist[] }>('/admin/specialists')).specialists);
      setLoadError(null);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Could not load the specialists.');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const toggleDay = (d: number) => setDays((cur) => (cur.includes(d) ? cur.filter((x) => x !== d) : [...cur, d].sort()));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setResult(null);
    setCopied(false);
    try {
      const r = await api<NewSpecialistResult>('/admin/specialists', {
        method: 'POST',
        body: { email, name, type, specialty, yearsOfExperience: Number(years) || 0, emergency, fees: { video: Number(video), chat: Number(chat) }, availability: { days, start, end, slotMinutes: 30 } },
      });
      setResult(r);
      setEmail('');
      setName('');
      setSpecialty('');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not add the specialist.');
    } finally {
      setBusy(false);
    }
  }

  async function remove(s: AdminSpecialist) {
    if (!window.confirm(`Delete ${s.name} (${s.email})?\n\nTheir future appointments and requests are cancelled and the patients are told. Past notes and prescriptions stay in the patients' records. This cannot be undone.`)) return;
    setDeleting(s.uid);
    setNotice(null);
    setLoadError(null);
    try {
      const r = await api<DeleteResult>(`/admin/specialists/${s.uid}`, { method: 'DELETE' });
      setNotice(`${s.name} was deleted. ${r.cancelled} upcoming appointment${r.cancelled === 1 ? '' : 's'} cancelled.${r.keptMemberAccount ? ' Their Baymax app login was kept because the same account is also a member.' : ''}`);
      await load();
    } catch (err) {
      setLoadError(err instanceof Error ? err.message : 'Could not delete.');
    } finally {
      setDeleting(null);
    }
  }

  async function copy() {
    if (!result) return;
    try {
      await navigator.clipboard.writeText(result.resetLink);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  return (
    <>
      <header className="page-head"><div><h1>Specialists</h1><p className="muted">Everyone patients can book in the Baymax app.</p></div></header>
      {notice && <Notice tone="ok">{notice}</Notice>}
      {loadError && <Notice tone="error">{loadError}</Notice>}
      {!list && !loadError && <Spinner label="Loading specialists" />}
      {list && (
        <Card title={`${list.length} specialist${list.length === 1 ? '' : 's'}`}>
          {list.length === 0 ? <p className="muted">No specialists yet. Approve a registration or add one below.</p> : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>Name</th><th>Type</th><th>Specialty</th><th>Email</th><th>Fees</th><th>Status</th><th><span className="sr-only">Actions</span></th></tr></thead>
                <tbody>
                  {list.map((s) => (
                    <tr key={s.uid}>
                      <td>{s.name}</td>
                      <td>{TYPES.find((t) => t.value === s.type)?.label ?? s.type}</td>
                      <td>{s.specialty}</td>
                      <td>{s.email}</td>
                      <td>{s.fees ? `${pkr(s.fees.video)} / ${pkr(s.fees.chat)}` : 'Not set'}</td>
                      <td>{s.available ? <Badge tone="good">Taking bookings</Badge> : <Badge tone="warn">Not taking bookings</Badge>}</td>
                      <td><button className="btn btn-small btn-danger" disabled={deleting === s.uid} onClick={() => void remove(s)}>{deleting === s.uid ? 'Deleting…' : 'Delete'}</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}

      {result && (
        <Notice tone="ok">
          <strong>{result.created ? 'Account created' : 'Existing account updated'} for {result.email}.</strong>
          <p>Send this one-time link so they can choose their own password. You never see or set it.</p>
          <p className="pre small" data-testid="reset-link">{result.resetLink}</p>
          <button type="button" className="btn btn-small" onClick={() => void copy()}>{copied ? 'Copied' : 'Copy link'}</button>
        </Notice>
      )}

      <Card title="Add a specialist directly">
        <form className="stack" onSubmit={submit}>
          {error && <Notice tone="error">{error}</Notice>}
          <div className="grid2">
            <label>Email<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="off" /></label>
            <label>Full name<input value={name} onChange={(e) => setName(e.target.value)} required minLength={2} maxLength={80} /></label>
          </div>
          <div className="grid2">
            <label>Type<select value={type} onChange={(e) => setType(e.target.value as Role)}>{TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}</select></label>
            <label>Specialty<input value={specialty} onChange={(e) => setSpecialty(e.target.value)} required maxLength={80} /></label>
          </div>
          <div className="grid3">
            <label>Video fee (PKR)<input type="number" min={0} max={1000000} step={50} value={video} onChange={(e) => setVideo(e.target.value)} required /></label>
            <label>Chat fee (PKR)<input type="number" min={0} max={1000000} step={50} value={chat} onChange={(e) => setChat(e.target.value)} required /></label>
            <label>Years of experience<input type="number" min={0} max={70} value={years} onChange={(e) => setYears(e.target.value)} /></label>
          </div>
          <fieldset className="days">
            <legend>Working days</legend>
            {DAYS.map((d, i) => <label key={d} className="check"><input type="checkbox" checked={days.includes(i + 1)} onChange={() => toggleDay(i + 1)} /> {d}</label>)}
          </fieldset>
          <div className="grid2">
            <label>From<input type="time" value={start} onChange={(e) => setStart(e.target.value)} required /></label>
            <label>Until<input type="time" value={end} onChange={(e) => setEnd(e.target.value)} required /></label>
          </div>
          <label className="check"><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> Takes urgent (emergency) bookings</label>
          <div><button className="btn btn-primary" disabled={busy || days.length === 0}>{busy ? 'Adding…' : 'Add specialist'}</button></div>
        </form>
      </Card>
    </>
  );
}
