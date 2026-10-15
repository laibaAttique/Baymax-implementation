'use client';

import { FormEvent, useState } from 'react';
import { api } from '@/lib/api';
import { useAuth, useMe } from '@/lib/auth';
import { Card, Notice } from '@/components/ui';

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export default function SettingsPage() {
  const me = useMe();
  const { refreshMe } = useAuth();
  const p = me.profile;
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

  const toggleDay = (d: number) => setDays((cur) => (cur.includes(d) ? cur.filter((x) => x !== d) : [...cur, d].sort()));

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      await api('/me/profile', {
        method: 'PUT',
        body: {
          specialty,
          bio,
          fees: { video: Number(video), chat: Number(chat) },
          availability: { days, start, end, slotMinutes: Number(slot) },
          available,
          emergency,
        },
      });
      await refreshMe();
      setMessage({ tone: 'ok', text: 'Saved. Patients see the change in the Baymax app straight away. Appointments already booked are not affected.' });
    } catch (err) {
      setMessage({ tone: 'error', text: err instanceof Error ? err.message : 'Could not save.' });
    } finally {
      setBusy(false);
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
      <form className="stack" onSubmit={save}>
        <Card title="About you">
          <dl className="facts">
            <dt>Name</dt><dd>{p.name}</dd>
            <dt>Role</dt><dd>{me.roleLabel}</dd>
            <dt>Email</dt><dd>{me.email}</dd>
            <dt>Rating</dt><dd>{p.reviewCount ? `${p.rating?.toFixed(1)} from ${p.reviewCount} reviews` : 'No reviews yet'}</dd>
          </dl>
          <p className="muted small">Name, role and rating are set by a Baymax administrator.</p>
          <label>Specialty<input value={specialty} onChange={(e) => setSpecialty(e.target.value)} maxLength={80} required /></label>
          <label>Short bio<textarea value={bio} onChange={(e) => setBio(e.target.value)} rows={4} maxLength={600} /></label>
        </Card>

        <Card title="Fees (PKR)">
          <div className="grid2">
            <label>Video call<input type="number" min={0} max={1000000} step={50} value={video} onChange={(e) => setVideo(e.target.value)} required /></label>
            <label>Chat only<input type="number" min={0} max={1000000} step={50} value={chat} onChange={(e) => setChat(e.target.value)} required /></label>
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
            <label>From<input type="time" value={start} onChange={(e) => setStart(e.target.value)} required /></label>
            <label>Until<input type="time" value={end} onChange={(e) => setEnd(e.target.value)} required /></label>
            <label>
              Length of one slot
              <select value={slot} onChange={(e) => setSlot(e.target.value)}>
                {[15, 20, 30, 45, 60].map((m) => <option key={m} value={m}>{m} minutes</option>)}
              </select>
            </label>
          </div>
        </Card>

        <Card title="Availability">
          <label className="check"><input type="checkbox" checked={available} onChange={(e) => setAvailable(e.target.checked)} /> I am taking bookings</label>
          <label className="check"><input type="checkbox" checked={emergency} onChange={(e) => setEmergency(e.target.checked)} /> I take urgent (emergency) bookings</label>
        </Card>

        <div><button className="btn btn-primary" disabled={busy || days.length === 0}>{busy ? 'Saving…' : 'Save changes'}</button></div>
      </form>
    </>
  );
}
