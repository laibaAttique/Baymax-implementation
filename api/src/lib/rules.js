// Module 14 rules for the specialist portal. Pure functions: no database, no clock of their own.
// They mirror the mobile app's rules (app/lib/services/consultation_rules.dart) where both sides need the same answer.

export const SPECIALIST_ROLES = ['doctor', 'nutritionist', 'trainer'];

export const ROLE_LABELS = { doctor: 'Doctor', nutritionist: 'Nutritionist', trainer: 'Trainer' };

/**
 * What a specialist can see. `requested` = paid for (or pay-at-clinic) and waiting for the specialist to accept; accepting creates the
 * video room and makes it `confirmed`. `declined` = the specialist turned the request down.
 */
export const STATUSES = ['requested', 'confirmed', 'completed', 'cancelled', 'no_show', 'declined'];

/** Statuses of a session that really took place or is going to: only these open the patient's shared data. */
export const REAL_STATUSES = ['confirmed', 'completed', 'no_show'];

/** A booking whose time is held for ten minutes while the member pays. It is not an appointment yet and is never shown to a specialist. */
export const HELD = 'pending_payment';

const MIN = 60_000;

/** The meeting room can be opened this long before the start (FR10.5). */
export const JOIN_EARLY_MS = 5 * MIN;
/** The patient's shared data can be opened this long before the start (FR10.6). */
export const PREPARE_EARLY_MS = 30 * MIN;
/** The shared data stays open this long after the slot ends, so the specialist can write up the session. */
export const POST_SESSION_GRACE_MS = 60 * MIN;
/** A session is marked "missed" only this long after it was due to start. */
export const NO_SHOW_AFTER_MS = 10 * MIN;

export const MAX_NOTES = 5000;
export const MAX_PRESCRIPTION = 3000;

/** Turns a stored record into a plain object with numeric times. The slot key is the time that was actually locked, so it wins. */
export function normalizeAppointment(id, raw) {
  if (!raw || typeof raw !== 'object') return null;
  const key = Number(raw.slotKey);
  const startAt = Number.isFinite(key) && key > 0 ? key : Number(raw.startAt);
  if (!Number.isFinite(startAt)) return null;
  const durationMinutes = Number(raw.durationMinutes) > 0 ? Number(raw.durationMinutes) : 30;
  return {
    id,
    patientId: String(raw.patientId ?? ''),
    patientName: String(raw.patientName ?? ''),
    specialistId: String(raw.specialistId ?? ''),
    specialistName: String(raw.specialistName ?? ''),
    role: raw.role,
    specialty: String(raw.specialty ?? ''),
    startAt,
    endAt: startAt + durationMinutes * MIN,
    durationMinutes,
    type: raw.type === 'chat' ? 'chat' : 'video',
    // An unknown status is never read as "confirmed": it is treated as a held booking and left out of every list.
    status: STATUSES.includes(raw.status) ? raw.status : HELD,
    fee: Number(raw.fee) || 0,
    // The patient's phone writes this link, so only a plain https address is ever passed on to the browser.
    meetingLink: typeof raw.meetingLink === 'string' && /^https:\/\/[^\s]+$/.test(raw.meetingLink) ? raw.meetingLink : '',
    notesForSpecialist: String(raw.notesForSpecialist ?? ''),
    shares: {
      healthSummary: raw.shares?.healthSummary === true,
      foodLog7d: raw.shares?.foodLog7d === true,
      activity30d: raw.shares?.activity30d === true,
    },
    createdAt: Number(raw.createdAt) || 0,
    declineReason: typeof raw.declineReason === 'string' ? raw.declineReason : '',
    consultation: normalizeConsultation(raw.consultation),
    payment: normalizePayment(raw.payment),
  };
}

/** What the specialist sees about payment: whether it is paid, how, and how much. Never card details (none are stored). */
function normalizePayment(p) {
  if (!p || typeof p !== 'object') return null;
  const status = p.status === 'paid' || p.status === 'pay_at_clinic' ? p.status : null;
  if (!status) return null;
  return {
    status,
    method: ['card', 'wallet', 'clinic'].includes(p.method) ? p.method : null,
    total: Number(p.total) || 0,
    test: p.mode !== 'live',
    transactionId: String(p.transactionId ?? ''),
  };
}

function normalizeConsultation(c) {
  if (!c || typeof c !== 'object') return null;
  const notes = String(c.notes ?? '');
  const prescription = String(c.prescription ?? '');
  if (!notes.trim() && !prescription.trim()) return null;
  return { notes, prescription, updatedAt: Number(c.updatedAt) || 0, updatedBy: String(c.updatedBy ?? '') };
}

/**
 * What the specialist can do with an appointment right now.
 *  - canJoin: confirmed, from 5 minutes before the start until the slot ends. (The scope says "within 5 minutes before or after";
 *    this keeps the button for the whole session so a dropped call can be rejoined.)
 *  - canPrepare: confirmed, from 30 minutes before until the slot ends (FR10.6).
 *  - canViewShared: the patient's shared data is readable from 30 minutes before to 60 minutes after the slot, whatever the status,
 *    except a cancelled booking, which never opens it.
 */
export function appointmentState(a, now) {
  const confirmed = a.status === 'confirmed';
  // A room exists only once the specialist has accepted (the link is made then), so there is nothing to join before that.
  const canJoin = confirmed && !!a.meetingLink && now >= a.startAt - JOIN_EARLY_MS && now < a.endAt;
  const canPrepare = confirmed && now >= a.startAt - PREPARE_EARLY_MS && now < a.endAt;
  const canViewShared = REAL_STATUSES.includes(a.status) && now >= a.startAt - PREPARE_EARLY_MS && now < a.endAt + POST_SESSION_GRACE_MS;
  // A request can be answered until its start time; after that it has expired unanswered.
  const canRespond = a.status === 'requested' && now < a.startAt;
  let phase;
  if (a.status === 'cancelled') phase = 'cancelled';
  else if (a.status === 'declined') phase = 'declined';
  else if (a.status === 'requested') phase = now < a.startAt ? 'requested' : 'expired';
  else if (!confirmed) phase = 'past';
  else if (now >= a.endAt) phase = 'past';
  else if (now >= a.startAt) phase = 'live';
  else phase = 'upcoming';
  return { phase, canJoin, canPrepare, canViewShared, canRespond, live: phase === 'live' || canJoin };
}

/** Today's list order (FR10.4): live sessions first, then the rest of today in time order, with finished ones at the end. */
export function sortToday(list, now) {
  const rank = (a) => {
    const s = appointmentState(a, now);
    return s.phase === 'live' ? 0 : s.phase === 'upcoming' ? 1 : 2;
  };
  return [...list].sort((x, y) => rank(x) - rank(y) || x.startAt - y.startAt);
}

/** The calendar day [start, end) in ms that contains [now] in a time zone [tzOffsetMinutes] east of UTC. */
export function dayBounds(now, tzOffsetMinutes) {
  const shifted = now + tzOffsetMinutes * MIN;
  const dayStartShifted = Math.floor(shifted / 86_400_000) * 86_400_000;
  const start = dayStartShifted - tzOffsetMinutes * MIN;
  return { start, end: start + 86_400_000 };
}

/** "Good Morning" before 12:00, "Good Afternoon" until 17:00, "Good Evening" after (FR10.2), in the specialist's own clock. */
export function greeting(now, tzOffsetMinutes) {
  const d = new Date(now + tzOffsetMinutes * MIN);
  const h = d.getUTCHours();
  const m = d.getUTCMinutes();
  if (h < 12) return 'Good Morning';
  if (h < 17 || (h === 17 && m === 0)) return 'Good Afternoon';
  return 'Good Evening';
}

/**
 * The Appointments screen filters (FR10.11): status, a date range (inclusive, in ms), and part of the patient's name.
 * Unknown values are ignored rather than erroring, so a stale link still shows something.
 */
export function filterAppointments(list, { status, from, to, q } = {}) {
  const needle = (q ?? '').trim().toLowerCase();
  return list.filter((a) => {
    if (status && STATUSES.includes(status) && a.status !== status) return false;
    if (Number.isFinite(from) && a.startAt < from) return false;
    if (Number.isFinite(to) && a.startAt >= to) return false;
    if (needle && !a.patientName.toLowerCase().includes(needle)) return false;
    return true;
  });
}

/** Held bookings are not appointments: keep only what a specialist should see. */
export const isListed = (a) => a.status !== HELD;

/** Counts for the dashboard cards. Only what the stored data can honestly say. */
export function dashboardCounts(list, now, tzOffsetMinutes) {
  const day = dayBounds(now, tzOffsetMinutes);
  const week = day.start + 7 * 86_400_000;
  const confirmed = list.filter((a) => a.status === 'confirmed');
  return {
    consultationsToday: confirmed.filter((a) => a.startAt >= day.start && a.startAt < day.end).length,
    upcoming7Days: confirmed.filter((a) => a.endAt > now && a.startAt < week).length,
    patients: new Set(list.filter((a) => REAL_STATUSES.includes(a.status)).map((a) => a.patientId)).size,
    pendingRequests: list.filter((a) => a.status === 'requested' && a.startAt > now).length,
    awaitingNotes: list.filter((a) => (a.status === 'completed' || (a.status === 'confirmed' && a.endAt <= now)) && !a.consultation).length,
  };
}

/** Why a status change is not allowed now, or null. */
export function statusChangeProblem(a, next, now) {
  if (a.status !== 'confirmed') return `This appointment is already ${a.status.replace('_', ' ')}.`;
  if (next === 'completed' && now < a.startAt) return 'The session has not started yet.';
  if (next === 'no_show' && now < a.startAt + NO_SHOW_AFTER_MS) return 'The patient can only be marked as missed 10 minutes after the start time.';
  if (next === 'cancelled' && now >= a.endAt) return 'This appointment has already ended.';
  if (!['completed', 'cancelled', 'no_show'].includes(next)) return 'Unknown status.';
  return null;
}

/** Why a request cannot be answered now, or null. Both accepting and declining need the request to be waiting and not yet due. */
export function respondProblem(a, now) {
  if (a.status !== 'requested') return a.status === 'confirmed' ? 'This request was already accepted.' : `This request is already ${a.status.replace('_', ' ')}.`;
  if (now >= a.startAt) return 'The start time has passed, so this request expired. The patient can book another time.';
  return null;
}

/** An unguessable meeting room name: only the two people given the link can find it. */
export function newRoomName(randomBytes) {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  const bytes = randomBytes(20);
  return `baymax-${Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('')}`;
}

/** The video link for an accepted appointment. A chat-only booking opens the room with camera and microphone off. */
export function buildMeetingLink(base, room, type) {
  const trimmed = base.endsWith('/') ? base.slice(0, -1) : base;
  const hash = type === 'chat' ? '#config.startWithVideoMuted=true&config.startWithAudioMuted=true' : '';
  return `${trimmed}/${room}${hash}`;
}

/** Validates the specialist's own profile edits. Returns { value } or { error }. */
export function parseProfileUpdate(body) {
  const out = {};
  const str = (k, max) => {
    if (body[k] === undefined) return null;
    if (typeof body[k] !== 'string' || body[k].length > max) return `${k} must be text of at most ${max} characters.`;
    out[k] = body[k].trim();
    return null;
  };
  for (const err of [str('specialty', 80), str('bio', 600)]) if (err) return { error: err };
  if (body.fees !== undefined) {
    const { video, chat } = body.fees ?? {};
    for (const v of [video, chat]) {
      if (!Number.isInteger(v) || v < 0 || v > 1_000_000) return { error: 'Fees must be whole numbers of PKR between 0 and 1,000,000.' };
    }
    out.fees = { video, chat };
  }
  for (const k of ['available', 'emergency']) {
    if (body[k] === undefined) continue;
    if (typeof body[k] !== 'boolean') return { error: `${k} must be true or false.` };
    out[k] = body[k];
  }
  if (body.yearsOfExperience !== undefined) {
    if (!Number.isInteger(body.yearsOfExperience) || body.yearsOfExperience < 0 || body.yearsOfExperience > 70) return { error: 'Years of experience must be between 0 and 70.' };
    out.yearsOfExperience = body.yearsOfExperience;
  }
  if (body.availability !== undefined) {
    const a = body.availability ?? {};
    const clock = /^([01]\d|2[0-3]):([0-5]\d)$/;
    const days = Array.isArray(a.days) ? [...new Set(a.days)] : null;
    if (!days || !days.length || days.some((d) => !Number.isInteger(d) || d < 1 || d > 7)) return { error: 'Choose at least one working day.' };
    if (!clock.test(a.start ?? '') || !clock.test(a.end ?? '')) return { error: 'Times must look like 09:00.' };
    if (a.end <= a.start) return { error: 'The end time must be after the start time.' };
    if (!Number.isInteger(a.slotMinutes) || a.slotMinutes < 10 || a.slotMinutes > 120) return { error: 'A slot must be between 10 and 120 minutes.' };
    out.availability = { days: days.sort((x, y) => x - y), start: a.start, end: a.end, slotMinutes: a.slotMinutes };
  }
  if (!Object.keys(out).length) return { error: 'Nothing to update.' };
  return { value: out };
}

/** Validates the notes a specialist adds after a session (FR-8, FR-6). Prescriptions are for doctors only. */
export function parseConsultationNote(body, role) {
  const notes = body?.notes ?? '';
  const prescription = body?.prescription ?? '';
  if (typeof notes !== 'string' || typeof prescription !== 'string') return { error: 'Notes and prescription must be text.' };
  if (notes.length > MAX_NOTES) return { error: `Notes can be at most ${MAX_NOTES} characters.` };
  if (prescription.length > MAX_PRESCRIPTION) return { error: `A prescription can be at most ${MAX_PRESCRIPTION} characters.` };
  if (prescription.trim() && role !== 'doctor') return { error: 'Only a doctor can write a prescription.' };
  if (!notes.trim() && !prescription.trim()) return { error: 'Write some notes or a prescription first.' };
  return { value: { notes: notes.trim(), prescription: prescription.trim() } };
}
