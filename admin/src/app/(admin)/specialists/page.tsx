'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { pkr } from '@/lib/format';
import type { AdminSpecialist, DeleteResult, NewSpecialistResult, Role } from '@/lib/types';
import { Badge, Card, Field, Notice, Spinner } from '@/components/ui';
import { applicationProblems, emailProblem, hoursProblem, type Problems } from '@/lib/validate';

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
  const [problems, setProblems] = useState<Problems>({});

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

  const toggleDay = (d: number) => {
    const next = days.includes(d) ? days.filter((x) => x !== d) : [...days, d].sort();
    setDays(next);
    // Check against the new list of days, not the one from before this click.
    setProblems((cur) => {
      const found = hoursProblem(next, start, end);
      const copy = { ...cur };
      if (found) copy.hours = found; else delete copy.hours;
      return copy;
    });
  };

  /** Everything wrong with the form, by field. The licence is not asked for here: the administrator is adding a person they already know. */
  const check = (): Problems => {
    const found = applicationProblems({ name, specialty, license: '', years, bio: '', video, chat, days, start, end }, { license: false });
    const mail = emailProblem(email);
    return mail ? { email: mail, ...found } : found;
  };
  const recheck = (key: string) => setProblems((cur) => {
    const copy = { ...cur };
    const found = check()[key];
    if (found) copy[key] = found; else delete copy[key];
    return copy;
  });
  const bad = (k: string) => (problems[k] ? true : undefined);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    const found = check();
    setProblems(found);
    if (Object.keys(found).length) {
      setError('Please fix the highlighted fields and add again.');
      return;
    }
    setBusy(true);
    setError(null);
    setResult(null);
    setCopied(false);
    try {
      const r = await api<NewSpecialistResult>('/admin/specialists', {
        method: 'POST',
        body: { email: email.trim(), name: name.trim(), type, specialty: specialty.trim(), yearsOfExperience: Number(years) || 0, emergency, fees: { video: Number(video), chat: Number(chat) }, availability: { days, start, end, slotMinutes: 30 } },
      });
      setResult(r);
      setEmail('');
      setName('');
      setSpecialty('');
      setProblems({});
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
        <form className="stack" onSubmit={submit} noValidate>
          {error && <Notice tone="error">{error}</Notice>}
          <div className="grid2">
            <Field label="Email" error={problems.email}>
              <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} onBlur={() => recheck('email')} maxLength={120} autoComplete="off" aria-invalid={bad('email')} />
            </Field>
            <Field label="Full name" error={problems.name}>
              <input value={name} onChange={(e) => setName(e.target.value)} onBlur={() => recheck('name')} maxLength={80} aria-invalid={bad('name')} />
            </Field>
          </div>
          <div className="grid2">
            <label>Type<select value={type} onChange={(e) => setType(e.target.value as Role)}>{TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}</select></label>
            <Field label="Specialty" error={problems.specialty}>
              <input value={specialty} onChange={(e) => setSpecialty(e.target.value)} onBlur={() => recheck('specialty')} maxLength={80} aria-invalid={bad('specialty')} />
            </Field>
          </div>
          <div className="grid3">
            <Field label="Video fee (PKR)" error={problems.video}>
              <input type="number" inputMode="numeric" min={0} max={1000000} step={50} value={video} onChange={(e) => setVideo(e.target.value)} onBlur={() => recheck('video')} aria-invalid={bad('video')} />
            </Field>
            <Field label="Chat fee (PKR)" error={problems.chat}>
              <input type="number" inputMode="numeric" min={0} max={1000000} step={50} value={chat} onChange={(e) => setChat(e.target.value)} onBlur={() => recheck('chat')} aria-invalid={bad('chat')} />
            </Field>
            <Field label="Years of experience" error={problems.years}>
              <input type="number" inputMode="numeric" min={0} max={70} value={years} onChange={(e) => setYears(e.target.value)} onBlur={() => recheck('years')} aria-invalid={bad('years')} />
            </Field>
          </div>
          <fieldset className="days">
            <legend>Working days</legend>
            {DAYS.map((d, i) => <label key={d} className="check"><input type="checkbox" checked={days.includes(i + 1)} onChange={() => toggleDay(i + 1)} /> {d}</label>)}
          </fieldset>
          <div className="grid2">
            <label>From<input type="time" value={start} onChange={(e) => setStart(e.target.value)} onBlur={() => recheck('hours')} aria-invalid={bad('hours')} /></label>
            <label>Until<input type="time" value={end} onChange={(e) => setEnd(e.target.value)} onBlur={() => recheck('hours')} aria-invalid={bad('hours')} /></label>
          </div>
          {problems.hours && <span className="field-error" role="alert">{problems.hours}</span>}
          <label className="check"><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> Takes urgent (emergency) bookings</label>
          <div><button className="btn btn-primary" disabled={busy}>{busy ? 'Adding…' : 'Add specialist'}</button></div>
        </form>
      </Card>
    </>
  );
}
