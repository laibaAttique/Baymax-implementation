'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { downloadCsv } from '@/lib/csv';
import { dayStart, fmtDateTime, fromInputDate, pkr, toInputDate } from '@/lib/format';
import type { PaymentBucket, PaymentRow, PaymentSummary } from '@/lib/types';
import { rangeProblem } from '@/lib/validate';
import { Badge, Card, Notice, Spinner } from '@/components/ui';

const BUCKETS: { value: PaymentBucket; label: string }[] = [
  { value: 'earned', label: 'Earned' },
  { value: 'upcoming', label: 'Upcoming' },
  { value: 'held', label: 'Waiting for your answer' },
  { value: 'clinic', label: 'Pay at clinic' },
  { value: 'due', label: 'Refund due' },
  { value: 'refunded', label: 'Refunded' },
];

const BUCKET_LABEL: Record<string, string> = Object.fromEntries(BUCKETS.map((b) => [b.value, b.label]));
const BUCKET_TONE: Record<string, 'good' | 'info' | 'warn' | 'bad' | 'neutral'> = { earned: 'good', upcoming: 'info', held: 'warn', clinic: 'warn', due: 'bad', refunded: 'neutral', void: 'neutral' };

/** What the specialist has earned from Baymax bookings (Module 15 on the web). The gateway is a test one: no real money moves. */
export default function PaymentsPage() {
  const [bucket, setBucket] = useState('');
  const [q, setQ] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [data, setData] = useState<{ summary: PaymentSummary; payments: PaymentRow[]; truncated: boolean } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const badRange = rangeProblem(from, to);
    if (badRange) {
      setError(badRange);
      return;
    }
    const params = new URLSearchParams();
    if (bucket) params.set('bucket', bucket);
    if (q.trim()) params.set('q', q.trim());
    const f = fromInputDate(from);
    const t = fromInputDate(to);
    if (f !== null) params.set('from', String(f));
    if (t !== null) params.set('to', String(t + 86_400_000));
    try {
      setData(await api(`/payments?${params}`));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load your payments.');
    }
  }, [bucket, q, from, to]);

  useEffect(() => {
    const t = setTimeout(() => void load(), 250);
    return () => clearTimeout(t);
  }, [load]);

  const quick = (days: number) => {
    setFrom(toInputDate(dayStart(-days)));
    setTo(toInputDate(dayStart(0)));
  };

  function exportCsv() {
    if (!data) return;
    downloadCsv(`baymax-payments-${toInputDate(Date.now())}.csv`, [
      ['Appointment date', 'Patient', 'Type', 'Appointment status', 'Payment status', 'Method', 'Consultation fee (PKR)', 'Platform fee (PKR)', 'Total (PKR)', 'Transaction', 'Test payment', 'Refund (PKR)', 'Refund reason'],
      ...data.payments.map((p) => [
        fmtDateTime(p.startAt), p.patientName, p.type, p.status, BUCKET_LABEL[p.bucket] ?? p.bucket, p.payment?.method ?? '',
        p.payment?.consultationFee ?? 0, p.payment?.platformFee ?? 0, p.payment?.total ?? 0, p.payment?.transactionId ?? '', p.payment?.test ? 'yes' : 'no',
        p.refund?.amount ?? '', p.refund?.reason ?? '',
      ]),
    ]);
  }

  const s = data?.summary;
  return (
    <>
      <header className="page-head">
        <div>
          <h1>Payments</h1>
          <p className="muted">What patients paid for your consultations. Your share is the consultation fee; the platform fee belongs to Baymax.</p>
        </div>
        <button type="button" className="btn" disabled={!data || data.payments.length === 0} onClick={exportCsv}>Download CSV</button>
      </header>

      <Card>
        <form className="filters" onSubmit={(e) => e.preventDefault()}>
          <label>Patient name<input type="search" value={q} onChange={(e) => setQ(e.target.value)} maxLength={80} placeholder="Search by name" /></label>
          <label>
            Status
            <select value={bucket} onChange={(e) => setBucket(e.target.value)}>
              <option value="">All</option>
              {BUCKETS.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
            </select>
          </label>
          <label>From<input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
          <label>To<input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></label>
          <div className="filter-actions">
            <button type="button" className="btn btn-small" onClick={() => quick(7)}>Last 7 days</button>
            <button type="button" className="btn btn-small" onClick={() => quick(30)}>Last 30 days</button>
            <button type="button" className="btn btn-small" onClick={() => { setQ(''); setBucket(''); setFrom(''); setTo(''); }}>Clear</button>
          </div>
        </form>
      </Card>

      {error && <Notice tone="error">{error}</Notice>}
      {!data && !error && <Spinner label="Loading payments" />}
      {s && (
        <div className="metrics four">
          <div className="metric"><span className="metric-value">{pkr(s.earned.amount)}</span><span className="metric-label">Earned</span><span className="metric-hint">{s.earned.count} finished session{s.earned.count === 1 ? '' : 's'}</span></div>
          <div className="metric"><span className="metric-value">{pkr(s.upcoming.amount)}</span><span className="metric-label">Upcoming</span><span className="metric-hint">{s.upcoming.count} accepted, not yet held</span></div>
          <div className={`metric ${s.held.count > 0 ? 'metric-warn' : ''}`}><span className="metric-value">{pkr(s.held.amount)}</span><span className="metric-label">Waiting for your answer</span><span className="metric-hint">{s.held.count} request{s.held.count === 1 ? '' : 's'}</span></div>
          <div className="metric"><span className="metric-value">{pkr(s.clinicDue.amount)}</span><span className="metric-label">To collect at the visit</span><span className="metric-hint">{s.clinicDue.count} pay-at-clinic booking{s.clinicDue.count === 1 ? '' : 's'}</span></div>
          <div className="metric"><span className="metric-value">{pkr(s.refunded.amount)}</span><span className="metric-label">Refunded</span><span className="metric-hint">{s.refunded.count} payment{s.refunded.count === 1 ? '' : 's'} returned</span></div>
          <div className={`metric ${s.due.count > 0 ? 'metric-warn' : ''}`}><span className="metric-value">{pkr(s.due.amount)}</span><span className="metric-label">Refund due</span><span className="metric-hint">Cancelled by the patient; an administrator decides</span></div>
        </div>
      )}

      {data && (
        <Card title={`${data.payments.length} payment${data.payments.length === 1 ? '' : 's'}${data.truncated ? ' (first 500)' : ''}`}>
          {data.payments.length === 0 ? (
            <p className="muted">No payments match these filters.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>When</th><th>Patient</th><th>Method</th><th className="num">Your fee</th><th className="num">Platform</th><th className="num">Total</th><th>Status</th><th><span className="sr-only">Open</span></th></tr></thead>
                <tbody>
                  {data.payments.map((p) => (
                    <tr key={p.appointmentId} className={p.bucket === 'refunded' || p.bucket === 'void' ? 'row-done' : ''}>
                      <td>{fmtDateTime(p.startAt)}</td>
                      <td>{p.patientName || 'Patient'}</td>
                      <td>{p.payment?.method === 'card' ? 'Card' : p.payment?.method === 'wallet' ? 'Wallet' : p.payment?.method === 'clinic' ? 'At clinic' : '—'}{p.payment?.test && <span className="muted small"> (test)</span>}</td>
                      <td className="num">{pkr(p.payment?.consultationFee ?? 0)}</td>
                      <td className="num">{pkr(p.payment?.platformFee ?? 0)}</td>
                      <td className="num">{pkr(p.payment?.total ?? 0)}</td>
                      <td><Badge tone={BUCKET_TONE[p.bucket] ?? 'neutral'}>{BUCKET_LABEL[p.bucket] ?? p.bucket}</Badge>{p.refund && <span className="muted small"> {pkr(p.refund.amount)}</span>}</td>
                      <td><Link className="link" href={`/appointments/${p.appointmentId}`}>Open ›</Link></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
      <p className="muted small">The payment gateway in Baymax is a test one: only published test cards work and no real money moves. Going live needs a merchant account (JazzCash) and a server that holds its secret key.</p>
    </>
  );
}
