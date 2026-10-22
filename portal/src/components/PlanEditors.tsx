'use client';

import { useEffect, useState } from 'react';
import { api } from '@/lib/api';
import { fmtDate } from '@/lib/format';
import type { DietPlan, LibraryExercise, WorkoutDayPlan, WorkoutItem, WorkoutPlan } from '@/lib/types';
import { Badge, Card, Notice } from '@/components/ui';
import { dietPlanProblem, workoutPlanProblem } from '@/lib/validate';

const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const lines = (s: string) => s.split('\n').map((x) => x.trim()).filter(Boolean);
const num = (s: string) => (s.trim() === '' ? undefined : Number(s));

function PlanHeader({ plan, patientChoice }: { plan: { status: string; by: { name: string; role: string }; at: number; note: string }; patientChoice: 'baymax' | 'specialist' }) {
  return (
    <p className="muted small">
      Current plan: <Badge tone={plan.status === 'approved' ? 'good' : 'info'}>{plan.status === 'approved' ? 'Approved as is' : 'Changed'}</Badge> by {plan.by.name} ({plan.by.role}) on {fmtDate(plan.at)}.
      {plan.status === 'modified' && (patientChoice === 'baymax' ? ' The patient has chosen to use Baymax\'s own plan instead.' : ' The patient is following it.')}
    </p>
  );
}

/** Diet plan (FR-5, FR-9): a nutritionist or doctor approves the patient's plan as it is, or sets a target, macros, foods to avoid and tips. */
export function DietPlanEditor({ pid, current, patientChoice, canEdit, days, onChanged }: { pid: string; current: DietPlan | null; patientChoice: 'baymax' | 'specialist'; canEdit: boolean; days: number; onChanged: () => void }) {
  const [kcal, setKcal] = useState(current?.targetKcal?.toString() ?? '');
  const [protein, setProtein] = useState(current?.proteinG?.toString() ?? '');
  const [carbs, setCarbs] = useState(current?.carbsG?.toString() ?? '');
  const [fat, setFat] = useState(current?.fatG?.toString() ?? '');
  const [avoid, setAvoid] = useState(current?.avoid.join('\n') ?? '');
  const [tips, setTips] = useState(current?.tips.join('\n') ?? '');
  const [note, setNote] = useState(current?.note ?? '');
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);

  async function save(status: 'approved' | 'modified') {
    if (busy) return;
    if (status === 'modified') {
      const problem = dietPlanProblem({ kcal, protein, carbs, fat, avoid: lines(avoid), tips: lines(tips), note });
      if (problem) {
        setMsg({ tone: 'error', text: problem });
        return;
      }
    }
    setBusy(status);
    setMsg(null);
    try {
      await api(`/patients/${pid}/plans/diet`, {
        method: 'PUT',
        body: status === 'approved'
          ? { status, note }
          : { status, note, targetKcal: num(kcal), proteinG: num(protein), carbsG: num(carbs), fatG: num(fat), avoid: lines(avoid), tips: lines(tips) },
      });
      setMsg({ tone: 'ok', text: status === 'approved' ? 'Approved. The patient was told.' : 'Saved. The patient sees it in the Baymax app and was told.' });
      onChanged();
    } catch (e) {
      setMsg({ tone: 'error', text: e instanceof Error ? e.message : 'Could not save.' });
    } finally {
      setBusy(null);
    }
  }

  async function remove() {
    if (!window.confirm('Remove your diet plan? The patient goes back to Baymax\'s own plan and is told.')) return;
    setBusy('remove');
    setMsg(null);
    try {
      await api(`/patients/${pid}/plans/diet`, { method: 'DELETE' });
      setMsg({ tone: 'ok', text: 'Removed.' });
      onChanged();
    } catch (e) {
      setMsg({ tone: 'error', text: e instanceof Error ? e.message : 'Could not remove.' });
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card title="Diet plan">
      {current && <PlanHeader plan={current} patientChoice={patientChoice} />}
      {!canEdit ? (
        <p className="muted">{current ? 'Shown as set.' : 'No specialist diet plan has been set.'} You can change a patient&apos;s plan from when you accept their appointment until {days} days after it.</p>
      ) : (
        <div className="stack">
          {msg && <Notice tone={msg.tone}>{msg.text}</Notice>}
          <p className="muted small">The patient&apos;s own Baymax plan is unchanged underneath. Leave a box empty to keep Baymax&apos;s number. Protein, carbohydrate and fat go together.</p>
          <div className="grid3">
            <label>Daily calories (kcal)<input type="number" min={800} max={5000} value={kcal} onChange={(e) => setKcal(e.target.value)} /></label>
            <label>Protein (g)<input type="number" min={0} max={500} value={protein} onChange={(e) => setProtein(e.target.value)} /></label>
            <label>Carbohydrate (g)<input type="number" min={0} max={1000} value={carbs} onChange={(e) => setCarbs(e.target.value)} /></label>
          </div>
          <label>Fat (g)<input type="number" min={0} max={300} value={fat} onChange={(e) => setFat(e.target.value)} /></label>
          <div className="grid2">
            <label>Foods to avoid (one per line)<textarea rows={4} value={avoid} onChange={(e) => setAvoid(e.target.value)} /></label>
            <label>Tips for the patient (one per line)<textarea rows={4} value={tips} onChange={(e) => setTips(e.target.value)} /></label>
          </div>
          <label>Note to the patient<textarea rows={2} maxLength={600} value={note} onChange={(e) => setNote(e.target.value)} /></label>
          <div className="actions">
            <button className="btn btn-primary" disabled={busy !== null} onClick={() => void save('modified')}>{busy === 'modified' ? 'Saving…' : 'Save changes'}</button>
            <button className="btn" disabled={busy !== null} onClick={() => void save('approved')}>{busy === 'approved' ? 'Approving…' : 'Approve Baymax\'s plan as is'}</button>
            {current && <button className="btn btn-danger" disabled={busy !== null} onClick={() => void remove()}>Remove my plan</button>}
          </div>
        </div>
      )}
    </Card>
  );
}

function emptyWeek(): WorkoutDayPlan[] {
  return DAY_NAMES.map((_, i) => ({ day: i + 1, rest: true, items: [] }));
}

/** Workout plan (FR-5, FR-10): a trainer or doctor approves the patient's plan, or builds a weekly schedule from the exercise library. */
export function WorkoutPlanEditor({ pid, current, patientChoice, canEdit, days, onChanged }: { pid: string; current: WorkoutPlan | null; patientChoice: 'baymax' | 'specialist'; canEdit: boolean; days: number; onChanged: () => void }) {
  const [library, setLibrary] = useState<LibraryExercise[]>([]);
  const [week, setWeek] = useState<WorkoutDayPlan[]>(current?.schedule.length === 7 ? structuredClone(current.schedule) : emptyWeek());
  const [note, setNote] = useState(current?.note ?? '');
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);

  useEffect(() => {
    if (!canEdit) return;
    void api<{ exercises: LibraryExercise[] }>('/exercises').then((r) => setLibrary(r.exercises)).catch(() => setMsg({ tone: 'error', text: 'Could not load the exercise library.' }));
  }, [canEdit]);

  const byId = new Map(library.map((e) => [e.id, e]));
  const groups = [...new Set(library.map((e) => e.group))].sort();

  const setDay = (i: number, patch: Partial<WorkoutDayPlan>) => setWeek((w) => w.map((d, j) => (j === i ? { ...d, ...patch } : d)));
  const setItem = (i: number, k: number, patch: Partial<WorkoutItem>) => setWeek((w) => w.map((d, j) => (j === i ? { ...d, items: d.items.map((it, m) => (m === k ? { ...it, ...patch } : it)) } : d)));

  function addItem(i: number) {
    const first = library[0];
    if (!first) return;
    setDay(i, { rest: false, items: [...week[i].items, first.timed ? { exerciseId: first.id, sets: 1, seconds: first.baseSeconds } : { exerciseId: first.id, sets: 3, reps: first.baseReps }] });
  }

  function changeExercise(i: number, k: number, id: string) {
    const ex = byId.get(id);
    if (!ex) return;
    setItem(i, k, ex.timed ? { exerciseId: id, reps: undefined, seconds: ex.baseSeconds } : { exerciseId: id, seconds: undefined, reps: ex.baseReps });
  }

  async function save(status: 'approved' | 'modified') {
    if (busy) return;
    if (status === 'modified') {
      const problem = workoutPlanProblem(week, note);
      if (problem) {
        setMsg({ tone: 'error', text: problem });
        return;
      }
    }
    setBusy(status);
    setMsg(null);
    try {
      await api(`/patients/${pid}/plans/workout`, { method: 'PUT', body: status === 'approved' ? { status, note } : { status, note, schedule: week } });
      setMsg({ tone: 'ok', text: status === 'approved' ? 'Approved. The patient was told.' : 'Saved. The patient sees it in the Baymax app and was told.' });
      onChanged();
    } catch (e) {
      setMsg({ tone: 'error', text: e instanceof Error ? e.message : 'Could not save.' });
    } finally {
      setBusy(null);
    }
  }

  async function remove() {
    if (!window.confirm('Remove your workout plan? The patient goes back to Baymax\'s own plan and is told.')) return;
    setBusy('remove');
    try {
      await api(`/patients/${pid}/plans/workout`, { method: 'DELETE' });
      setMsg({ tone: 'ok', text: 'Removed.' });
      onChanged();
    } catch (e) {
      setMsg({ tone: 'error', text: e instanceof Error ? e.message : 'Could not remove.' });
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card title="Workout plan">
      {current && <PlanHeader plan={current} patientChoice={patientChoice} />}
      {!canEdit ? (
        <p className="muted">{current ? 'Shown as set.' : 'No specialist workout plan has been set.'} You can change a patient&apos;s plan from when you accept their appointment until {days} days after it.</p>
      ) : (
        <div className="stack">
          {msg && <Notice tone={msg.tone}>{msg.text}</Notice>}
          <p className="muted small">Build the week from the Baymax exercise library. The app adds a warm-up and cool-down to each day. Tick &quot;Rest day&quot; for days without training.</p>
          {week.map((d, i) => (
            <fieldset key={d.day} className="dayplan">
              <legend>{DAY_NAMES[i]}</legend>
              <label className="check"><input type="checkbox" checked={d.rest} onChange={(e) => setDay(i, { rest: e.target.checked, items: e.target.checked ? [] : d.items })} /> Rest day</label>
              {!d.rest && d.items.map((it, k) => {
                const ex = byId.get(it.exerciseId);
                return (
                  <div key={k} className="itemrow">
                    <label>Exercise
                      <select value={it.exerciseId} onChange={(e) => changeExercise(i, k, e.target.value)}>
                        {groups.map((g) => (
                          <optgroup key={g} label={g}>
                            {library.filter((x) => x.group === g).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
                          </optgroup>
                        ))}
                      </select>
                    </label>
                    <label>Sets<input type="number" min={1} max={8} value={it.sets} onChange={(e) => setItem(i, k, { sets: Number(e.target.value) })} /></label>
                    {ex?.timed ? (
                      <label>Seconds<input type="number" min={5} max={3600} value={it.seconds ?? ''} onChange={(e) => setItem(i, k, { seconds: Number(e.target.value) })} /></label>
                    ) : (
                      <label>Reps<input type="number" min={1} max={100} value={it.reps ?? ''} onChange={(e) => setItem(i, k, { reps: Number(e.target.value) })} /></label>
                    )}
                    <label>Note<input maxLength={120} value={it.note ?? ''} onChange={(e) => setItem(i, k, { note: e.target.value })} /></label>
                    <button type="button" className="btn btn-small" onClick={() => setDay(i, { items: d.items.filter((_, m) => m !== k), rest: d.items.length === 1 })}>Remove</button>
                  </div>
                );
              })}
              {!d.rest && d.items.length < 8 && <button type="button" className="btn btn-small" onClick={() => addItem(i)} disabled={!library.length}>Add exercise</button>}
              {d.rest && <button type="button" className="btn btn-small" onClick={() => addItem(i)} disabled={!library.length}>Add exercises to this day</button>}
            </fieldset>
          ))}
          <label>Note to the patient<textarea rows={2} maxLength={600} value={note} onChange={(e) => setNote(e.target.value)} /></label>
          <div className="actions">
            <button className="btn btn-primary" disabled={busy !== null} onClick={() => void save('modified')}>{busy === 'modified' ? 'Saving…' : 'Save plan'}</button>
            <button className="btn" disabled={busy !== null} onClick={() => void save('approved')}>{busy === 'approved' ? 'Approving…' : 'Approve Baymax\'s plan as is'}</button>
            {current && <button className="btn btn-danger" disabled={busy !== null} onClick={() => void remove()}>Remove my plan</button>}
          </div>
        </div>
      )}
    </Card>
  );
}
