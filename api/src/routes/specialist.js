import { Router } from 'express';
import { badRequest, forbidden } from '../http.js';
import { randomBytes as nodeRandomBytes } from 'node:crypto';
import { requireSpecialist } from '../middleware/auth.js';
import {
  REAL_STATUSES, ROLE_LABELS, SPECIALIST_ROLES, STATUSES, appointmentState, buildMeetingLink, newRoomName, respondProblem, dashboardCounts, dayBounds, filterAppointments, greeting, normalizeAppointment,
  parseConsultationNote, parseProfileUpdate, sortToday, statusChangeProblem,
} from '../lib/rules.js';
import { loadSharedData } from '../lib/patientData.js';
import { publicApplication } from './applications.js';
import { exerciseList, patientRoutes } from './patients.js';
import { chatRoutes, unreadTotal } from './chats.js';
import { specialistPaymentRoutes } from './payments.js';
import { deleteSpecialist } from '../lib/accounts.js';
import { HttpError } from '../http.js';
import { CALL_EVENTS, MAX_CALL_EVENTS, callInfo, callSummary } from '../lib/call.js';
import { chatState } from '../lib/chat.js';
import { listAppointments, ownAppointment as loadOwnAppointment } from '../lib/own.js';
import { refundInbox, refundWrites } from '../lib/payments.js';
import { activeClientIds, roleCards } from '../lib/roleCards.js';
import { ID, checkParam, queryChoice, queryRange, queryText } from '../lib/validate.js';

/** The specialist's own profile. A role without a profile (not set up yet) or with a different type cannot use the portal. */
async function loadSpecialistProfile(db, user) {
  const profile = await db.get(`specialists/${user.uid}`);
  if (!profile) throw forbidden('Your specialist profile has not been set up yet. Please contact a Baymax administrator.');
  if (profile.type !== user.role) throw forbidden('Your role and specialist profile do not match. Please contact a Baymax administrator.');
  return profile;
}

/** Who am I: open to specialists and administrators, so the web app knows which screens to show. */
export function meRoutes({ db }) {
  const router = Router();
  router.get('/me', async (req, res) => {
    const { uid, email, role } = req.user;
    if (role === 'admin') return res.json({ uid, email, role, roleLabel: 'Administrator', profile: null });
    if (!SPECIALIST_ROLES.includes(role)) {
      // Not a specialist (yet): the web app shows the registration form, or the state of the person's application.
      return res.json({ uid, email, role: 'user', roleLabel: 'Not yet a specialist', profile: null, application: publicApplication(await db.get(`applications/${uid}`)) });
    }
    res.json({ uid, email, role, roleLabel: ROLE_LABELS[role], profile: await loadSpecialistProfile(db, req.user) });
  });
  return router;
}

/** All routes below need a signed-in specialist whose profile exists and matches their role. */
export function specialistRoutes({ auth, db, now, meetingBase = 'https://meet.jit.si', randomBytes = nodeRandomBytes }) {
  const router = Router();
  router.use(requireSpecialist);

  router.use(async (req, _res, next) => {
    req.profile = await loadSpecialistProfile(db, req.user);
    next();
  });

  const tz = (req) => Number(req.profile.tzOffsetMinutes ?? 300);

  const myAppointments = (req) => listAppointments(db, req.user.uid);
  // Someone else's appointment looks exactly like one that does not exist; a booking still waiting for payment is not an appointment yet.
  const ownAppointment = (req) => loadOwnAppointment(db, req.user.uid, req.params.id);

  const present = (a, t) => ({ ...a, ...appointmentState(a, t) });

  router.param('id', checkParam(ID, 'appointment'));
  router.use('/patients', patientRoutes({ db, now }));
  router.use('/chats', chatRoutes({ db, now }));
  router.use('/payments', specialistPaymentRoutes({ db, now }));

  router.get('/exercises', (_req, res) => res.json({ exercises: exerciseList() }));

  /** The small numbers the portal shows in its menu: requests waiting and sessions awaiting notes. */
  router.get('/summary', async (req, res) => {
    const t = now();
    const all = await myAppointments(req);
    const counts = dashboardCounts(all, t, tz(req));
    res.json({ pendingRequests: counts.pendingRequests, awaitingNotes: counts.awaitingNotes, unreadMessages: await unreadTotal(db, all, req.user.uid, t) });
  });

  /** Every prescription this doctor has written (FR-6). */
  router.get('/prescriptions', async (req, res) => {
    if (req.user.role !== 'doctor') throw forbidden('Only doctors write prescriptions.');
    const prescriptions = (await myAppointments(req))
      .filter((a) => a.consultation?.prescription)
      .map((a) => ({ appointmentId: a.id, patientName: a.patientName, startAt: a.startAt, prescription: a.consultation.prescription, updatedAt: a.consultation.updatedAt }))
      .sort((x, y) => y.updatedAt - x.updatedAt);
    res.json({ prescriptions });
  });

  /** Close the specialist's own account. Needs a sign-in within the last 5 minutes, so a left-open browser cannot do it. */
  router.delete('/me', async (req, res) => {
    const t = now();
    if (req.body?.confirm !== 'DELETE') throw badRequest('Type DELETE to confirm.');
    if (!req.user.authTime || t - req.user.authTime > 5 * 60_000) {
      throw new HttpError(401, 'For your security, please sign in again, then delete your account.', 'reauth-required');
    }
    res.json(await deleteSpecialist({ auth, db, now }, req.user.uid, { by: req.user.uid }));
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

  /** Patients whose shared food log is open right now and has a day this nutritionist has not reviewed yet. */
  async function dietReviewsWaiting(all, t) {
    const open = new Map();
    for (const a of all) if (a.shares.foodLog7d && appointmentState(a, t).canViewShared) open.set(a.patientId, a);
    let waiting = 0;
    for (const pid of open.keys()) {
      const reviews = (await db.get(`dietReviews/${pid}`)) ?? {};
      const days = Array.from({ length: 7 }, (_, i) => new Date(t - i * 86_400_000).toISOString().slice(0, 10));
      if (days.some((d) => !reviews[d])) waiting++;
    }
    return waiting;
  }

  /** Active trainees who have no workout plan from a specialist yet (a trainer or doctor reviewing it would be the first). */
  async function workoutsToReview(all, t) {
    let n = 0;
    for (const pid of activeClientIds(all, t)) if (!(await db.get(`specialistPlans/${pid}/workout`))) n++;
    return n;
  }

  router.get('/dashboard', async (req, res) => {
    const t = now();
    const all = await myAppointments(req);
    const day = dayBounds(t, tz(req));
    // Today's list is real sessions only; requests waiting for an answer have their own list.
    const today = sortToday(all.filter((a) => REAL_STATUSES.includes(a.status) && a.startAt >= day.start && a.startAt < day.end), t);
    const requests = all.filter((a) => a.status === 'requested' && a.startAt > t).sort((a, b) => a.startAt - b.startAt);
    const counts = dashboardCounts(all, t, tz(req));
    const extra = { unreadMessages: await unreadTotal(db, all, req.user.uid, t) };
    if (req.user.role === 'nutritionist') extra.dietReviewsWaiting = await dietReviewsWaiting(all, t);
    if (req.user.role === 'trainer') extra.workoutsToReview = await workoutsToReview(all, t);
    res.json({
      serverTime: t,
      greeting: greeting(t, tz(req)),
      name: req.profile.name,
      role: req.user.role,
      roleLabel: ROLE_LABELS[req.user.role],
      counts,
      cards: roleCards(req.user.role, { all, now: t, counts, extra }),
      requests: requests.map((a) => present(a, t)),
      today: today.map((a) => present(a, t)),
    });
  });

  router.get('/appointments', async (req, res) => {
    const t = now();
    const { from, to } = queryRange(req.query);
    const status = queryChoice(req.query.status, 'Status', STATUSES);
    const q = queryText(req.query.q, 'The search', 80);
    const list = filterAppointments(await myAppointments(req), { status, from: from ?? NaN, to: to ?? NaN, q });
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
        sharedLocked =
          a.status === 'requested' ? 'Accept the request to see what the patient chose to share. It opens 30 minutes before the appointment.'
          : a.status === 'cancelled' || a.status === 'declined' ? `This appointment was ${a.status}.`
          : t < a.startAt ? 'Shared data opens 30 minutes before the appointment.'
          : 'The viewing period for this appointment has ended.';
      }
    }
    const events = await db.get(`callLog/${a.id}`);
    res.json({ serverTime: t, appointment: present(a, t), sharedData, sharedLocked, call: callSummary(events, a.endAt), chat: chatState(a, t) });
  });

  /**
   * The video room (FR-3, FR10.5). The room's name is handed over only while the person may join, so the page cannot open it early.
   * The page also reports when the specialist joined and left, which is what the call log (and the administrator's call figures) hold.
   */
  router.get('/appointments/:id/call', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    res.json({ ...callInfo(a, t, appointmentState(a, t), meetingBase), displayName: req.profile.name, summary: callSummary(await db.get(`callLog/${a.id}`), a.endAt) });
  });

  router.post('/appointments/:id/call/event', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    const event = req.body?.event;
    if (!CALL_EVENTS.includes(event)) throw badRequest(`The event must be one of: ${CALL_EVENTS.join(', ')}.`);
    if (!['confirmed', 'completed'].includes(a.status)) throw badRequest('There is no call for this appointment.');
    // Joining is only logged while the room is open; leaving is always logged, so a call that overran the slot still closes.
    if (event === 'joined' && !appointmentState(a, t).canJoin) throw badRequest('The room is not open right now.');
    const log = (await db.get(`callLog/${a.id}`)) ?? {};
    if (Object.keys(log).length >= MAX_CALL_EVENTS) throw badRequest('This call has too many log entries.');
    await db.update({ [`callLog/${a.id}/${db.newKey(`callLog/${a.id}`)}`]: { uid: req.user.uid, role: req.user.role, event, at: t } });
    res.status(201).json({ summary: callSummary({ ...log, new: { event, at: t } }, a.endAt) });
  });

  router.put('/appointments/:id/consultation', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    if (!REAL_STATUSES.includes(a.status)) throw badRequest(a.status === 'requested' ? 'Accept the request first.' : `This appointment was ${a.status.replace('_', ' ')}.`);
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

  // Accepting a request creates the video room: the link is made here, on the server, never by the patient's phone.
  router.post('/appointments/:id/accept', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    const problem = respondProblem(a, t);
    if (problem) throw badRequest(problem);
    const link = buildMeetingLink(meetingBase, newRoomName(randomBytes), a.type);
    await db.update({
      [`appointments/${a.id}/status`]: 'confirmed',
      [`appointments/${a.id}/meetingLink`]: link,
      [`appointments/${a.id}/respondedAt`]: t,
      // The slot stays locked (it is now a confirmed booking).
      [`users/${a.patientId}/inbox/accept-${a.id}`]: {
        type: 'appointment',
        title: 'Your appointment was accepted',
        body: `${a.specialistName} accepted your request. The video link is in My appointments.`.slice(0, 240),
        createdAt: t,
        read: false,
        route: 'appointments',
      },
    });
    res.json({ appointment: present(normalizeAppointment(a.id, await db.get(`appointments/${a.id}`)), t) });
  });

  router.post('/appointments/:id/decline', async (req, res) => {
    const t = now();
    const a = await ownAppointment(req);
    const problem = respondProblem(a, t);
    if (problem) throw badRequest(problem);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
    if (reason.length > 200) throw badRequest('The reason can be at most 200 characters.');
    const refunded = refundWrites(a, t, { reason: reason || 'The specialist declined the request.', by: 'specialist' });
    const refund = Object.keys(refunded).length ? ' Your payment was refunded.' : '';
    await db.update({
      ...refunded,
      ...(refund ? { [`users/${a.patientId}/inbox/refund-${a.id}`]: refundInbox(a, t, 'The specialist declined your request.') } : {}),
      [`appointments/${a.id}/status`]: 'declined',
      [`appointments/${a.id}/declineReason`]: reason || null,
      [`appointments/${a.id}/respondedAt`]: t,
      [`slots/${a.specialistId}/${a.startAt}`]: null, // the time is free for someone else
      [`users/${a.patientId}/inbox/decline-${a.id}`]: {
        type: 'appointment',
        title: 'Your request was not accepted',
        body: `${a.specialistName} could not take this appointment. You can book another time.${refund}`.slice(0, 240),
        createdAt: t,
        read: false,
        route: 'appointments',
      },
    });
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
      // Free the time so someone else can book it, return a payment taken for it, and tell the patient.
      Object.assign(updates, refundWrites(a, t, { reason: 'The specialist cancelled the appointment.', by: 'specialist' }));
      if (Object.keys(updates).length > 1) updates[`users/${a.patientId}/inbox/refund-${a.id}`] = refundInbox(a, t, 'The specialist cancelled your appointment.');
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
