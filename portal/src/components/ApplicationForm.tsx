'use client';

import { FormEvent, useState, type ReactNode } from 'react';
import { api } from '@/lib/api';
import type { Role } from '@/lib/types';
import { Card, Notice } from '@/components/ui';

const TYPES: { value: Role; label: string }[] = [
  { value: 'doctor', label: 'Doctor' },
  { value: 'nutritionist', label: 'Nutritionist' },
  { value: 'trainer', label: 'Trainer' },
];
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/**
 * A specialist's registration details. Sending it does NOT give access: an administrator checks the licence number first.
 * [beforeSubmit] runs first (the register page uses it to create the sign-in account); [extra] is shown at the top of the form.
 */
export function ApplicationForm({
  onSubmitted,
  beforeSubmit,
  extra,
  initialName = '',
}: {
  onSubmitted: () => void | Promise<void>;
  beforeSubmit?: () => Promise<void>;
  extra?: ReactNode;
  initialName?: string;
}) {
  const [name, setName] = useState(initialName);
  const [type, setType] = useState<Role>('doctor');
  const [specialty, setSpecialty] = useState('');
  const [license, setLicense] = useState('');
  const [years, setYears] = useState('0');
  const [bio, setBio] = useState('');
  const [video, setVideo] = useState('2500');
  const [chat, setChat] = useState('1500');
  const [days, setDays] = useState<number[]>([1, 2, 3, 4, 5]);
  const [start, setStart] = useState('09:00');
  const [end, setEnd] = useState('17:00');
  const [emergency, setEmergency] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggleDay = (d: number) => setDays((cur) => (cur.includes(d) ? cur.filter((x) => x !== d) : [...cur, d].sort()));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (beforeSubmit) await beforeSubmit();
      await api('/applications', {
        method: 'POST',
        body: {
          name,
          type,
          specialty,
          licenseNumber: license,
          yearsOfExperience: Number(years) || 0,
          bio,
          emergency,
          fees: { video: Number(video), chat: Number(chat) },
          availability: { days, start, end, slotMinutes: 30 },
        },
      });
      await onSubmitted();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send your registration.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="stack" onSubmit={submit}>
      {error && <Notice tone="error">{error}</Notice>}
      {extra}
      <Card title="About you">
        <div className="grid2">
          <label>Full name<input value={name} onChange={(e) => setName(e.target.value)} required minLength={2} maxLength={80} /></label>
          <label>
            I am a
            <select value={type} onChange={(e) => setType(e.target.value as Role)}>
              {TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </label>
        </div>
        <div className="grid2">
          <label>Specialty<input value={specialty} onChange={(e) => setSpecialty(e.target.value)} required maxLength={80} placeholder="e.g. Sports nutrition" /></label>
          <label>Professional licence / registration number<input value={license} onChange={(e) => setLicense(e.target.value)} required maxLength={40} placeholder="e.g. PMDC-12345" /></label>
        </div>
        <label>Years of experience<input type="number" min={0} max={70} value={years} onChange={(e) => setYears(e.target.value)} /></label>
        <label>Short bio (shown to patients)<textarea rows={3} maxLength={600} value={bio} onChange={(e) => setBio(e.target.value)} /></label>
      </Card>
      <Card title="Fees and hours">
        <div className="grid2">
          <label>Video call fee (PKR)<input type="number" min={0} max={1000000} step={50} value={video} onChange={(e) => setVideo(e.target.value)} required /></label>
          <label>Chat-only fee (PKR)<input type="number" min={0} max={1000000} step={50} value={chat} onChange={(e) => setChat(e.target.value)} required /></label>
        </div>
        <fieldset className="days">
          <legend>Working days</legend>
          {DAYS.map((d, i) => (
            <label key={d} className="check"><input type="checkbox" checked={days.includes(i + 1)} onChange={() => toggleDay(i + 1)} /> {d}</label>
          ))}
        </fieldset>
        <div className="grid2">
          <label>From<input type="time" value={start} onChange={(e) => setStart(e.target.value)} required /></label>
          <label>Until<input type="time" value={end} onChange={(e) => setEnd(e.target.value)} required /></label>
        </div>
        <label className="check"><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> I take urgent (emergency) bookings</label>
        <p className="muted small">Times are in Pakistan time, in 30-minute slots. You can change fees and hours later.</p>
      </Card>
      <p className="muted small">An administrator checks your licence number before you appear in the Baymax app or can sign in to the portal as a specialist.</p>
      <div><button className="btn btn-primary" disabled={busy || days.length === 0}>{busy ? 'Sending…' : 'Send registration'}</button></div>
    </form>
  );
}
