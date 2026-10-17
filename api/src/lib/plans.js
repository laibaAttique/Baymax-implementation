// Specialist plans (FR-5, FR-9, FR-10): what a nutritionist, trainer or doctor may set for a patient, and how it is checked.
// Pure functions: no database, no clock.
import { readFileSync } from 'node:fs';

/** The exercise library the app uses (copied from the app's assets/data/exercises.json). Warm-up and cool-down are added by the app itself. */
export const EXERCISES = JSON.parse(readFileSync(new URL('../../data/exercises.json', import.meta.url), 'utf8')).filter((e) => e.id !== 'warmup' && e.id !== 'cooldown');
const BY_ID = new Map(EXERCISES.map((e) => [e.id, e]));

/** Who may change which plan. A doctor can do both; a nutritionist only the diet; a trainer only the workout. */
export const PLAN_ROLES = { diet: ['doctor', 'nutritionist'], workout: ['doctor', 'trainer'] };
export const DIET_REVIEW_ROLES = ['nutritionist'];

/** A plan can be changed from acceptance until this long after the session. */
export const PLAN_EDIT_DAYS = 30;

const STATUSES = ['approved', 'modified'];

class PlanError extends Error {}
export { PlanError };

const int = (v, min, max, label) => {
  if (!Number.isInteger(v) || v < min || v > max) throw new PlanError(`${label} must be a whole number from ${min} to ${max}.`);
  return v;
};

function cleanList(v, { max, minLen, maxLen, label }) {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max) throw new PlanError(`${label}: at most ${max} entries.`);
  const out = [];
  for (const x of v) {
    if (typeof x !== 'string') throw new PlanError(`${label} must be text.`);
    const t = x.trim();
    if (!t) continue;
    if (t.length < minLen || t.length > maxLen) throw new PlanError(`${label}: each entry must be ${minLen} to ${maxLen} characters.`);
    out.push(t);
  }
  return [...new Set(out)];
}

function parseNote(v) {
  if (v === undefined || v === null) return '';
  if (typeof v !== 'string' || v.length > 600) throw new PlanError('The note can be at most 600 characters.');
  return v.trim();
}

/**
 * A diet plan from a nutritionist or doctor: either "approved as it is", or changes to the calorie target, macros, foods to avoid and
 * tips. If a calorie target and macros are both given they must agree, which catches a typo before it reaches a patient.
 */
export function parseDietPlan(body) {
  const b = body ?? {};
  if (!STATUSES.includes(b.status)) throw new PlanError('Choose "Approve as is" or "Save changes".');
  const note = parseNote(b.note);
  if (b.status === 'approved') return { status: 'approved', note, avoid: [], tips: [] };
  const plan = { status: 'modified', note, avoid: cleanList(b.avoid, { max: 20, minLen: 2, maxLen: 50, label: 'Foods to avoid' }), tips: cleanList(b.tips, { max: 10, minLen: 5, maxLen: 200, label: 'Tips' }) };
  if (b.targetKcal !== undefined && b.targetKcal !== null && b.targetKcal !== '') plan.targetKcal = int(b.targetKcal, 800, 5000, 'The calorie target');
  const macros = { proteinG: [0, 500, 'Protein'], carbsG: [0, 1000, 'Carbohydrate'], fatG: [0, 300, 'Fat'] };
  for (const [k, [lo, hi, label]] of Object.entries(macros)) {
    if (b[k] !== undefined && b[k] !== null && b[k] !== '') plan[k] = int(b[k], lo, hi, label);
  }
  const hasMacros = ['proteinG', 'carbsG', 'fatG'].every((k) => plan[k] !== undefined);
  const someMacros = ['proteinG', 'carbsG', 'fatG'].some((k) => plan[k] !== undefined);
  if (someMacros && !hasMacros) throw new PlanError('Give protein, carbohydrate and fat together, or none of them.');
  if (hasMacros && plan.targetKcal !== undefined) {
    const kcal = plan.proteinG * 4 + plan.carbsG * 4 + plan.fatG * 9;
    if (Math.abs(kcal - plan.targetKcal) > plan.targetKcal * 0.15) {
      throw new PlanError(`Protein, carbohydrate and fat add up to about ${kcal} kcal, which differs from the ${plan.targetKcal} kcal target by more than 15%. Check the numbers.`);
    }
  }
  const changed = plan.targetKcal !== undefined || hasMacros || plan.avoid.length || plan.tips.length;
  if (!changed) throw new PlanError('Change at least one thing, or choose "Approve as is".');
  return plan;
}

/**
 * A workout plan from a trainer or doctor: "approved as it is", or a weekly schedule built only from library exercises. Rest days have
 * no exercises; a training day has 1 to 8. Reps apply to counted exercises and seconds to timed ones.
 */
export function parseWorkoutPlan(body) {
  const b = body ?? {};
  if (!STATUSES.includes(b.status)) throw new PlanError('Choose "Approve as is" or "Save changes".');
  const note = parseNote(b.note);
  if (b.status === 'approved') return { status: 'approved', note, schedule: [] };
  if (!Array.isArray(b.schedule) || b.schedule.length !== 7) throw new PlanError('The schedule needs all seven days.');
  const seen = new Set();
  const schedule = [];
  for (const d of b.schedule) {
    const day = int(d?.day, 1, 7, 'The day');
    if (seen.has(day)) throw new PlanError('Each day can appear only once.');
    seen.add(day);
    if (d.rest === true) {
      if (Array.isArray(d.items) && d.items.length) throw new PlanError('A rest day cannot have exercises.');
      schedule.push({ day, rest: true, items: [] });
      continue;
    }
    if (!Array.isArray(d.items) || d.items.length < 1 || d.items.length > 8) throw new PlanError('A training day needs 1 to 8 exercises (or mark it as a rest day).');
    const items = d.items.map((it) => {
      const ex = BY_ID.get(it?.exerciseId);
      if (!ex) throw new PlanError(`"${it?.exerciseId}" is not an exercise in the Baymax library.`);
      const out = { exerciseId: ex.id, sets: int(it.sets, 1, 8, `Sets for ${ex.name}`) };
      if (ex.timed) out.seconds = int(it.seconds, 5, 3600, `Seconds for ${ex.name}`);
      else out.reps = int(it.reps, 1, 100, `Reps for ${ex.name}`);
      const note = typeof it.note === 'string' ? it.note.trim() : '';
      if (note.length > 120) throw new PlanError(`The note for ${ex.name} can be at most 120 characters.`);
      if (note) out.note = note;
      return out;
    });
    schedule.push({ day, rest: false, items });
  }
  if (schedule.every((d) => d.rest)) throw new PlanError('At least one day must have exercises.');
  return { status: 'modified', note, schedule: schedule.sort((x, y) => x.day - y.day) };
}

/** A day-by-day review of a patient's food log by a nutritionist (FR-9): approved, or flagged with a note saying why. */
export function parseDietReview(body, date, now) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(`${date}T00:00:00Z`))) throw new PlanError('The date must look like 2026-10-19.');
  const b = body ?? {};
  if (b.status !== 'approved' && b.status !== 'flagged') throw new PlanError('Choose "Approve" or "Flag".');
  const note = parseNote(b.note);
  if (b.status === 'flagged' && note.length < 3) throw new PlanError('Say why you are flagging this day, so the patient knows what to change.');
  const age = (now - Date.parse(`${date}T00:00:00Z`)) / 86_400_000;
  if (age < -1 || age > 8) throw new PlanError('Only the last 7 days of the food log can be reviewed.');
  return { status: b.status, note };
}
