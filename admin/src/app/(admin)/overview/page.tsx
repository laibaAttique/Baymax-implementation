'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import type { Overview } from '@/lib/types';
import { Card, Notice, Spinner } from '@/components/ui';

const STATUS_LABELS: Record<string, string> = {
  pending_payment: 'Awaiting payment',
  requested: 'Awaiting a specialist',
  confirmed: 'Confirmed',
  completed: 'Completed',
  cancelled: 'Cancelled',
  declined: 'Declined',
  no_show: 'Missed',
};

export default function OverviewPage() {
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<Overview>('/admin/overview').then(setData).catch((e) => setError(e instanceof Error ? e.message : 'Could not load the overview.'));
  }, []);

  if (error) return <Notice tone="error">{error}</Notice>;
  if (!data) return <Spinner label="Loading the overview" />;
  return (
    <>
      <header className="page-head"><div><h1>Overview</h1><p className="muted">How Baymax consultations are doing right now.</p></div></header>
      <div className="metrics">
        <div className={`metric ${data.applications.pending > 0 ? 'metric-warn' : ''}`}><span className="metric-value">{data.applications.pending}</span><span className="metric-label">Registrations waiting</span></div>
        <div className="metric"><span className="metric-value">{data.specialists.total}</span><span className="metric-label">Specialists</span></div>
        <div className="metric"><span className="metric-value">{data.appointments.total}</span><span className="metric-label">Appointments, all time</span></div>
      </div>
      {data.applications.pending > 0 && <Notice>{data.applications.pending} registration{data.applications.pending === 1 ? ' is' : 's are'} waiting for your decision. <Link className="link" href="/registrations">Review them ›</Link></Notice>}
      <Card title="Specialists by type">
        <div className="tiles">
          <div className="tile"><span className="tile-value">{data.specialists.doctor}</span><span className="tile-label">Doctors</span></div>
          <div className="tile"><span className="tile-value">{data.specialists.nutritionist}</span><span className="tile-label">Nutritionists</span></div>
          <div className="tile"><span className="tile-value">{data.specialists.trainer}</span><span className="tile-label">Trainers</span></div>
        </div>
      </Card>
      <Card title="Appointments by status">
        {Object.keys(data.appointments.byStatus).length === 0 ? <p className="muted">No appointments yet.</p> : (
          <div className="tiles">
            {Object.entries(data.appointments.byStatus).map(([k, v]) => (
              <div className="tile" key={k}><span className="tile-value">{v}</span><span className="tile-label">{STATUS_LABELS[k] ?? k}</span></div>
            ))}
          </div>
        )}
      </Card>
    </>
  );
}
