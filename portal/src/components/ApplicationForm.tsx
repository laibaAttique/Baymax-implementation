'use client';

import { FormEvent, useState, type ReactNode } from 'react';
import { api } from '@/lib/api';
import type { Role } from '@/lib/types';
import { applicationProblems, hoursProblem, type Problems } from '@/lib/validate';
import { Card, Counter, Field, Notice } from '@/components/ui';

const TYPES: { value: Role; label: string }[] = [
  { value: 'doctor', label: 'Doctor' },
  { value: 'nutritionist', label: 'Nutritionist' },
  { value: 'trainer', label: 'Trainer' },
];
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/**
 * A specialist's registration details. Sending it does NOT give access: an administrator checks the licence number first.
 * [beforeSubmit] runs first (the register page uses it to create the sign-in account); [extra] is shown at the top of the form.
 * Every field is checked before anything is sent, and the problems are shown next to the fields.
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
  const [problems, setProblems] = useState<Problems>({});

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
  const fields = () => ({ name, specialty, license, years, bio, video, chat, days, start, end });
  /** Re-check one field when the person leaves it, so the message appears while they are still there. */
  const recheck = (key: string) => setProblems((cur) => {
    const next = { ...cur };
    const found = applicationProblems(fields())[key];
    if (found) next[key] = found; else delete next[key];
    return next;
  });

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    const found = applicationProblems(fields());
    setProblems(found);
    if (Object.keys(found).length) {
      setError('Please fix the highlighted fields and send again.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (beforeSubmit) await beforeSubmit();
      await api('/applications', {
        method: 'POST',
        body: {
          name: name.trim(),
          type,
          specialty: specialty.trim(),
          licenseNumber: license.trim(),
          yearsOfExperience: Number(years) || 0,
          bio: bio.trim(),
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

  const bad = (k: string) => (problems[k] ? true : undefined);

  return (
    <form className="stack" onSubmit={submit} noValidate>
      {error && <Notice tone="error">{error}</Notice>}
      {extra}
      <Card title="About you">
        <div className="grid2">
          <Field label="Full name" error={problems.name}>
            <input value={name} onChange={(e) => setName(e.target.value)} onBlur={() => recheck('name')} maxLength={80} aria-invalid={bad('name')} autoComplete="name" />
          </Field>
          <label>
            I am a
            <select value={type} onChange={(e) => setType(e.target.value as Role)}>
              {TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </label>
        </div>
        <div className="grid2">
          <Field label="Specialty" error={problems.specialty}>
            <input value={specialty} onChange={(e) => setSpecialty(e.target.value)} onBlur={() => recheck('specialty')} maxLength={80} placeholder="e.g. Sports nutrition" aria-invalid={bad('specialty')} />
          </Field>
          <Field label="Professional licence / registration number" error={problems.license} hint="An administrator checks this before approving you.">
            <input value={license} onChange={(e) => setLicense(e.target.value)} onBlur={() => recheck('license')} maxLength={40} placeholder="e.g. PMDC-12345" aria-invalid={bad('license')} />
          </Field>
        </div>
        <Field label="Years of experience" error={problems.years}>
          <input type="number" inputMode="numeric" min={0} max={70} value={years} onChange={(e) => setYears(e.target.value)} onBlur={() => recheck('years')} aria-invalid={bad('years')} />
        </Field>
        <Field label="Short bio (shown to patients)" error={problems.bio}>
          <textarea rows={3} value={bio} onChange={(e) => setBio(e.target.value)} onBlur={() => recheck('bio')} aria-invalid={bad('bio')} />
          <Counter value={bio} max={600} />
        </Field>
      </Card>
      <Card title="Fees and hours">
        <div className="grid2">
          <Field label="Video call fee (PKR)" error={problems.video}>
            <input type="number" inputMode="numeric" min={0} max={1000000} step={50} value={video} onChange={(e) => setVideo(e.target.value)} onBlur={() => recheck('video')} aria-invalid={bad('video')} />
          </Field>
          <Field label="Chat-only fee (PKR)" error={problems.chat}>
            <input type="number" inputMode="numeric" min={0} max={1000000} step={50} value={chat} onChange={(e) => setChat(e.target.value)} onBlur={() => recheck('chat')} aria-invalid={bad('chat')} />
          </Field>
        </div>
        <fieldset className="days">
          <legend>Working days</legend>
          {DAYS.map((d, i) => (
            <label key={d} className="check"><input type="checkbox" checked={days.includes(i + 1)} onChange={() => toggleDay(i + 1)} /> {d}</label>
          ))}
        </fieldset>
        <div className="grid2">
          <label>From<input type="time" value={start} onChange={(e) => setStart(e.target.value)} onBlur={() => recheck('hours')} aria-invalid={bad('hours')} /></label>
          <label>Until<input type="time" value={end} onChange={(e) => setEnd(e.target.value)} onBlur={() => recheck('hours')} aria-invalid={bad('hours')} /></label>
        </div>
        {problems.hours && <span className="field-error" role="alert">{problems.hours}</span>}
        <label className="check"><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> I take urgent (emergency) bookings</label>
        <p className="muted small">Times are in Pakistan time, in 30-minute slots. You can change fees and hours later.</p>
      </Card>
      <p className="muted small">An administrator checks your licence number before you appear in the Baymax app or can sign in to the portal as a specialist.</p>
      <div><button className="btn btn-primary" disabled={busy}>{busy ? 'Sending…' : 'Send registration'}</button></div>
    </form>
  );
}
