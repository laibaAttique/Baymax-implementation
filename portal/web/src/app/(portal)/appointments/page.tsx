'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { dayStart, fmtDateTime, fromInputDate, pkr, toInputDate } from '@/lib/format';
import type { Appointment } from '@/lib/types';
import { Card, Notice, PaymentBadge, Spinner, StatusBadge } from '@/components/ui';

export default function AppointmentsPage() {
  const [status, setStatus] = useState('');
  const [q, setQ] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [list, setList] = useState<Appointment[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const params = new URLSearchParams();
    if (status) params.set('status', status);
    if (q.trim()) params.set('q', q.trim());
    const f = fromInputDate(from);
    const t = fromInputDate(to);
    if (f !== null) params.set('from', String(f));
    if (t !== null) params.set('to', String(t + 86_400_000)); // the "to" day is included
    try {
      const r = await api<{ appointments: Appointment[] }>(`/appointments?${params}`);
      setList(r.appointments);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load appointments.');
    }
  }, [status, q, from, to]);

  // Typing in the name box waits a moment before asking the server again.
  useEffect(() => {
    const t = setTimeout(() => void load(), 250);
    return () => clearTimeout(t);
  }, [load]);

  const quick = (days: number) => {
    setFrom(toInputDate(dayStart(0)));
    setTo(toInputDate(dayStart(days)));
  };

  return (
    <>
      <header className="page-head">
        <h1>Appointments</h1>
      </header>

      <Card>
        <form className="filters" onSubmit={(e) => e.preventDefault()}>
          <label>
            Patient name
            <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search by name" />
          </label>
          <label>
            Status
            <select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All</option>
              <option value="confirmed">Confirmed</option>
              <option value="completed">Completed</option>
              <option value="cancelled">Cancelled</option>
              <option value="no_show">Missed</option>
            </select>
          </label>
          <label>
            From
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label>
            To
            <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </label>
          <div className="filter-actions">
            <button type="button" className="btn btn-small" onClick={() => quick(0)}>Today</button>
            <button type="button" className="btn btn-small" onClick={() => quick(7)}>Next 7 days</button>
            <button type="button" className="btn btn-small" onClick={() => { setQ(''); setStatus(''); setFrom(''); setTo(''); }}>Clear</button>
          </div>
        </form>
      </Card>

      {error && <Notice tone="error">{error}</Notice>}
      {!list && !error && <Spinner label="Loading appointments" />}
      {list && (
        <Card title={`${list.length} appointment${list.length === 1 ? '' : 's'}`}>
          {list.length === 0 ? (
            <p className="muted">No appointments match these filters.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>When</th><th>Patient</th><th>Type</th><th>Fee</th><th>Payment</th><th>Status</th><th><span className="sr-only">Open</span></th></tr>
                </thead>
                <tbody>
                  {list.map((a) => (
                    <tr key={a.id} className={a.phase === 'past' || a.phase === 'cancelled' ? 'row-done' : ''}>
                      <td>{fmtDateTime(a.startAt)}</td>
                      <td>{a.patientName || 'Patient'}{a.consultation && <span className="muted small"> · notes added</span>}</td>
                      <td>{a.type === 'video' ? 'Video call' : 'Chat only'}</td>
                      <td>{pkr(a.fee)}</td>
                      <td><PaymentBadge a={a} /></td>
                      <td><StatusBadge a={a} /></td>
                      <td><Link className="link" href={`/appointments/${a.id}`}>Open ›</Link></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </>
  );
}
