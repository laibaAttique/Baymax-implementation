'use client';

import { use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { useMe } from '@/lib/auth';
import { fmtDate, fmtDateTime, statusLabel } from '@/lib/format';
import type { PatientRecord } from '@/lib/types';
import { Badge, Card, Notice, Spinner } from '@/components/ui';
import { PatientDashboard } from '@/components/PatientDashboard';
import { DietPlanEditor, WorkoutPlanEditor } from '@/components/PlanEditors';

function DayReview({ pid, date, existing, onChanged }: { pid: string; date: string; existing?: PatientRecord['reviews'][number]; onChanged: () => void }) {
  const [note, setNote] = useState(existing?.note ?? '');
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function review(status: 'approved' | 'flagged') {
    setBusy(status);
    setError(null);
    try {
      await api(`/patients/${pid}/diet-reviews/${date}`, { method: 'PUT', body: { status, note } });
      onChanged();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the review.');
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="review-actions">
      {existing && <Badge tone={existing.status === 'approved' ? 'good' : 'warn'}>{existing.status === 'approved' ? 'Approved' : 'Flagged'}</Badge>}
      <label>Note for the patient (needed to flag)<input value={note} maxLength={600} onChange={(e) => setNote(e.target.value)} /></label>
      <button className="btn btn-small" disabled={busy !== null} onClick={() => void review('approved')}>{busy === 'approved' ? 'Saving…' : 'Approve this day'}</button>
      <button className="btn btn-small btn-danger" disabled={busy !== null} onClick={() => void review('flagged')}>{busy === 'flagged' ? 'Saving…' : 'Flag this day'}</button>
      {error && <span role="alert" className="small" style={{ color: 'var(--bad)' }}>{error}</span>}
    </div>
  );
}

/** One patient's record for this specialist: history, plans, food-log review, and the data the patient shared. */
export default function PatientRecordPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const me = useMe();
  const [rec, setRec] = useState<PatientRecord | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setRec(await api<PatientRecord>(`/patients/${id}`));
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load this record.');
    }
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  if (error && !rec) {
    return (
      <>
        <Link className="link" href="/patients">‹ My patients</Link>
        <Notice tone="error">{error}</Notice>
      </>
    );
  }
  if (!rec) return <Spinner label="Loading the record" />;

  const reviewFor = (date: string) => rec.reviews.find((r) => r.date === date);
  const role = me.role;
  const showDiet = role === 'doctor' || role === 'nutritionist';
  const showWorkout = role === 'doctor' || role === 'trainer';

  return (
    <>
      <Link className="link" href="/patients">‹ My patients</Link>
      <header className="page-head">
        <div>
          <h1>{rec.patient.name}</h1>
          <p className="muted">Your record of this patient. Their own health data appears only while an accepted appointment&apos;s sharing window is open, and only what they chose to share.</p>
        </div>
      </header>

      <Card title="Your appointments with this patient">
        <div className="table-wrap">
          <table>
            <thead><tr><th>When</th><th>Type</th><th>Status</th><th>Notes and prescription</th><th><span className="sr-only">Open</span></th></tr></thead>
            <tbody>
              {rec.appointments.map((a) => (
                <tr key={a.id}>
                  <td>{fmtDateTime(a.startAt)}</td>
                  <td>{a.type === 'video' ? 'Video call' : 'Chat only'}</td>
                  <td>{statusLabel(a.status)}</td>
                  <td className="wrap">
                    {a.consultation ? (
                      <>
                        {a.consultation.notes && <div className="pre small">{a.consultation.notes}</div>}
                        {a.consultation.prescription && <div className="pre small"><strong>Prescription:</strong> {a.consultation.prescription}</div>}
                      </>
                    ) : <span className="muted small">None written</span>}
                  </td>
                  <td><Link className="link" href={`/appointments/${a.id}`}>Open ›</Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>

      {rec.sharedLocked && <Notice>{rec.sharedLocked}</Notice>}
      {rec.sharedData && (
        <PatientDashboard
          data={rec.sharedData}
          dayActions={rec.access.canReviewDiet ? (date) => <DayReview pid={id} date={date} existing={reviewFor(date)} onChanged={() => void load()} /> : undefined}
        />
      )}

      {role === 'nutritionist' && rec.reviews.length > 0 && (
        <Card title="Your food log reviews">
          <ul className="plain">
            {rec.reviews.map((r) => <li key={r.date}>{r.date}: <strong>{r.status === 'approved' ? 'Approved' : 'Flagged'}</strong>{r.note ? `, ${r.note}` : ''}</li>)}
          </ul>
        </Card>
      )}

      {showDiet && <DietPlanEditor key={`d${rec.plans.diet?.at ?? 0}`} pid={id} current={rec.plans.diet} patientChoice={rec.patientChoice.diet} canEdit={rec.access.canEditDiet} days={rec.access.planEditDays} onChanged={() => void load()} />}
      {showWorkout && <WorkoutPlanEditor key={`w${rec.plans.workout?.at ?? 0}`} pid={id} current={rec.plans.workout} patientChoice={rec.patientChoice.workout} canEdit={rec.access.canEditWorkout} days={rec.access.planEditDays} onChanged={() => void load()} />}
      {role === 'trainer' && rec.plans.diet && <Notice>A diet plan by {rec.plans.diet.by.name} ({rec.plans.diet.by.role}) is in place for this patient. Only doctors and nutritionists can change it.</Notice>}
      <p className="muted small">Opening this record is logged, so the patient and administrators can see that you looked ({fmtDate(Date.now())}).</p>
    </>
  );
}
