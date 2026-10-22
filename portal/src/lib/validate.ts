// Checks for every form in the portal. They mirror the API's rules (baymax-api/src/lib/specialistAdmin.js and rules.js) so a mistake is
// shown next to the field before anything is sent. The API checks everything again: these only save a round trip.

export type Problems = Record<string, string>;

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const LICENSE = /^[A-Za-z0-9][A-Za-z0-9 ./-]{2,39}$/;
const CLOCK = /^([01]\d|2[0-3]):([0-5]\d)$/;
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;

export const emailProblem = (v: string): string | null => {
  const t = v.trim();
  if (!t) return 'Enter your email address.';
  if (t.length > 120 || !EMAIL.test(t)) return 'That email address does not look right.';
  return null;
};

/** At least 8 characters with a letter and a number. (Firebase itself would accept 6.) */
export const passwordProblem = (v: string): string | null => {
  if (v.length < 8) return 'Use at least 8 characters.';
  if (v.length > 128) return 'Use at most 128 characters.';
  if (!/[A-Za-z]/.test(v) || !/\d/.test(v)) return 'Include at least one letter and one number.';
  return null;
};

export const textProblem = (v: string, label: string, min: number, max: number): string | null => {
  const t = v.trim();
  if (t.length < min) return min <= 1 ? `Enter ${label}.` : `${label[0].toUpperCase()}${label.slice(1)} must be at least ${min} characters.`;
  if (t.length > max) return `${label[0].toUpperCase()}${label.slice(1)} can be at most ${max} characters.`;
  if (CONTROL.test(t)) return `${label[0].toUpperCase()}${label.slice(1)} has characters that are not allowed.`;
  return null;
};

export const licenseProblem = (v: string): string | null =>
  LICENSE.test(v.trim()) ? null : 'Enter your licence or registration number: 3 to 40 letters, digits, spaces, - . /';

/** A whole number of PKR. Empty, decimals, negative and absurd amounts are refused. */
export const feeProblem = (v: string, label: string): string | null => {
  if (v.trim() === '') return `Enter the ${label}.`;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > 1_000_000) return `The ${label} must be a whole number of PKR from 0 to 1,000,000.`;
  return null;
};

export const yearsProblem = (v: string): string | null => {
  if (v.trim() === '') return null;
  const n = Number(v);
  return Number.isInteger(n) && n >= 0 && n <= 70 ? null : 'Years of experience must be a whole number from 0 to 70.';
};

export const hoursProblem = (days: number[], start: string, end: string): string | null => {
  if (days.length === 0) return 'Choose at least one working day.';
  if (!CLOCK.test(start) || !CLOCK.test(end)) return 'Enter the working hours as times, for example 09:00.';
  if (end <= start) return 'The end time must be after the start time.';
  return null;
};

export const slotProblem = (v: string): string | null => {
  const n = Number(v);
  return Number.isInteger(n) && n >= 10 && n <= 120 ? null : 'A slot must be between 10 and 120 minutes.';
};

export interface ApplicationFields {
  name: string; specialty: string; license: string; years: string; bio: string; video: string; chat: string;
  days: number[]; start: string; end: string;
}

/** Everything wrong with a registration or a new-specialist form, by field. Empty means it can be sent. */
export function applicationProblems(f: ApplicationFields, { license = true } = {}): Problems {
  const p: Problems = {};
  const set = (k: string, m: string | null) => { if (m) p[k] = m; };
  set('name', textProblem(f.name, 'your name', 2, 80));
  set('specialty', textProblem(f.specialty, 'a specialty', 1, 80));
  if (license) set('license', licenseProblem(f.license));
  set('years', yearsProblem(f.years));
  set('bio', f.bio.length > 600 ? 'The bio can be at most 600 characters.' : null);
  set('video', feeProblem(f.video, 'video fee'));
  set('chat', feeProblem(f.chat, 'chat fee'));
  set('hours', hoursProblem(f.days, f.start, f.end));
  return p;
}

export interface ProfileFields { specialty: string; bio: string; video: string; chat: string; days: number[]; start: string; end: string; slot: string }

export function profileProblems(f: ProfileFields): Problems {
  const p: Problems = {};
  const set = (k: string, m: string | null) => { if (m) p[k] = m; };
  set('specialty', textProblem(f.specialty, 'a specialty', 1, 80));
  set('bio', f.bio.length > 600 ? 'The bio can be at most 600 characters.' : null);
  set('video', feeProblem(f.video, 'video fee'));
  set('chat', feeProblem(f.chat, 'chat fee'));
  set('hours', hoursProblem(f.days, f.start, f.end));
  set('slot', slotProblem(f.slot));
  return p;
}

/** A chat message: 1 to 1000 characters of plain text. */
export const messageProblem = (v: string): string | null => textProblem(v, 'the message', 1, 1000);

/** The date range of a list: both ends optional, but the end cannot be before the start. */
export const rangeProblem = (from: string, to: string): string | null => (from && to && to < from ? 'The end date is before the start date.' : null);

export const firstProblem = (p: Problems): string | null => Object.values(p)[0] ?? null;

// ---- plans -------------------------------------------------------------------------------------------------------------------

const whole = (s: string) => (s.trim() === '' ? undefined : Number(s));

/** Why a diet plan cannot be saved, or null. Mirrors parseDietPlan in the API. */
export function dietPlanProblem(f: { kcal: string; protein: string; carbs: string; fat: string; avoid: string[]; tips: string[]; note: string }): string | null {
  const inRange = (v: string, lo: number, hi: number, label: string): string | null => {
    if (v.trim() === '') return null;
    const n = Number(v);
    return Number.isInteger(n) && n >= lo && n <= hi ? null : `${label} must be a whole number from ${lo} to ${hi}.`;
  };
  const bad = inRange(f.kcal, 800, 5000, 'The calorie target') ?? inRange(f.protein, 0, 500, 'Protein') ?? inRange(f.carbs, 0, 1000, 'Carbohydrate') ?? inRange(f.fat, 0, 300, 'Fat');
  if (bad) return bad;
  const macros = [f.protein, f.carbs, f.fat].filter((v) => v.trim() !== '').length;
  if (macros !== 0 && macros !== 3) return 'Give protein, carbohydrate and fat together, or none of them.';
  const kcal = whole(f.kcal);
  if (macros === 3 && kcal !== undefined) {
    const sum = Number(f.protein) * 4 + Number(f.carbs) * 4 + Number(f.fat) * 9;
    if (Math.abs(sum - kcal) > kcal * 0.15) return `Protein, carbohydrate and fat add up to about ${sum} kcal, which differs from the ${kcal} kcal target by more than 15%. Check the numbers.`;
  }
  if (f.avoid.length > 20) return 'Foods to avoid: at most 20 entries.';
  if (f.avoid.some((x) => x.length < 2 || x.length > 50)) return 'Foods to avoid: each entry must be 2 to 50 characters.';
  if (f.tips.length > 10) return 'Tips: at most 10 entries.';
  if (f.tips.some((x) => x.length < 5 || x.length > 200)) return 'Tips: each entry must be 5 to 200 characters.';
  if (f.note.length > 600) return 'The note can be at most 600 characters.';
  const changed = kcal !== undefined || macros === 3 || f.avoid.length > 0 || f.tips.length > 0;
  return changed ? null : 'Change at least one thing, or choose "Approve as is".';
}

/** Why a weekly workout schedule cannot be saved, or null. Mirrors parseWorkoutPlan in the API. */
export function workoutPlanProblem(week: { day: number; rest: boolean; items: { exerciseId: string; sets: number; reps?: number; seconds?: number; note?: string }[] }[], note: string): string | null {
  if (week.length !== 7) return 'The schedule needs all seven days.';
  if (week.every((d) => d.rest || d.items.length === 0)) return 'At least one day must have exercises.';
  const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  for (const d of week) {
    const name = names[d.day - 1];
    if (d.rest) continue;
    if (d.items.length < 1 || d.items.length > 8) return `${name} needs 1 to 8 exercises, or mark it as a rest day.`;
    for (const it of d.items) {
      if (!Number.isInteger(it.sets) || it.sets < 1 || it.sets > 8) return `${name}: sets must be a whole number from 1 to 8.`;
      if (it.seconds !== undefined && (!Number.isInteger(it.seconds) || it.seconds < 5 || it.seconds > 3600)) return `${name}: seconds must be a whole number from 5 to 3600.`;
      if (it.seconds === undefined && (!Number.isInteger(it.reps) || (it.reps ?? 0) < 1 || (it.reps ?? 0) > 100)) return `${name}: reps must be a whole number from 1 to 100.`;
      if ((it.note ?? '').length > 120) return `${name}: a note can be at most 120 characters.`;
    }
  }
  return note.length > 600 ? 'The note can be at most 600 characters.' : null;
}
