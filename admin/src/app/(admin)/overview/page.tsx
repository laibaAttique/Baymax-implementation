'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import type { Overview } from '@/lib/types';
import { Card, Notice, Spinner } from '@/components/ui';
import { pkr } from '@/lib/format';

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
      {data.payments.refundsDue.count > 0 && <Notice>{data.payments.refundsDue.count} paid appointment{data.payments.refundsDue.count === 1 ? ' was' : 's were'} cancelled without a refund. <Link className="link" href="/payments?bucket=due">Decide on them ›</Link></Notice>}
      {data.applications.pending > 0 && <Notice>{data.applications.pending} registration{data.applications.pending === 1 ? ' is' : 's are'} waiting for your decision. <Link className="link" href="/registrations">Review them ›</Link></Notice>}
      <Card title="Specialists by type">
        <div className="tiles">
          <div className="tile"><span className="tile-value">{data.specialists.doctor}</span><span className="tile-label">Doctors</span></div>
          <div className="tile"><span className="tile-value">{data.specialists.nutritionist}</span><span className="tile-label">Nutritionists</span></div>
          <div className="tile"><span className="tile-value">{data.specialists.trainer}</span><span className="tile-label">Trainers</span></div>
        </div>
      </Card>
      <Card title="Money, calls and messages" action={<Link className="link" href="/payments">All payments ›</Link>}>
        <div className="tiles">
          <div className="tile"><span className="tile-value">{pkr(data.payments.gross)}</span><span className="tile-label">Taken online</span></div>
          <div className="tile"><span className="tile-value">{pkr(data.payments.platformFees)}</span><span className="tile-label">Platform fees</span></div>
          <div className="tile"><span className="tile-value">{pkr(data.payments.refunded.amount)}</span><span className="tile-label">Refunded ({data.payments.refunded.count})</span></div>
          <div className="tile"><span className="tile-value">{data.payments.refundsDue.count}</span><span className="tile-label">Refunds for you to decide</span></div>
          <div className="tile"><span className="tile-value">{data.calls.sessions}</span><span className="tile-label">Video sessions opened ({data.calls.minutes} min)</span></div>
          <div className="tile"><span className="tile-value">{data.messages.total}</span><span className="tile-label">Messages in {data.messages.conversations} conversation{data.messages.conversations === 1 ? '' : 's'}</span></div>
        </div>
        {data.payments.testPayments > 0 && <p className="muted small">{data.payments.testPayments} of the {data.payments.count} payments are test payments: no real money moved.</p>}
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
