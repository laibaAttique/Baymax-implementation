'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { fmtDate, fmtTime, safeHttps } from '@/lib/format';
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

      <div className="metrics">
        <div className="metric"><span className="metric-value">{counts.consultationsToday}</span><span className="metric-label">Consultations today</span></div>
        <div className="metric"><span className="metric-value">{counts.upcoming7Days}</span><span className="metric-label">Upcoming, next 7 days</span></div>
        <div className="metric"><span className="metric-value">{counts.patients}</span><span className="metric-label">Patients</span></div>
        <div className={`metric ${counts.awaitingNotes > 0 ? 'metric-warn' : ''}`}><span className="metric-value">{counts.awaitingNotes}</span><span className="metric-label">Awaiting notes</span></div>
      </div>

      <Card title="Today's consultations" action={<Link className="link" href="/appointments">View all ›</Link>}>
        {data.today.length === 0 ? (
          <p className="muted">Nothing booked for today.</p>
        ) : (
          <ul className="rows">{data.today.map((a) => <TodayRow key={a.id} a={a} />)}</ul>
        )}
      </Card>

      <p className="muted small">
        <Badge>Not shown yet</Badge> Risk alerts, diet reviews and posture flags need the AI engine&apos;s data, which is not connected to this portal yet.
      </p>
    </>
  );
}
