'use client';

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { downloadCsv } from '@/lib/csv';
import { dayStart, fmtDateTime, fromInputDate, pkr, toInputDate } from '@/lib/format';
import type { PaymentBucket, PaymentRow, PaymentSummary, SpecialistPayments } from '@/lib/types';
import { rangeProblem, textProblem } from '@/lib/validate';
import { Badge, Card, Counter, Field, Notice, Spinner } from '@/components/ui';

const BUCKETS: { value: PaymentBucket; label: string }[] = [
  { value: 'earned', label: 'Earned' },
  { value: 'upcoming', label: 'Upcoming' },
  { value: 'held', label: 'Waiting for a specialist' },
  { value: 'clinic', label: 'Pay at clinic' },
  { value: 'due', label: 'Refund due' },
  { value: 'refunded', label: 'Refunded' },
];
const LABEL: Record<string, string> = Object.fromEntries(BUCKETS.map((b) => [b.value, b.label]));
const TONE: Record<string, 'good' | 'info' | 'warn' | 'bad' | 'neutral'> = { earned: 'good', upcoming: 'info', held: 'warn', clinic: 'warn', due: 'bad', refunded: 'neutral', void: 'neutral' };

interface Payments { summary: PaymentSummary; bySpecialist: SpecialistPayments[]; payments: PaymentRow[]; truncated: boolean }

/** Every payment on the platform: totals, per-specialist figures, and refunds. The gateway is a test one, so no real money moves. */
export default function PaymentsPage() {
  const [bucket, setBucket] = useState('');
  const [specialist, setSpecialist] = useState('');
  const [q, setQ] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [data, setData] = useState<Payments | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [refunding, setRefunding] = useState<PaymentRow | null>(null);
  const [reason, setReason] = useState('');
  const [reasonError, setReasonError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const badRange = rangeProblem(from, to);
    if (badRange) {
      setError(badRange);
      return;
    }
    const params = new URLSearchParams();
    if (bucket) params.set('bucket', bucket);
    if (specialist) params.set('specialist', specialist);
    if (q.trim()) params.set('q', q.trim());
    const f = fromInputDate(from);
    const t = fromInputDate(to);
    if (f !== null) params.set('from', String(f));
    if (t !== null) params.set('to', String(t + 86_400_000));
    try {
      setData(await api<Payments>(`/admin/payments?${params}`));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load the payments.');
    }
  }, [bucket, specialist, q, from, to]);

  // A link such as /payments?bucket=due opens the list already filtered (only values that exist are accepted).
  useEffect(() => {
    const wanted = new URLSearchParams(window.location.search).get('bucket');
    if (wanted && BUCKETS.some((b) => b.value === wanted)) setBucket(wanted);
  }, []);

  useEffect(() => {
    const t = setTimeout(() => void load(), 250);
    return () => clearTimeout(t);
  }, [load]);

  async function refund(e: FormEvent) {
    e.preventDefault();
    if (!refunding || busy) return;
    const problem = textProblem(reason, 'the reason', 3, 200);
    setReasonError(problem);
    if (problem) return;
    setBusy(true);
    setError(null);
    try {
      await api(`/admin/payments/${refunding.appointmentId}/refund`, { method: 'POST', body: { reason: reason.trim() } });
      setNotice(`Refund recorded for ${refunding.patientName || 'the patient'}: ${pkr(refunding.payment?.total ?? 0)}. They were told in the app.`);
      setRefunding(null);
      setReason('');
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not record the refund.');
    } finally {
      setBusy(false);
    }
  }

  function exportCsv() {
    if (!data) return;
    downloadCsv(`baymax-all-payments-${toInputDate(Date.now())}.csv`, [
      ['Appointment date', 'Patient', 'Specialist', 'Type', 'Appointment status', 'Payment status', 'Method', 'Consultation fee (PKR)', 'Platform fee (PKR)', 'Total (PKR)', 'Transaction', 'Test payment', 'Refund (PKR)', 'Refunded by', 'Refund reason'],
      ...data.payments.map((p) => [
        fmtDateTime(p.startAt), p.patientName, p.specialistName, p.type, p.status, LABEL[p.bucket] ?? p.bucket, p.payment?.method ?? '',
        p.payment?.consultationFee ?? 0, p.payment?.platformFee ?? 0, p.payment?.total ?? 0, p.payment?.transactionId ?? '', p.payment?.test ? 'yes' : 'no',
        p.refund?.amount ?? '', p.refund?.by ?? '', p.refund?.reason ?? '',
      ]),
    ]);
  }

  const s = data?.summary;
  // Only an appointment that is over, paid online and not yet refunded can be refunded here (the server checks again).
  const canRefund = (p: PaymentRow) => (p.payment?.status === 'paid' && !p.refund && ['cancelled', 'declined', 'no_show', 'completed'].includes(p.status)) || p.bucket === 'due';

  return (
    <>
      <header className="page-head">
        <div>
          <h1>Payments</h1>
          <p className="muted">Every consultation payment. Declined, cancelled and unanswered requests are refunded automatically; a patient who cancelled is refunded here, by you.</p>
        </div>
        <button type="button" className="btn" disabled={!data || data.payments.length === 0} onClick={exportCsv}>Download CSV</button>
      </header>
      {notice && <Notice tone="ok">{notice}</Notice>}
      {error && <Notice tone="error">{error}</Notice>}

      <Card>
        <form className="filters" onSubmit={(e) => e.preventDefault()}>
          <label>Patient or specialist<input type="search" value={q} onChange={(e) => setQ(e.target.value)} maxLength={80} placeholder="Search by name" /></label>
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
            <button type="button" className="btn btn-small" onClick={() => { setFrom(toInputDate(dayStart(-7))); setTo(toInputDate(dayStart(0))); }}>Last 7 days</button>
            <button type="button" className="btn btn-small" onClick={() => { setFrom(toInputDate(dayStart(-30))); setTo(toInputDate(dayStart(0))); }}>Last 30 days</button>
            <button type="button" className="btn btn-small" onClick={() => { setQ(''); setBucket(''); setSpecialist(''); setFrom(''); setTo(''); }}>Clear</button>
            {specialist && <Badge tone="info">One specialist</Badge>}
          </div>
        </form>
      </Card>

      {!data && !error && <Spinner label="Loading payments" />}
      {s && (
        <div className="metrics four">
          <div className="metric"><span className="metric-value">{pkr(s.gross)}</span><span className="metric-label">Taken online</span><span className="metric-hint">Earned, upcoming and waiting, before refunds</span></div>
          <div className="metric"><span className="metric-value">{pkr(s.platformFees)}</span><span className="metric-label">Platform fees</span><span className="metric-hint">Kept by Baymax</span></div>
          <div className="metric"><span className="metric-value">{pkr(s.refunded.amount)}</span><span className="metric-label">Refunded</span><span className="metric-hint">{s.refunded.count} payment{s.refunded.count === 1 ? '' : 's'}</span></div>
          <div className={`metric ${s.due.count > 0 ? 'metric-warn' : ''}`}><span className="metric-value">{pkr(s.due.amount)}</span><span className="metric-label">Refund due</span><span className="metric-hint">{s.due.count} for you to decide</span></div>
          <div className="metric"><span className="metric-value">{pkr(s.clinicDue.amount)}</span><span className="metric-label">Pay at clinic</span><span className="metric-hint">{s.clinicDue.count} booking{s.clinicDue.count === 1 ? '' : 's'}, not taken online</span></div>
        </div>
      )}

      {data && data.bySpecialist.length > 0 && (
        <Card title="By specialist">
          <div className="table-wrap">
            <table>
              <thead><tr><th>Specialist</th><th className="num">Payments</th><th className="num">Earned</th><th className="num">Upcoming</th><th className="num">Waiting</th><th className="num">Refunded</th><th><span className="sr-only">Filter</span></th></tr></thead>
              <tbody>
                {data.bySpecialist.map((b) => (
                  <tr key={b.specialistId}>
                    <td>{b.name || 'Specialist'}</td>
                    <td className="num">{b.summary.count}</td>
                    <td className="num">{pkr(b.summary.earned.amount)}</td>
                    <td className="num">{pkr(b.summary.upcoming.amount)}</td>
                    <td className="num">{pkr(b.summary.held.amount)}</td>
                    <td className="num">{pkr(b.summary.refunded.amount)}</td>
                    <td><button type="button" className="btn btn-small" onClick={() => setSpecialist(specialist === b.specialistId ? '' : b.specialistId)}>{specialist === b.specialistId ? 'Show all' : 'Only this one'}</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {refunding && (
        <Card title={`Refund ${pkr(refunding.payment?.total ?? 0)} to ${refunding.patientName || 'the patient'}`}>
          <form className="stack" onSubmit={refund} noValidate>
            <p>Appointment with {refunding.specialistName} on {fmtDateTime(refunding.startAt)} ({refunding.status.replace('_', ' ')}). {refunding.payment?.test ? 'This is a test payment: no real money moves.' : 'This is a live payment: you must return it through the payment gateway as well. The patient is told it will be returned.'}</p>
            <Field label="Reason (shown in the record and to the patient)" error={reasonError}>
              <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={200} aria-invalid={reasonError ? true : undefined} autoFocus />
              <Counter value={reason} max={200} />
            </Field>
            <div className="actions">
              <button className="btn btn-primary" disabled={busy}>{busy ? 'Saving…' : 'Record refund'}</button>
              <button type="button" className="btn" disabled={busy} onClick={() => { setRefunding(null); setReason(''); setReasonError(null); }}>Cancel</button>
            </div>
          </form>
        </Card>
      )}

      {data && (
        <Card title={`${data.payments.length} payment${data.payments.length === 1 ? '' : 's'}${data.truncated ? ' (first 500)' : ''}`}>
          {data.payments.length === 0 ? <p className="muted">No payments match these filters.</p> : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>When</th><th>Patient</th><th>Specialist</th><th>Method</th><th className="num">Fee</th><th className="num">Platform</th><th className="num">Total</th><th>Status</th><th><span className="sr-only">Actions</span></th></tr></thead>
                <tbody>
                  {data.payments.map((p) => (
                    <tr key={p.appointmentId} className={p.bucket === 'refunded' || p.bucket === 'void' ? 'row-done' : ''}>
                      <td>{fmtDateTime(p.startAt)}</td>
                      <td>{p.patientName || 'Patient'}</td>
                      <td>{p.specialistName}</td>
                      <td>{p.payment?.method === 'card' ? 'Card' : p.payment?.method === 'wallet' ? 'Wallet' : p.payment?.method === 'clinic' ? 'At clinic' : '—'}{p.payment?.test && <span className="muted small"> (test)</span>}</td>
                      <td className="num">{pkr(p.payment?.consultationFee ?? 0)}</td>
                      <td className="num">{pkr(p.payment?.platformFee ?? 0)}</td>
                      <td className="num">{pkr(p.payment?.total ?? 0)}</td>
                      <td><Badge tone={TONE[p.bucket] ?? 'neutral'}>{LABEL[p.bucket] ?? p.bucket}</Badge>{p.refund && <span className="muted small"> {p.refund.by}</span>}</td>
                      <td>{canRefund(p) && <button type="button" className="btn btn-small btn-danger" disabled={busy} onClick={() => { setRefunding(p); setReason(''); setReasonError(null); setNotice(null); }}>Refund</button>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
      <p className="muted small">The payment gateway is a test one: only published test cards work and no real money moves. Going live needs a merchant account (JazzCash) and a server holding its secret key, which only that server may use to write payments.</p>
    </>
  );
}
