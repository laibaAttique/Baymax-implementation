'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { useMe } from '@/lib/auth';
import { fmtDateTime } from '@/lib/format';
import type { Prescription } from '@/lib/types';
import { Card, Notice, Spinner } from '@/components/ui';

/** Every prescription this doctor has written (FR-6). */
export default function PrescriptionsPage() {
  const me = useMe();
  const [list, setList] = useState<Prescription[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (me.role !== 'doctor') return;
    api<{ prescriptions: Prescription[] }>('/prescriptions').then((r) => setList(r.prescriptions)).catch((e) => setError(e instanceof Error ? e.message : 'Could not load prescriptions.'));
  }, [me.role]);

  if (me.role !== 'doctor') return <Notice>Only doctors write prescriptions.</Notice>;
  return (
    <>
      <header className="page-head">
        <div>
          <h1>Prescriptions</h1>
          <p className="muted">Everything you have prescribed. To write a new one, open the appointment and use Consultation notes.</p>
        </div>
      </header>
      {error && <Notice tone="error">{error}</Notice>}
      {!list && !error && <Spinner label="Loading prescriptions" />}
      {list && (
        <Card title={`${list.length} prescription${list.length === 1 ? '' : 's'}`}>
          {list.length === 0 ? <p className="muted">You have not written any prescriptions yet.</p> : (
            <ul className="rows">
              {list.map((p) => (
                <li key={p.appointmentId} className="row" style={{ gridTemplateColumns: '1fr auto' }}>
                  <div>
                    <strong>{p.patientName || 'Patient'}</strong> <span className="muted small">{fmtDateTime(p.startAt)}</span>
                    <div className="pre">{p.prescription}</div>
                  </div>
                  <Link className="link" href={`/appointments/${p.appointmentId}`}>Open ›</Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </>
  );
}
