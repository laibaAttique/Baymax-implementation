import { Router } from 'express';
import { HttpError, forbidden } from '../http.js';
import { SPECIALIST_ROLES } from '../lib/rules.js';
import { AdminError, applicationRecord, parseApplication } from '../lib/specialistAdmin.js';

/** A person who is not yet a specialist submits their registration. It does nothing until an administrator approves it. */
export function applicationRoutes({ db, now }) {
  const router = Router();

  router.post('/', async (req, res) => {
    const { uid, email, role } = req.user;
    if (role === 'admin' || SPECIALIST_ROLES.includes(role)) throw new HttpError(409, 'This account is already set up in the portal.');
    if (!email) throw forbidden('Your account has no email address, so it cannot register.');
    let input;
    try {
      input = parseApplication(req.body, email);
    } catch (e) {
      throw e instanceof AdminError ? new HttpError(e.status, e.message) : e;
    }
    const existing = await db.get(`applications/${uid}`);
    if (existing?.status === 'approved') throw new HttpError(409, 'Your registration was already approved.');
    // A pending or rejected application can be corrected and sent again.
    await db.update({ [`applications/${uid}`]: applicationRecord(input, now()) });
    res.status(201).json({ application: publicApplication(await db.get(`applications/${uid}`)) });
  });

  /** Withdraw a registration. Only the registration is removed: the person's sign-in account (which may also be their Baymax app login) stays. */
  router.delete('/', async (req, res) => {
    const { uid, role } = req.user;
    if (role === 'admin' || SPECIALIST_ROLES.includes(role)) throw new HttpError(409, 'This account is already set up in the portal. Delete it from your profile.');
    const existing = await db.get(`applications/${uid}`);
    if (!existing) throw new HttpError(404, 'You have no registration to withdraw.');
    await db.update({ [`applications/${uid}`]: null });
    res.json({ ok: true });
  });

  return router;
}

/** What the applicant sees about their own application: never the reviewer's identity. */
export function publicApplication(a) {
  if (!a) return null;
  return {
    status: a.status,
    name: a.name,
    type: a.type,
    specialty: a.specialty,
    submittedAt: a.submittedAt,
    rejectReason: a.status === 'rejected' ? (a.rejectReason ?? '') : '',
  };
}
