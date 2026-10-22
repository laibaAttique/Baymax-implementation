'use client';

import { FormEvent, useEffect, useState } from 'react';
import { EmailAuthProvider, reauthenticateWithCredential } from 'firebase/auth';
import { firebaseAuth } from '@/lib/firebase';
import { api } from '@/lib/api';
import { useAuth, useMe } from '@/lib/auth';
import { Card, Counter, Field, Notice } from '@/components/ui';
import { hoursProblem, profileProblems, type Problems } from '@/lib/validate';
import type { SpecialistProfile } from '@/lib/types';

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export default function SettingsPage() {
  const me = useMe();
  const { refreshMe } = useAuth();
  // Administrators never reach this page (the layout sends them to /admin), so a profile is always there.
  const p = me.profile as SpecialistProfile;
  const [specialty, setSpecialty] = useState(p.specialty);
  const [bio, setBio] = useState(p.bio ?? '');
  const [video, setVideo] = useState(String(p.fees.video));
  const [chat, setChat] = useState(String(p.fees.chat));
  const [days, setDays] = useState<number[]>(p.availability.days);
  const [start, setStart] = useState(p.availability.start);
  const [end, setEnd] = useState(p.availability.end);
  const [slot, setSlot] = useState(String(p.availability.slotMinutes));
  const [available, setAvailable] = useState(p.available);
  const [emergency, setEmergency] = useState(Boolean(p.emergency));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const [problems, setProblems] = useState<Problems>({});
  const [dirty, setDirty] = useState(false);
  const touch = () => setDirty(true);

  // Leaving with unsaved changes asks first.
  useEffect(() => {
    if (!dirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty]);

  const fields = () => ({ specialty, bio, video, chat, days, start, end, slot });
  const recheck = (key: string) => setProblems((cur) => {
    const next = { ...cur };
    const found = profileProblems(fields())[key];
    if (found) next[key] = found; else delete next[key];
    return next;
  });
  const bad = (k: string) => (problems[k] ? true : undefined);

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

  async function save(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    const found = profileProblems(fields());
    setProblems(found);
    if (Object.keys(found).length) {
      setMessage({ tone: 'error', text: 'Please fix the highlighted fields and save again.' });
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      await api('/me/profile', {
        method: 'PUT',
        body: {
          specialty: specialty.trim(),
          bio: bio.trim(),
          fees: { video: Number(video), chat: Number(chat) },
          availability: { days, start, end, slotMinutes: Number(slot) },
          available,
          emergency,
        },
      });
      await refreshMe();
      setDirty(false);
      setMessage({ tone: 'ok', text: 'Saved. Patients see the change in the Baymax app straight away. Appointments already booked are not affected.' });
    } catch (err) {
      setMessage({ tone: 'error', text: err instanceof Error ? err.message : 'Could not save.' });
    } finally {
      setBusy(false);
    }
  }

  const { signOut } = useAuth();
  const [password, setPassword] = useState('');
  const [typed, setTyped] = useState('');
  const [closing, setClosing] = useState(false);
  const [closeError, setCloseError] = useState<string | null>(null);

  /** Closing the account asks for the password again, so a browser left open cannot do it. */
  async function closeAccount(e: FormEvent) {
    e.preventDefault();
    setClosing(true);
    setCloseError(null);
    try {
      const user = firebaseAuth().currentUser;
      if (!user || !user.email) throw new Error('Please sign in again.');
      await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email, password));
      await user.getIdToken(true); // a fresh sign-in time for the server to see
      await api('/me', { method: 'DELETE', body: { confirm: 'DELETE' } });
      await signOut();
      window.location.href = '/login';
    } catch (err) {
      const code = (err as { code?: string }).code;
      setCloseError(
        code === 'auth/wrong-password' || code === 'auth/invalid-credential'
          ? 'That password is not right.'
          : err instanceof Error ? err.message : 'Could not close the account.',
      );
    } finally {
      setClosing(false);
    }
  }

  return (
    <>
      <header className="page-head">
        <div>
          <h1>My profile</h1>
          <p className="muted">This is what patients see when they look for a {me.roleLabel.toLowerCase()} in the Baymax app.</p>
        </div>
      </header>
      {message && <Notice tone={message.tone}>{message.text}</Notice>}
      <form className="stack" onSubmit={save} noValidate onChange={touch}>
        <Card title="About you">
          <dl className="facts">
            <dt>Name</dt><dd>{p.name}</dd>
            <dt>Role</dt><dd>{me.roleLabel}</dd>
            <dt>Email</dt><dd>{me.email}</dd>
            <dt>Rating</dt><dd>{p.reviewCount ? `${p.rating?.toFixed(1)} from ${p.reviewCount} reviews` : 'No reviews yet'}</dd>
          </dl>
          <p className="muted small">Name, role and rating are set by a Baymax administrator.</p>
          <Field label="Specialty" error={problems.specialty}>
            <input value={specialty} onChange={(e) => setSpecialty(e.target.value)} onBlur={() => recheck('specialty')} maxLength={80} aria-invalid={bad('specialty')} />
          </Field>
          <Field label="Short bio" error={problems.bio}>
            <textarea value={bio} onChange={(e) => setBio(e.target.value)} onBlur={() => recheck('bio')} rows={4} aria-invalid={bad('bio')} />
            <Counter value={bio} max={600} />
          </Field>
        </Card>

        <Card title="Fees (PKR)">
          <div className="grid2">
            <Field label="Video call" error={problems.video}>
              <input type="number" inputMode="numeric" min={0} max={1000000} step={50} value={video} onChange={(e) => setVideo(e.target.value)} onBlur={() => recheck('video')} aria-invalid={bad('video')} />
            </Field>
            <Field label="Chat only" error={problems.chat}>
              <input type="number" inputMode="numeric" min={0} max={1000000} step={50} value={chat} onChange={(e) => setChat(e.target.value)} onBlur={() => recheck('chat')} aria-invalid={bad('chat')} />
            </Field>
          </div>
        </Card>

        <Card title="Working hours">
          <p className="muted small">Times are in your own time zone (UTC{p.tzOffsetMinutes >= 0 ? '+' : '-'}{Math.abs(p.tzOffsetMinutes / 60)}).</p>
          <fieldset className="days">
            <legend>Working days</legend>
            {DAYS.map((name, i) => (
              <label key={name} className="check">
                <input type="checkbox" checked={days.includes(i + 1)} onChange={() => toggleDay(i + 1)} /> {name}
              </label>
            ))}
          </fieldset>
          <div className="grid3">
            <label>From<input type="time" value={start} onChange={(e) => setStart(e.target.value)} onBlur={() => recheck('hours')} aria-invalid={bad('hours')} /></label>
            <label>Until<input type="time" value={end} onChange={(e) => setEnd(e.target.value)} onBlur={() => recheck('hours')} aria-invalid={bad('hours')} /></label>
            <label>
              Length of one slot
              <select value={slot} onChange={(e) => setSlot(e.target.value)}>
                {[15, 20, 30, 45, 60].map((m) => <option key={m} value={m}>{m} minutes</option>)}
              </select>
            </label>
          </div>
          {problems.hours && <span className="field-error" role="alert">{problems.hours}</span>}
        </Card>

        <Card title="Availability">
          <label className="check"><input type="checkbox" checked={available} onChange={(e) => setAvailable(e.target.checked)} /> I am taking bookings</label>
          <label className="check"><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> I take urgent (emergency) bookings</label>
        </Card>

        <div><button className="btn btn-primary" disabled={busy}>{busy ? 'Saving…' : 'Save changes'}</button>{dirty && <span className="muted small"> You have unsaved changes.</span>}</div>
      </form>

      <Card title="Close my account">
        <p>This removes you as a specialist: you disappear from the Baymax app, your future appointments and requests are cancelled and the patients are told, and your sign-in is deleted. Notes and prescriptions you already wrote stay in each patient&apos;s own record. This cannot be undone.</p>
        <form className="stack" onSubmit={closeAccount}>
          {closeError && <Notice tone="error">{closeError}</Notice>}
          <div className="grid2">
            <label>Your password<input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} maxLength={128} /></label>
            <label>Type DELETE to confirm<input value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="DELETE" /></label>
          </div>
          <div><button className="btn btn-danger" disabled={closing || typed !== 'DELETE' || !password}>{closing ? 'Closing…' : 'Close my account'}</button></div>
        </form>
      </Card>
    </>
  );
}
