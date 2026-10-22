'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { refreshSummary } from '@/lib/events';
import { fmtDateTime, pkr } from '@/lib/format';
import type { AdminApplication } from '@/lib/types';
import { Badge, Card, Notice, Spinner } from '@/components/ui';

const TYPE_LABEL = { doctor: 'Doctor', nutritionist: 'Nutritionist', trainer: 'Trainer' } as const;

/** Specialist registrations. A registration grants nothing until it is approved here. */
export default function RegistrationsPage() {
  const [apps, setApps] = useState<AdminApplication[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [rejecting, setRejecting] = useState<string | null>(null);
  const [reason, setReason] = useState('');

  const load = useCallback(async () => {
    try {
      setApps((await api<{ applications: AdminApplication[] }>('/admin/applications')).applications);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load registrations.');
    }
  }, []);

  useEffect(() => {
    void load();
    const t = setInterval(() => void load(), 30_000);
    return () => clearInterval(t);
  }, [load]);

  async function decide(a: AdminApplication, kind: 'approve' | 'reject') {
    if (kind === 'approve' && !window.confirm(`Approve ${a.name} as a ${TYPE_LABEL[a.type] ?? a.type}?\n\nLicence number: ${a.licenseNumber}\n\nPatients will be able to book them in the Baymax app. Only approve if you have checked the licence number with the issuing body.`)) return;
    if (kind === 'reject' && reason.trim().length > 300) {
      setError('The reason can be at most 300 characters.');
      return;
    }
    setBusy(a.uid);
    setError(null);
    setNotice(null);
    try {
      await api(`/admin/applications/${a.uid}/${kind}`, { method: 'POST', body: kind === 'reject' ? { reason } : undefined });
      setNotice(kind === 'approve' ? `${a.name} is approved. They can now sign in to the specialist portal and patients can book them in the app.` : `${a.name}'s registration was rejected.`);
      setRejecting(null);
      setReason('');
      await load();
      refreshSummary();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save that.');
    } finally {
      setBusy(null);
    }
  }

  const pending = (apps ?? []).filter((a) => a.status === 'pending');
  const decided = (apps ?? []).filter((a) => a.status !== 'pending');

  return (
    <>
      <header className="page-head"><div><h1>Registrations</h1><p className="muted">Doctors, nutritionists and trainers who registered on the specialist portal. Check the licence number with the issuing body before you approve.</p></div></header>
      {notice && <Notice tone="ok">{notice}</Notice>}
      {error && <Notice tone="error">{error}</Notice>}
      {!apps && !error && <Spinner label="Loading registrations" />}
      {apps && (
        <Card title={`Waiting for approval${pending.length ? ` (${pending.length})` : ''}`}>
          {pending.length === 0 && <p className="muted">Nothing is waiting. New registrations appear here by themselves.</p>}
          {pending.map((a) => (
            <div key={a.uid} className="req">
              <div>
                <strong>{a.name}</strong> <Badge>{TYPE_LABEL[a.type] ?? a.type}</Badge>
                <div className="muted small">{a.specialty} · {a.yearsOfExperience} years · {a.fees ? `${pkr(a.fees.video)} video / ${pkr(a.fees.chat)} chat` : 'no fees given'}</div>
                <div className="small">Licence number: <strong>{a.licenseNumber}</strong></div>
                <div className="small">{a.email} · sent {fmtDateTime(a.submittedAt)}</div>
                {rejecting === a.uid && (
                  <div className="inline-form" style={{ marginTop: 8 }}>
                    <label>Reason (shown to the applicant, optional)<input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} /></label>
                    <button className="btn btn-danger btn-small" disabled={busy === a.uid} onClick={() => void decide(a, 'reject')}>Confirm reject</button>
                    <button className="btn btn-small" onClick={() => setRejecting(null)}>Back</button>
                  </div>
                )}
              </div>
              {rejecting !== a.uid && (
                <div className="row-actions">
                  <button className="btn btn-primary btn-small" disabled={busy === a.uid} onClick={() => void decide(a, 'approve')}>{busy === a.uid ? 'Saving…' : 'Approve'}</button>
                  <button className="btn btn-small" disabled={busy === a.uid} onClick={() => setRejecting(a.uid)}>Reject</button>
                </div>
              )}
            </div>
          ))}
        </Card>
      )}
      {decided.length > 0 && (
        <Card title={`Earlier decisions (${decided.length})`}>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Name</th><th>Type</th><th>Email</th><th>Licence</th><th>Decision</th></tr></thead>
              <tbody>
                {decided.map((a) => (
                  <tr key={a.uid}>
                    <td>{a.name}</td><td>{TYPE_LABEL[a.type] ?? a.type}</td><td>{a.email}</td><td>{a.licenseNumber}</td>
                    <td>{a.status === 'approved' ? <Badge tone="good">Approved</Badge> : <Badge tone="bad">Rejected</Badge>}{a.rejectReason ? ` ${a.rejectReason}` : ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </>
  );
}
