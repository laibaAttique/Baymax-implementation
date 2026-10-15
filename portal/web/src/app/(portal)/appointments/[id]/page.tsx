'use client';

import { FormEvent, use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { useMe } from '@/lib/auth';
import { fmtDateTime, pkr, safeHttps } from '@/lib/format';
import type { AppointmentDetail, SharedData } from '@/lib/types';
import { Badge, Card, Notice, PaymentBadge, Spinner, StatusBadge } from '@/components/ui';

function Shared({ data }: { data: SharedData }) {
  const h = data.healthSummary;
  return (
    <>
      {h && (
        <Card title="Health summary">
          <dl className="facts">
            <dt>Age</dt><dd>{h.age ?? 'Not given'}</dd>
            <dt>Gender</dt><dd>{h.gender || 'Not given'}</dd>
            <dt>Height</dt><dd>{h.height ? `${h.height.value} ${h.height.unit}` : 'Not given'}</dd>
            <dt>Weight</dt><dd>{h.weight ? `${h.weight.value} ${h.weight.unit}` : 'Not given'}{h.targetWeight ? ` (target ${h.targetWeight.value} ${h.targetWeight.unit})` : ''}</dd>
            <dt>BMI</dt><dd>{h.bmi ?? 'Not given'}</dd>
            <dt>Baymax health class</dt><dd>{h.healthClassification ?? 'Not given'}</dd>
            <dt>Goal</dt><dd>{h.primaryGoal ?? 'Not given'}</dd>
            <dt>Activity</dt><dd>{h.activityLevel ?? 'Not given'}{h.workoutFrequency != null ? `, ${h.workoutFrequency} workouts a week` : ''}</dd>
            <dt>Medical conditions</dt><dd>{h.medicalConditions.length ? h.medicalConditions.join(', ') : 'None reported'}</dd>
            <dt>Food allergies</dt><dd>{h.foodAllergies.length ? h.foodAllergies.join(', ') : 'None reported'}</dd>
            <dt>Medicines</dt><dd>{h.medications || 'None reported'}</dd>
          </dl>
          <p className="muted small">Reported by the patient. The Baymax health class is decision support, not a diagnosis.</p>
        </Card>
      )}
      {data.foodLog7d && (
        <Card title="Diet log, last 7 days">
          {data.foodLog7d.every((d) => d.entries.length === 0) ? (
            <p className="muted">Nothing was logged in the last seven days.</p>
          ) : (
            data.foodLog7d.map((d) => (
              <div key={d.date} className="day">
                <h3>{d.date} <span className="muted small">{d.totalKcal} kcal</span></h3>
                {d.entries.length === 0 ? (
                  <p className="muted small">Nothing logged.</p>
                ) : (
                  <ul className="plain">
                    {d.entries.map((e, i) => (
                      <li key={i}>{e.meal}: {e.name} <span className="muted small">{Math.round(e.kcal)} kcal · P {Math.round(e.protein)} · C {Math.round(e.carbs)} · F {Math.round(e.fat)}</span></li>
                    ))}
                  </ul>
                )}
              </div>
            ))
          )}
          <p className="muted small">Calories and macros are estimates from the patient&apos;s own entries.</p>
        </Card>
      )}
      {data.activity30d && (
        <Card title="Workouts, last 30 days">
          {data.activity30d.length === 0 ? (
            <p className="muted">No completed workouts in the last 30 days.</p>
          ) : (
            <ul className="plain">
              {data.activity30d.map((d) => (
                <li key={d.date}>{d.date}{d.minutes != null ? `: ${d.minutes} min` : ''}{d.kcal != null ? `, about ${d.kcal} kcal` : ''}</li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </>
  );
}

export default function AppointmentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const me = useMe();
  const [detail, setDetail] = useState<AppointmentDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [prescription, setPrescription] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);

  const load = useCallback(async () => {
    try {
      const d = await api<AppointmentDetail>(`/appointments/${id}`);
      setDetail(d);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load this appointment.');
    }
  }, [id]);

  useEffect(() => {
    void load();
    const t = setInterval(() => void load(), 30_000);
    return () => clearInterval(t);
  }, [load]);

  // Fill the form once from what is already saved; later refreshes must not overwrite what is being typed.
  const [filled, setFilled] = useState(false);
  useEffect(() => {
    if (detail && !filled) {
      setNotes(detail.appointment.consultation?.notes ?? '');
      setPrescription(detail.appointment.consultation?.prescription ?? '');
      setFilled(true);
    }
  }, [detail, filled]);

  async function saveNotes(e: FormEvent) {
    e.preventDefault();
    setBusy('notes');
    setMessage(null);
    try {
      await api(`/appointments/${id}/consultation`, { method: 'PUT', body: { notes, prescription } });
      setMessage({ tone: 'ok', text: 'Saved. The patient can now see this in the Baymax app.' });
      await load();
    } catch (err) {
      setMessage({ tone: 'error', text: err instanceof Error ? err.message : 'Could not save.' });
    } finally {
      setBusy(null);
    }
  }

  async function changeStatus(status: 'completed' | 'cancelled' | 'no_show') {
    if (status === 'cancelled' && !window.confirm('Cancel this appointment? The patient will be told and the time will be offered to others.')) return;
    setBusy(status);
    setMessage(null);
    try {
      await api(`/appointments/${id}/status`, { method: 'POST', body: { status } });
      setMessage({ tone: 'ok', text: status === 'completed' ? 'Marked as completed.' : status === 'cancelled' ? 'Appointment cancelled.' : 'Marked as missed.' });
      await load();
    } catch (err) {
      setMessage({ tone: 'error', text: err instanceof Error ? err.message : 'Could not update.' });
    } finally {
      setBusy(null);
    }
  }

  if (error && !detail) {
    return (
      <>
        <Link className="link" href="/appointments">‹ Appointments</Link>
        <Notice tone="error">{error}</Notice>
      </>
    );
  }
  if (!detail) return <Spinner label="Loading appointment" />;

  const a = detail.appointment;
  const link = safeHttps(a.meetingLink);
  const anyShared = a.shares.healthSummary || a.shares.foodLog7d || a.shares.activity30d;
  const started = detail.serverTime >= a.startAt;
  const canWrite = a.status !== 'cancelled' && started;

  return (
    <>
      <Link className="link" href="/appointments">‹ Appointments</Link>
      <header className="page-head">
        <div>
          <h1>{a.patientName || 'Patient'}</h1>
          <p className="muted">{fmtDateTime(a.startAt)} · {a.durationMinutes} min · {a.type === 'video' ? 'Video call' : 'Chat only'} · {pkr(a.fee)}</p>
        </div>
        <StatusBadge a={a} />
      </header>

      {message && <Notice tone={message.tone}>{message.text}</Notice>}

      <Card title="Payment">
        <p><PaymentBadge a={a} /></p>
        {a.payment ? (
          <dl className="facts">
            <dt>Method</dt><dd>{a.payment.method === 'card' ? 'Card' : a.payment.method === 'wallet' ? 'Mobile wallet' : 'Pay at clinic'}</dd>
            <dt>Amount</dt><dd>{pkr(a.payment.total)}{a.payment.status === 'pay_at_clinic' ? ' (to collect at the visit)' : ''}</dd>
            <dt>Transaction</dt><dd>{a.payment.transactionId}</dd>
          </dl>
        ) : (
          <p className="muted">No payment record is attached to this appointment.</p>
        )}
        {a.payment?.test && <p className="muted small">Test payment: no money was taken.</p>}
      </Card>

      <Card title="Meeting room">
        {a.status !== 'confirmed' ? (
          <p className="muted">This appointment is {a.status === 'no_show' ? 'marked as missed' : a.status}.</p>
        ) : a.canJoin && link ? (
          <>
            <p>The room is open.{a.type === 'chat' ? ' This is a chat-only booking: it opens with camera and microphone off, and you talk in the room’s chat.' : ''}</p>
            <a className="btn btn-primary" href={link} target="_blank" rel="noopener noreferrer">Join call ›</a>
          </>
        ) : (
          <p className="muted">{detail.serverTime < a.startAt ? 'The room opens 5 minutes before the start.' : 'The session time has passed.'}</p>
        )}
        <p className="muted small">The public Jitsi server may ask the first person in a room to sign in. Use your organisation&apos;s own Jitsi server in production.</p>
      </Card>

      {a.notesForSpecialist && (
        <Card title="Note from the patient">
          <p className="pre">{a.notesForSpecialist}</p>
        </Card>
      )}

      {!anyShared && <Notice>The patient did not share any health data for this appointment.</Notice>}
      {anyShared && detail.sharedLocked && <Notice>{detail.sharedLocked}</Notice>}
      {detail.sharedData && <Shared data={detail.sharedData} />}
      {detail.sharedData && <p className="muted small">Opening shared data is recorded, so the patient and administrators can see that you looked.</p>}

      <Card title="Consultation notes">
        {!canWrite ? (
          <p className="muted">{a.status === 'cancelled' ? 'This appointment was cancelled.' : 'You can add notes once the session has started.'}</p>
        ) : (
          <form onSubmit={saveNotes} className="stack">
            <label>
              Notes for the patient&apos;s profile
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={6} maxLength={5000} />
            </label>
            {me.role === 'doctor' ? (
              <label>
                Prescription
                <textarea value={prescription} onChange={(e) => setPrescription(e.target.value)} rows={4} maxLength={3000} placeholder="Medicine, dose, how often, for how long" />
              </label>
            ) : (
              <p className="muted small"><Badge>Doctors only</Badge> Prescriptions can only be written by a doctor.</p>
            )}
            <div>
              <button className="btn btn-primary" disabled={busy === 'notes' || (!notes.trim() && !prescription.trim())}>
                {busy === 'notes' ? 'Saving…' : 'Save and share with patient'}
              </button>
            </div>
            {a.consultation && <p className="muted small">Last saved {fmtDateTime(a.consultation.updatedAt)}.</p>}
          </form>
        )}
      </Card>

      {a.status === 'confirmed' && (
        <Card title="Appointment status">
          <div className="actions">
            <button className="btn" disabled={busy !== null || !started} onClick={() => void changeStatus('completed')}>Mark completed</button>
            <button className="btn" disabled={busy !== null || detail.serverTime < a.startAt + 10 * 60_000} onClick={() => void changeStatus('no_show')}>Patient did not attend</button>
            <button className="btn btn-danger" disabled={busy !== null || detail.serverTime >= a.endAt} onClick={() => void changeStatus('cancelled')}>Cancel appointment</button>
          </div>
        </Card>
      )}
    </>
  );
}
