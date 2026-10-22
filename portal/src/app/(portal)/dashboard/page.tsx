'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { refreshSummary } from '@/lib/events';
import { fmtDate, fmtDateTime, fmtTime, safeHttps } from '@/lib/format';
import type { Appointment, Dashboard } from '@/lib/types';
import { Badge, Card, Notice, Spinner, StatusBadge } from '@/components/ui';

const REFRESH_MS = 30_000; // live state (Join / Prepare) is re-checked every 30 seconds

function TodayRow({ a }: { a: Appointment }) {
  const link = safeHttps(a.meetingLink);
  const finished = a.phase === 'past' || a.phase === 'cancelled';
  return (
    <li className={`row ${a.phase === 'live' ? 'row-live' : ''} ${finished ? 'row-done' : ''}`}>
      <div className="row-time">
        {a.phase === 'live' && <span className="live-dot" aria-hidden />}
        <strong>{fmtTime(a.startAt)}</strong>
      </div>
      <div className="row-main">
        <Link href={`/appointments/${a.id}`} className="row-title">{a.patientName || 'Patient'}</Link>
        <div className="muted small">{a.type === 'video' ? 'Video call' : 'Chat only'} · {a.durationMinutes} min</div>
      </div>
      <div className="row-actions">
        <StatusBadge a={a} />
        {a.canJoin && link && (
          <a className="btn btn-primary btn-small" href={link} target="_blank" rel="noopener noreferrer">Join call ›</a>
        )}
        {!a.canJoin && a.canPrepare && (
          <Link className="btn btn-small" href={`/appointments/${a.id}`}>Prepare ›</Link>
        )}
      </div>
    </li>
  );
}

function RequestRow({ a, onDone }: { a: Appointment; onDone: () => void }) {
  const [busy, setBusy] = useState<'accept' | 'decline' | null>(null);
  const [declining, setDeclining] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function act(kind: 'accept' | 'decline') {
    setBusy(kind);
    setError(null);
    try {
      await api(`/appointments/${a.id}/${kind}`, { method: 'POST', body: kind === 'decline' ? { reason } : undefined });
      refreshSummary();
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not answer this request.');
      setBusy(null);
    }
  }

  return (
    <li className="req">
      <div>
        <Link href={`/appointments/${a.id}`} className="row-title">{a.patientName || 'Patient'}</Link>
        <div className="muted small">
          {fmtDateTime(a.startAt)} · {a.type === 'video' ? 'Video call' : 'Chat only'} · {a.durationMinutes} min
          {a.payment ? (a.payment.status === 'paid' ? (a.payment.test ? ' · Paid (test)' : ' · Paid') : ' · Pay at clinic') : ''}
        </div>
        {a.notesForSpecialist && <div className="small pre">“{a.notesForSpecialist.slice(0, 160)}{a.notesForSpecialist.length > 160 ? '…' : ''}”</div>}
        {error && <div className="small" role="alert" style={{ color: 'var(--bad)' }}>{error}</div>}
        {declining && (
          <div className="inline-form" style={{ marginTop: 8 }}>
            <label>Reason for the patient (optional)<input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={200} /></label>
            <button className="btn btn-danger btn-small" disabled={busy !== null} onClick={() => void act('decline')}>{busy === 'decline' ? 'Declining…' : 'Confirm decline'}</button>
            <button className="btn btn-small" disabled={busy !== null} onClick={() => setDeclining(false)}>Back</button>
          </div>
        )}
      </div>
      {!declining && (
        <div className="row-actions">
          <button className="btn btn-primary btn-small" disabled={busy !== null} onClick={() => void act('accept')}>{busy === 'accept' ? 'Accepting…' : 'Accept'}</button>
          <button className="btn btn-small" disabled={busy !== null} onClick={() => setDeclining(true)}>Decline</button>
        </div>
      )}
    </li>
  );
}

export default function DashboardPage() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setData(await api<Dashboard>('/dashboard'));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the dashboard.');
    }
  }, []);

  useEffect(() => {
    void load();
    const t = setInterval(() => void load(), REFRESH_MS);
    return () => clearInterval(t);
  }, [load]);

  if (!data && !error) return <Spinner label="Loading your day" />;
  if (!data) return <Notice tone="error">{error}</Notice>;

  const { counts } = data;
  const summary =
    counts.consultationsToday === 0
      ? 'You have no consultations scheduled today.'
      : `You have ${counts.consultationsToday} consultation${counts.consultationsToday === 1 ? '' : 's'} scheduled today.`;

  return (
    <>
      <header className="page-head">
        <div>
          <h1>{data.greeting}, {data.name}</h1>
          <p className="muted">{summary}{counts.awaitingNotes > 0 && ` ${counts.awaitingNotes} finished session${counts.awaitingNotes === 1 ? ' is' : 's are'} waiting for notes.`}</p>
        </div>
        <div className="muted small">{fmtDate(data.serverTime)}</div>
      </header>

      {error && <Notice tone="error">{error} Showing the last data we had.</Notice>}

      <div className="metrics four">
        {data.cards.map((c) => (
          <Link key={c.key} href={c.key === 'messages' ? '/messages' : c.key === 'patients' || c.key === 'clients' || c.key === 'trainees' ? '/patients' : c.key === 'prescriptions' ? '/prescriptions' : '/appointments'} className={`metric ${c.warn ? 'metric-warn' : ''}`} style={{ textDecoration: 'none', color: 'inherit' }}>
            <span className="metric-value">{c.value}</span>
            <span className="metric-label">{c.label}</span>
            <span className="metric-hint">{c.hint}</span>
          </Link>
        ))}
      </div>

      <Card title={`New requests${data.requests.length ? ` (${data.requests.length})` : ''}`}>
        {data.requests.length === 0 ? (
          <p className="muted">No requests waiting. When a patient books you in the app, the request appears here. Accepting it creates the video room.</p>
        ) : (
          <ul className="rows">{data.requests.map((a) => <RequestRow key={a.id} a={a} onDone={() => void load()} />)}</ul>
        )}
      </Card>

      <Card title="Today's consultations" action={<Link className="link" href="/appointments">View all ›</Link>}>
        {data.today.length === 0 ? (
          <p className="muted">Nothing booked for today.</p>
        ) : (
          <ul className="rows">{data.today.map((a) => <TodayRow key={a.id} a={a} />)}</ul>
        )}
      </Card>

      <p className="muted small">
        <Badge>Not shown yet</Badge> Risk alerts, clients on track, posture flags and emotion adjustments need the AI engine&apos;s data, which is not connected to this portal yet.
      </p>
    </>
  );
}
