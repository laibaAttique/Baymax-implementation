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
