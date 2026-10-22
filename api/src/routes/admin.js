import { Router } from 'express';
import { HttpError } from '../http.js';
import { requireRole } from '../middleware/auth.js';
import { AccountError, deleteSpecialist } from '../lib/accounts.js';
import { AdminError, approveApplication, makeSpecialist, parseNewSpecialist, rejectApplication } from '../lib/specialistAdmin.js';
import { UID, checkParam } from '../lib/validate.js';
import { isListed, normalizeAppointment } from '../lib/rules.js';
import { summarize } from '../lib/payments.js';
import { callSummary } from '../lib/call.js';
import { adminPaymentRoutes } from './payments.js';

/** Administrator-only routes: list the specialists and add new ones. Reached only with the `admin` role (403 for everyone else). */
export function adminRoutes({ auth, db, now }) {
  const router = Router();
  router.use(requireRole('admin'));
  router.param('uid', checkParam(UID, 'user'));
  router.use('/payments', adminPaymentRoutes({ db, now }));

  const wrap = (fn) => async (req, res, next) => {
    try {
      await fn(req, res);
    } catch (e) {
      next(e instanceof AdminError || e instanceof AccountError ? new HttpError(e.status, e.message) : e);
    }
  };

  router.get('/specialists', wrap(async (_req, res) => {
    const all = (await db.get('specialists')) ?? {};
    const ids = Object.keys(all);
    const emails = {};
    for (let i = 0; i < ids.length; i += 100) {
      const r = await auth.getUsers(ids.slice(i, i + 100).map((uid) => ({ uid })));
      for (const u of r.users) emails[u.uid] = u.email ?? '';
    }
    const specialists = ids
      .map((uid) => {
        const s = all[uid];
        return {
          uid,
          email: emails[uid] ?? '',
          name: String(s.name ?? ''),
          type: s.type,
          specialty: String(s.specialty ?? ''),
          fees: s.fees ?? null,
          available: s.available !== false,
          rating: s.rating ?? 0,
          reviewCount: s.reviewCount ?? 0,
        };
      })
      .sort((a, b) => a.type.localeCompare(b.type) || a.name.localeCompare(b.name));
    res.json({ specialists });
  }));

  router.post('/specialists', wrap(async (req, res) => {
    const input = parseNewSpecialist(req.body);
    const out = await makeSpecialist({ auth, db, now }, input);
    res.status(out.created ? 201 : 200).json({ ...out, email: input.email, profile: input.profile });
  }));

  router.get('/overview', wrap(async (_req, res) => {
    const t = now();
    const specialists = (await db.get('specialists')) ?? {};
    const applications = (await db.get('applications')) ?? {};
    const appointments = (await db.get('appointments')) ?? {};
    const byType = { doctor: 0, nutritionist: 0, trainer: 0 };
    for (const s of Object.values(specialists)) if (s.type in byType) byType[s.type]++;
    const byStatus = {};
    for (const a of Object.values(appointments)) byStatus[a.status] = (byStatus[a.status] ?? 0) + 1;
    const list = Object.entries(appointments).map(([id, v]) => normalizeAppointment(id, v)).filter((a) => a && isListed(a));
    const p = summarize(list, t);

    // Video calls the specialists actually opened, and messages exchanged: figures an administrator can check against the bookings.
    const callLog = (await db.get('callLog')) ?? {};
    const byId = new Map(list.map((a) => [a.id, a]));
    let callSessions = 0;
    let callMinutes = 0;
    for (const [id, events] of Object.entries(callLog)) {
      const a = byId.get(id);
      if (!a) continue;
      const c = callSummary(events, a.endAt);
      if (c.joins > 0) {
        callSessions++;
        callMinutes += c.minutes;
      }
    }
    const chats = (await db.get('chats')) ?? {};
    res.json({
      specialists: { total: Object.keys(specialists).length, ...byType },
      applications: { pending: Object.values(applications).filter((a) => a.status === 'pending').length },
      appointments: { total: Object.keys(appointments).length, byStatus },
      payments: {
        gross: p.gross, platformFees: p.platformFees, refunded: p.refunded, refundsDue: p.due, clinicDue: p.clinicDue, held: p.held,
        testPayments: p.testPayments, count: p.count,
      },
      calls: { sessions: callSessions, minutes: callMinutes },
      messages: { conversations: Object.keys(chats).length, total: Object.values(chats).reduce((n, c) => n + Object.keys(c ?? {}).length, 0) },
    });
  }));

  router.delete('/specialists/:uid', wrap(async (req, res) => {
    if (req.params.uid === req.user.uid) throw new AccountError(409, 'You cannot delete your own administrator account here.');
    res.json(await deleteSpecialist({ auth, db, now }, req.params.uid, { by: req.user.uid }));
  }));

  // ---- registrations --------------------------------------------------------------------------------------------------------

  router.get('/applications', wrap(async (_req, res) => {
    const all = (await db.get('applications')) ?? {};
    const order = { pending: 0, rejected: 1, approved: 2 };
    const applications = Object.entries(all)
      .map(([uid, a]) => ({
        uid,
        status: a.status,
        email: a.email,
        name: a.name,
        type: a.type,
        specialty: a.specialty,
        licenseNumber: a.licenseNumber,
        yearsOfExperience: a.profile?.yearsOfExperience ?? 0,
        fees: a.profile?.fees ?? null,
        submittedAt: a.submittedAt,
        rejectReason: a.rejectReason ?? '',
      }))
      .sort((x, y) => (order[x.status] ?? 3) - (order[y.status] ?? 3) || y.submittedAt - x.submittedAt);
    res.json({ applications });
  }));

  router.post('/applications/:uid/approve', wrap(async (req, res) => {
    res.json(await approveApplication({ db, now }, req.params.uid, req.user.uid));
  }));

  router.post('/applications/:uid/reject', wrap(async (req, res) => {
    await rejectApplication({ db, now }, req.params.uid, req.user.uid, req.body?.reason);
    res.json({ ok: true });
  }));

  return router;
}
