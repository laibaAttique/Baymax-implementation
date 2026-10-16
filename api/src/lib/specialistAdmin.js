// Making a person a specialist: shared by the administrator page (routes/admin.js) and the command-line script.
import { SPECIALIST_ROLES, parseProfileUpdate } from './rules.js';

export class AdminError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** Checks the form and returns { email, name, type, tzOffsetMinutes, profile } or throws AdminError(400). */
export function parseNewSpecialist(body) {
  const b = body ?? {};
  const email = typeof b.email === 'string' ? b.email.trim().toLowerCase() : '';
  if (!EMAIL.test(email) || email.length > 120) throw new AdminError(400, 'Enter a valid email address.');
  const name = typeof b.name === 'string' ? b.name.trim() : '';
  if (name.length < 2 || name.length > 80) throw new AdminError(400, 'Enter the specialist\'s name (2 to 80 characters).');
  if (!SPECIALIST_ROLES.includes(b.type)) throw new AdminError(400, `Type must be one of: ${SPECIALIST_ROLES.join(', ')}.`);
  const tz = b.tzOffsetMinutes === undefined ? 300 : Number(b.tzOffsetMinutes);
  if (!Number.isInteger(tz) || tz < -720 || tz > 840) throw new AdminError(400, 'The time zone must be minutes east of UTC, e.g. 300 for Pakistan.');
  if (typeof b.specialty !== 'string' || !b.specialty.trim()) throw new AdminError(400, 'Enter the specialty.');
  // The app cannot show a specialist without both fees, so they are required here (profile edits may leave them out).
  if (!b.fees || typeof b.fees !== 'object') throw new AdminError(400, 'Fees must be whole numbers of PKR for both video and chat.');
  const parsed = parseProfileUpdate({
    specialty: b.specialty,
    bio: b.bio ?? '',
    yearsOfExperience: b.yearsOfExperience ?? 0,
    emergency: b.emergency === true,
    available: true,
    fees: b.fees,
    availability: b.availability ?? { days: [1, 2, 3, 4, 5], start: '09:00', end: '17:00', slotMinutes: 30 },
  });
  if (parsed.error) throw new AdminError(400, parsed.error);
  return { email, name, type: b.type, tzOffsetMinutes: tz, profile: { name, type: b.type, tzOffsetMinutes: tz, ...parsed.value } };
}

/**
 * Finds or creates the sign-in account (no password is set or seen), sets the role and writes the public profile.
 * An account that already has a different role is refused, so this can never demote an administrator or switch a doctor into a trainer.
 * Returns { uid, created, resetLink }: the link lets the person choose their own password.
 */
export async function makeSpecialist({ auth, db, now = Date.now }, input) {
  let user;
  let created = false;
  try {
    user = await auth.getUserByEmail(input.email);
  } catch (e) {
    if (e?.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email: input.email, displayName: input.name });
    created = true;
  }
  const existingRole = await db.get(`roles/${user.uid}`);
  if (existingRole && existingRole !== input.type) {
    throw new AdminError(409, `${input.email} already has the role "${existingRole}". Use a different email.`);
  }
  const existing = (await db.get(`specialists/${user.uid}`)) ?? {};
  await db.update({
    [`roles/${user.uid}`]: input.type,
    // Rating and review count are kept if the person already had a profile.
    [`specialists/${user.uid}`]: { rating: 0, reviewCount: 0, ...existing, ...input.profile, updatedAt: now() },
  });
  const resetLink = await auth.generatePasswordResetLink(input.email);
  return { uid: user.uid, created, resetLink };
}

const LICENSE = /^[A-Za-z0-9][A-Za-z0-9 ./-]{2,39}$/;

/**
 * A specialist's own registration form. The email comes from the signed-in account, never from the form. A professional licence or
 * registration number is required so an administrator can check it before approving.
 */
export function parseApplication(body, email) {
  const input = parseNewSpecialist({ ...(body ?? {}), email });
  const license = typeof body?.licenseNumber === 'string' ? body.licenseNumber.trim() : '';
  if (!LICENSE.test(license)) throw new AdminError(400, 'Enter your professional licence or registration number (3 to 40 letters, digits, spaces, - . /).');
  return { ...input, licenseNumber: license };
}

/** What is kept for an administrator to review. */
export function applicationRecord(input, now) {
  return {
    status: 'pending',
    email: input.email,
    name: input.name,
    type: input.type,
    specialty: input.profile.specialty,
    licenseNumber: input.licenseNumber,
    tzOffsetMinutes: input.tzOffsetMinutes,
    profile: input.profile, // the public profile that is created if approved
    submittedAt: now,
  };
}

/**
 * Approves a registration: the role and the public profile are created for that account, and the application is marked approved.
 * Refuses an account that already has a specialist or administrator role.
 */
export async function approveApplication({ db, now = Date.now }, uid, reviewerUid) {
  const app = await db.get(`applications/${uid}`);
  if (!app) throw new AdminError(404, 'Application not found.');
  if (app.status === 'approved') throw new AdminError(409, 'This application was already approved.');
  const role = await db.get(`roles/${uid}`);
  if (role && role !== 'user') throw new AdminError(409, `This account already has the role "${role}".`);
  const t = now();
  await db.update({
    [`roles/${uid}`]: app.type,
    // `verified` records that an administrator checked the licence number. The licence number itself stays private.
    [`specialists/${uid}`]: { rating: 0, reviewCount: 0, ...app.profile, verified: true, updatedAt: t },
    [`applications/${uid}/status`]: 'approved',
    [`applications/${uid}/reviewedAt`]: t,
    [`applications/${uid}/reviewedBy`]: reviewerUid,
    [`applications/${uid}/rejectReason`]: null,
  });
  return { uid, type: app.type, name: app.name };
}

export async function rejectApplication({ db, now = Date.now }, uid, reviewerUid, reason) {
  const app = await db.get(`applications/${uid}`);
  if (!app) throw new AdminError(404, 'Application not found.');
  if (app.status === 'approved') throw new AdminError(409, 'This application was already approved.');
  const text = typeof reason === 'string' ? reason.trim() : '';
  if (text.length > 300) throw new AdminError(400, 'The reason can be at most 300 characters.');
  await db.update({
    [`applications/${uid}/status`]: 'rejected',
    [`applications/${uid}/reviewedAt`]: now(),
    [`applications/${uid}/reviewedBy`]: reviewerUid,
    [`applications/${uid}/rejectReason`]: text || null,
  });
}
