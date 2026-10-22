'use client';

import { FormEvent, use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { refreshSummary } from '@/lib/events';
import { useMe } from '@/lib/auth';
import { fmtDateTime, pkr, safeHttps } from '@/lib/format';
import type { AppointmentDetail } from '@/lib/types';
import { Badge, Card, Counter, Notice, PaymentBadge, Spinner, StatusBadge } from '@/components/ui';
import { PatientDashboard } from '@/components/PatientDashboard';

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

  const [reason, setReason] = useState('');

  async function respond(kind: 'accept' | 'decline') {
    setBusy(kind);
    setMessage(null);
    try {
      await api(`/appointments/${id}/${kind}`, { method: 'POST', body: kind === 'decline' ? { reason } : undefined });
      refreshSummary();
      setMessage({ tone: 'ok', text: kind === 'accept' ? 'Accepted. The video room was created and the patient was notified.' : 'Declined. The time is free again, any payment was refunded and the patient was told.' });
      await load();
    } catch (err) {
      setMessage({ tone: 'error', text: err instanceof Error ? err.message : 'Could not answer this request.' });
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

      {a.canRespond && (
        <Card title="This request is waiting for your answer">
          <p>Accepting creates the video room and tells the patient. Declining frees the time for someone else.</p>
          <div className="actions">
            <button className="btn btn-primary" disabled={busy !== null} onClick={() => void respond('accept')}>{busy === 'accept' ? 'Accepting…' : 'Accept and create video room'}</button>
          </div>
          <div className="inline-form">
            <label>Reason for declining (optional)<input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={200} /><Counter value={reason} max={200} /></label>
            <button className="btn btn-danger" disabled={busy !== null} onClick={() => void respond('decline')}>{busy === 'decline' ? 'Declining…' : 'Decline'}</button>
          </div>
        </Card>
      )}
      {a.phase === 'expired' && <Notice>This request was not answered before its start time, so it expired.</Notice>}
      {a.status === 'declined' && <Notice>You declined this request{a.declineReason ? `: ${a.declineReason}` : ''}.</Notice>}

      <Card title="Payment">
        <p><PaymentBadge a={a} /></p>
        {a.payment ? (
          <dl className="facts">
            <dt>Method</dt><dd>{a.payment.method === 'card' ? 'Card' : a.payment.method === 'wallet' ? 'Mobile wallet' : 'Pay at clinic'}</dd>
            <dt>Amount</dt><dd>{pkr(a.payment.total)}{a.payment.status === 'pay_at_clinic' ? ' (to collect at the visit)' : ''}</dd>
            <dt>Your fee</dt><dd>{pkr(a.payment.consultationFee)}</dd>
            <dt>Platform fee</dt><dd>{pkr(a.payment.platformFee)} (kept by Baymax)</dd>
            <dt>Transaction</dt><dd>{a.payment.transactionId}</dd>
            {a.refund && (<><dt>Refund</dt><dd>{a.refund.status === 'manual' ? 'Due: an administrator returns it through the payment gateway' : `${pkr(a.refund.amount)} returned to the patient`}{a.refund.reason ? ` (${a.refund.reason})` : ''}</dd></>)}
          </dl>
        ) : (
          <p className="muted">No payment record is attached to this appointment.</p>
        )}
        {a.payment?.test && <p className="muted small">Test payment: no money was taken.</p>}
      </Card>

      <Card title="Meeting room">
        {a.status === 'requested' ? (
          <p className="muted">The video room is created when you accept this request.</p>
        ) : a.status !== 'confirmed' ? (
          <p className="muted">This appointment is {a.status === 'no_show' ? 'marked as missed' : a.status}.</p>
        ) : a.canJoin && link ? (
          <>
            <p>The room is open.{a.type === 'chat' ? ' This is a chat-only booking: it opens with camera and microphone off, and you can talk in Messages or the room’s chat.' : ''}</p>
            <div className="actions">
              <Link className="btn btn-primary" href={`/appointments/${id}/call`}>Join call here ›</Link>
              <a className="btn" href={link} target="_blank" rel="noopener noreferrer">Open in a new tab</a>
            </div>
          </>
        ) : (
          <p className="muted">{detail.serverTime < a.startAt ? 'The room opens 5 minutes before the start.' : 'The session time has passed.'}</p>
        )}
        {detail.call.joins > 0 && (
          <p className="muted small">You joined {detail.call.joins} time{detail.call.joins === 1 ? '' : 's'}, first at {fmtDateTime(detail.call.firstJoinAt ?? a.startAt)}, for about {detail.call.minutes} minute{detail.call.minutes === 1 ? '' : 's'} in total.</p>
        )}
        {(a.status === 'confirmed' || a.status === 'completed') && (
          <div className="actions">
            <Link className="btn btn-small" href={`/messages/${id}`}>{detail.chat.canSend ? 'Message the patient' : 'View messages'}</Link>
          </div>
        )}
        <p className="muted small">The public Jitsi server may ask the first person in a room to sign in. Use your organisation&apos;s own Jitsi server in production.</p>
      </Card>

      {a.notesForSpecialist && (
        <Card title="Note from the patient">
          <p className="pre">{a.notesForSpecialist}</p>
        </Card>
      )}

      {!anyShared && <Notice>The patient did not share any health data for this appointment, so there is no patient dashboard to show.</Notice>}
      {anyShared && detail.sharedLocked && <Notice>{detail.sharedLocked}</Notice>}
      {detail.sharedData && <PatientDashboard data={detail.sharedData} />}
      {detail.sharedData && <p className="muted small">Opening shared data is recorded, so the patient and administrators can see that you looked.</p>}

      <Card title="Consultation notes">
        {!canWrite ? (
          <p className="muted">{a.status === 'cancelled' ? 'This appointment was cancelled.' : 'You can add notes once the session has started.'}</p>
        ) : (
          <form onSubmit={saveNotes} className="stack">
            <label>
              Notes for the patient&apos;s profile
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={6} maxLength={5000} />
              <Counter value={notes} max={5000} />
            </label>
            {me.role === 'doctor' ? (
              <label>
                Prescription
                <textarea value={prescription} onChange={(e) => setPrescription(e.target.value)} rows={4} maxLength={3000} placeholder="Medicine, dose, how often, for how long" />
                <Counter value={prescription} max={3000} />
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
