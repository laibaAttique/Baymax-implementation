// Closing a specialist account (their own choice, or an administrator's). Used by the portal and the admin panel.
import { REAL_STATUSES, normalizeAppointment } from './rules.js';

export class AccountError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/**
 * Removes a specialist: every request or appointment that has not happened is cancelled (the time is freed and the patient is told),
 * then the role, public profile and registration are removed. Past appointments stay: they are part of each patient's own record.
 * The sign-in account is deleted too, unless the same account is also a member of the mobile app (it has a health profile), in
 * which case only the specialist side is removed and they can still log in to the app.
 */
export async function deleteSpecialist({ auth, db, now = Date.now }, uid, { by } = {}) {
  const role = await db.get(`roles/${uid}`);
  if (role === 'admin') throw new AccountError(409, 'An administrator account cannot be deleted here.');
  const profile = await db.get(`specialists/${uid}`);
  const application = await db.get(`applications/${uid}`);
  if (!profile && !application && !['doctor', 'nutritionist', 'trainer'].includes(role)) throw new AccountError(404, 'Specialist not found.');

  const t = now();
  const updates = {};
  const raw = await db.byChild('appointments', 'specialistId', uid);
  let cancelled = 0;
  for (const [id, r] of Object.entries(raw)) {
    const a = normalizeAppointment(id, r);
    const open = r.status === 'pending_payment' || r.status === 'requested' || (r.status === 'confirmed' && a && a.endAt > t);
    if (!open) continue;
    cancelled++;
    updates[`appointments/${id}/status`] = 'cancelled';
    updates[`appointments/${id}/declineReason`] = 'This specialist closed their Baymax account.';
    if (r.status !== 'pending_payment' && r.patientId) {
      updates[`users/${r.patientId}/inbox/closed-${id}`] = {
        type: 'appointment',
        title: 'Your appointment was cancelled',
        body: `${r.specialistName || 'Your specialist'} is no longer available. You can book another specialist.`.slice(0, 240),
        createdAt: t,
        read: false,
        route: 'appointments',
      };
    }
  }
  // every time this specialist had locked, past or future: nobody can book a specialist who no longer exists
  updates[`slots/${uid}`] = null;
  updates[`specialists/${uid}`] = null;
  updates[`roles/${uid}`] = null;
  updates[`applications/${uid}`] = null;
  await db.update(updates);

  const alsoMember = !!(await db.get(`users/${uid}/profile`));
  let accountDeleted = false;
  if (!alsoMember) {
    try {
      await auth.deleteUser(uid);
      accountDeleted = true;
    } catch (e) {
      if (e?.code !== 'auth/user-not-found') throw e;
      accountDeleted = true;
    }
  }
  return { cancelled, accountDeleted, keptMemberAccount: alsoMember, realAppointmentsKept: Object.values(raw).filter((r) => REAL_STATUSES.includes(r.status)).length, by };
}
