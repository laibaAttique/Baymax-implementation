import { Router } from 'express';
import { badRequest, forbidden, notFound } from '../http.js';
import { requireSpecialist } from '../middleware/auth.js';
import {
  ROLE_LABELS, appointmentState, isListed, dashboardCounts, dayBounds, filterAppointments, greeting, normalizeAppointment,
  parseConsultationNote, parseProfileUpdate, sortToday, statusChangeProblem,
} from '../lib/rules.js';
import { loadSharedData } from '../lib/patientData.js';

/** All routes below need a signed-in specialist whose profile exists and matches their role. */
export function specialistRoutes({ db, now }) {
  const router = Router();
  router.use(requireSpecialist);

  // Load the specialist's own profile once per request. A role without a profile (not set up yet) cannot use the portal.
  router.use(async (req, _res, next) => {
    const profile = await db.get(`specialists/${req.user.uid}`);
    if (!profile) throw forbidden('Your specialist profile has not been set up yet. Please contact a Baymax administrator.');
    if (profile.type !== req.user.role) throw forbidden('Your role and specialist profile do not match. Please contact a Baymax administrator.');
    req.profile = profile;
    next();
  });

  const tz = (req) => Number(req.profile.tzOffsetMinutes ?? 300);

  async function myAppointments(req) {
    const raw = await db.byChild('appointments', 'specialistId', req.user.uid);
    return Object.entries(raw).map(([id, v]) => normalizeAppointment(id, v)).filter((a) => a && isListed(a));
  }

  async function ownAppointment(req) {
    const raw = await db.get(`appointments/${req.params.id}`);
    // Someone else's appointment looks exactly like one that does not exist.
    if (!raw || raw.specialistId !== req.user.uid) throw notFound('Appointment not found.');
    const a = normalizeAppointment(req.params.id, raw);
    if (!a || !isListed(a)) throw notFound('Appointment not found.'); // a booking still waiting for payment is not an appointment yet
    return a;
  }

  const present = (a, t) => ({ ...a, ...appointmentState(a, t) });

  router.get('/me', (req, res) => {
    const { uid, email, role } = req.user;
    res.json({ uid, email, role, roleLabel: ROLE_LABELS[role], profile: req.profile });
  });

  router.put('/me/profile', async (req, res) => {
    const parsed = parseProfileUpdate(req.body ?? {});
    if (parsed.error) throw badRequest(parsed.error);
    const updates = {};
    for (const [k, v] of Object.entries(parsed.value)) updates[`specialists/${req.user.uid}/${k}`] = v;
    updates[`specialists/${req.user.uid}/updatedAt`] = now();
    await db.update(updates);
    res.json({ profile: await db.get(`specialists/${req.user.uid}`) });
  });

  router.get('/dashboard', async (req, res) => {
    const t = now();
    const all = await myAppointments(req);
    const day = dayBounds(t, tz(req));
    const today = sortToday(all.filter((a) => a.status !== 'cancelled' && a.startAt >= day.start && a.startAt < day.end), t);
    res.json({
      serverTime: t,
      greeting: greeting(t, tz(req)),
      name: req.profile.name,
      role: req.user.role,
      roleLabel: ROLE_LABELS[req.user.role],
      counts: dashboardCounts(all, t, tz(req)),
      today: today.map((a) => present(a, t)),
    });
  });

  router.get('/appointments', async (req, res) => {
    const t = now();
    const num = (v) => (v === undefined || v === '' ? NaN : Number(v));
    const list = filterAppointments(await myAppointments(req), {
      status: req.query.status,
      from: num(req.query.from),
      to: num(req.query.to),
      q: typeof req.query.q === 'string' ? req.query.q : '',
    });
    list.sort((a, b) => b.startAt - a.startAt);
    res.json({ serverTime: t, appointments: list.slice(0, 500).map((a) => present(a, t)) });
  });

  router.get('/appointments/:id', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    const state = appointmentState(a, t);
    let sharedData = null;
    let sharedLocked = null;
    if (a.shares.healthSummary || a.shares.foodLog7d || a.shares.activity30d) {
      if (state.canViewShared) {
        sharedData = await loadSharedData(db, a, t);
        // Every time shared data is opened it is logged, so a patient or administrator can see who looked and when.
        await db.update({
          [`accessLog/${a.id}/${db.newKey(`accessLog/${a.id}`)}`]: {
            specialistId: req.user.uid,
            at: t,
            opened: Object.keys(sharedData),
          },
        });
      } else {
        sharedLocked = a.status === 'cancelled' ? 'This appointment was cancelled.' : t < a.startAt ? 'Shared data opens 30 minutes before the appointment.' : 'The viewing period for this appointment has ended.';
      }
    }
    res.json({ serverTime: t, appointment: present(a, t), sharedData, sharedLocked });
  });

  router.put('/appointments/:id/consultation', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    if (a.status === 'cancelled') throw badRequest('This appointment was cancelled.');
    if (t < a.startAt) throw badRequest('Notes can be added once the session has started.');
    const parsed = parseConsultationNote(req.body, req.user.role);
    if (parsed.error) throw badRequest(parsed.error);
    const updates = {
      [`appointments/${a.id}/consultation`]: { ...parsed.value, updatedAt: t, updatedBy: req.user.uid },
      [`users/${a.patientId}/inbox/note-${a.id}`]: {
        type: 'appointment',
        title: 'New notes from your specialist',
        body: `${a.specialistName} added notes${parsed.value.prescription ? ' and a prescription' : ''} to your appointment.`.slice(0, 240),
        createdAt: t,
        read: false,
        route: 'appointments',
      },
    };
    await db.update(updates);
    res.json({ appointment: present(normalizeAppointment(a.id, await db.get(`appointments/${a.id}`)), t) });
  });

  router.post('/appointments/:id/status', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    const next = req.body?.status;
    const problem = statusChangeProblem(a, next, t);
    if (problem) throw badRequest(problem);
    const updates = { [`appointments/${a.id}/status`]: next };
    if (next === 'cancelled') {
      // Free the time so someone else can book it, and tell the patient.
      updates[`slots/${a.specialistId}/${a.startAt}`] = null;
      updates[`users/${a.patientId}/inbox/cancel-${a.id}`] = {
        type: 'appointment',
        title: 'Appointment cancelled',
        body: `${a.specialistName} cancelled your appointment. You can book another time.`.slice(0, 240),
        createdAt: t,
        read: false,
        route: 'appointments',
      };
    }
    await db.update(updates);
    res.json({ appointment: present(normalizeAppointment(a.id, await db.get(`appointments/${a.id}`)), t) });
  });

  return router;
}
