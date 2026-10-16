'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { fmtDateTime } from '@/lib/format';
import type { PatientSummary } from '@/lib/types';
import { Badge, Card, Notice, Spinner } from '@/components/ui';

/** "My patients": everyone this specialist has an accepted appointment with. */
export default function PatientsPage() {
  const [q, setQ] = useState('');
  const [list, setList] = useState<PatientSummary[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setList((await api<{ patients: PatientSummary[] }>(`/patients?q=${encodeURIComponent(q.trim())}`)).patients);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load your patients.');
    }
  }, [q]);

  useEffect(() => {
    const t = setTimeout(() => void load(), 250);
    return () => clearTimeout(t);
  }, [load]);

  return (
    <>
      <header className="page-head">
        <div>
          <h1>My patients</h1>
          <p className="muted">People you have an accepted appointment with. Open a record to see your history with them, set plans and review their food log.</p>
        </div>
      </header>
      <Card>
        <label>Search by name<input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Patient name" /></label>
      </Card>
      {error && <Notice tone="error">{error}</Notice>}
      {!list && !error && <Spinner label="Loading patients" />}
      {list && (
        <Card title={`${list.length} patient${list.length === 1 ? '' : 's'}`}>
          {list.length === 0 ? (
            <p className="muted">No patients yet. A patient appears here once you accept their appointment.</p>
          ) : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>Name</th><th>Appointments</th><th>Last visit</th><th>Next visit</th><th>Notes</th><th><span className="sr-only">Open</span></th></tr></thead>
                <tbody>
                  {list.map((p) => (
                    <tr key={p.patientId}>
                      <td>{p.name}</td>
                      <td>{p.appointments}</td>
                      <td>{p.lastVisit ? fmtDateTime(p.lastVisit) : 'None yet'}</td>
                      <td>{p.nextVisit ? fmtDateTime(p.nextVisit) : 'Not booked'}</td>
                      <td>{p.notesWritten ? <Badge tone="good">{p.notesWritten} written</Badge> : <Badge tone="neutral">None</Badge>}</td>
                      <td><Link className="link" href={`/patients/${p.patientId}`}>Open record ›</Link></td>
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
