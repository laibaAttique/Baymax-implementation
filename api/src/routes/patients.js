import { Router } from 'express';
import { badRequest, forbidden, notFound } from '../http.js';
import { loadSharedData } from '../lib/patientData.js';
import { DIET_REVIEW_ROLES, EXERCISES, PLAN_EDIT_DAYS, PLAN_ROLES, PlanError, parseDietPlan, parseDietReview, parseWorkoutPlan } from '../lib/plans.js';
import { canEditPlans, openSharedAppointment, patientSummaries, relatedTo } from '../lib/patients.js';
import { ROLE_LABELS, isListed, normalizeAppointment } from '../lib/rules.js';
import { DAY, UID, checkParam, queryText } from '../lib/validate.js';

const KINDS = ['diet', 'workout'];

/**
 * "My patients": the record of each person the specialist has an accepted appointment with, and what the specialist may do for them:
 * set or approve a diet plan (doctor, nutritionist) or workout plan (doctor, trainer), and review the food log day by day (nutritionist).
 * Everything is limited to people the specialist actually treats; anyone else answers 404.
 */
export function patientRoutes({ db, now }) {
  const router = Router();
  router.param('pid', checkParam(UID, 'patient'));
  router.param('date', checkParam(DAY, 'date', 'The date must look like 2026-10-19.'));

  const mine = async (req) => {
    const raw = await db.byChild('appointments', 'specialistId', req.user.uid);
    return Object.entries(raw).map(([id, v]) => normalizeAppointment(id, v)).filter((a) => a && isListed(a));
  };

  const related = async (req) => {
    const list = await mine(req);
    const rel = list.filter((a) => a.patientId === req.params.pid && ['confirmed', 'completed', 'no_show'].includes(a.status));
    if (!rel.length) throw notFound('Patient not found.');
    return { list, rel };
  };

  const asPlanError = (fn) => {
    try {
      return fn();
    } catch (e) {
      if (e instanceof PlanError) throw badRequest(e.message);
      throw e;
    }
  };

  router.get('/', async (req, res) => {
    const q = queryText(req.query.q, 'The search', 80);
    res.json({ patients: patientSummaries(await mine(req), now(), q) });
  });

  router.get('/:pid', async (req, res) => {
    const t = now();
    const { rel } = await related(req);
    const pid = req.params.pid;
    const role = req.user.role;
    const editable = canEditPlans(rel, t);

    const [diet, workout, choice, reviews] = await Promise.all([
      db.get(`specialistPlans/${pid}/diet`),
      db.get(`specialistPlans/${pid}/workout`),
      db.get(`users/${pid}/planChoice`),
      db.get(`dietReviews/${pid}`),
    ]);

    // Shared data: only what the patient ticked for an appointment whose window is open now, and logged.
    const open = openSharedAppointment(rel, t);
    let sharedData = null;
    let sharedLocked = null;
    if (open) {
      sharedData = await loadSharedData(db, open, t);
      await db.update({ [`accessLog/${open.id}/${db.newKey(`accessLog/${open.id}`)}`]: { specialistId: req.user.uid, at: t, opened: Object.keys(sharedData), via: 'patient-record' } });
    } else if (rel.some((a) => a.shares.healthSummary || a.shares.foodLog7d || a.shares.activity30d)) {
      sharedLocked = 'The data this patient shared opens 30 minutes before an accepted appointment and closes 60 minutes after it.';
    }

    const myReviews = Object.entries(reviews ?? {})
      .filter(([, r]) => r.by?.uid === req.user.uid)
      .map(([date, r]) => ({ date, status: r.status, note: r.note ?? '', at: r.at }))
      .sort((x, y) => y.date.localeCompare(x.date))
      .slice(0, 30);

    res.json({
      patient: { id: pid, name: [...rel].sort((x, y) => y.startAt - x.startAt)[0].patientName || 'Patient' },
      appointments: [...rel]
        .sort((x, y) => y.startAt - x.startAt)
        .map((a) => ({ id: a.id, startAt: a.startAt, status: a.status, type: a.type, durationMinutes: a.durationMinutes, consultation: a.consultation, payment: a.payment })),
      plans: { diet: diet ?? null, workout: workout ?? null },
      patientChoice: { diet: choice?.diet ?? 'specialist', workout: choice?.workout ?? 'specialist' },
      reviews: myReviews,
      access: {
        canEditDiet: editable && PLAN_ROLES.diet.includes(role),
        canEditWorkout: editable && PLAN_ROLES.workout.includes(role),
        canReviewDiet: DIET_REVIEW_ROLES.includes(role) && !!openSharedAppointment(rel, t, 'foodLog7d'),
        planEditDays: PLAN_EDIT_DAYS,
      },
      sharedData,
      sharedLocked,
    });
  });

  router.put('/:pid/plans/:kind', async (req, res) => {
    const t = now();
    const kind = req.params.kind;
    if (!KINDS.includes(kind)) throw notFound();
    if (!PLAN_ROLES[kind].includes(req.user.role)) {
      throw forbidden(kind === 'diet' ? 'Only doctors and nutritionists can change a diet plan.' : 'Only doctors and trainers can change a workout plan.');
    }
    const { rel } = await related(req);
    if (!canEditPlans(rel, t)) throw badRequest(`You can change a patient's plan from when you accept their appointment until ${PLAN_EDIT_DAYS} days after it.`);
    const parsed = asPlanError(() => (kind === 'diet' ? parseDietPlan(req.body) : parseWorkoutPlan(req.body)));
    const doc = { ...parsed, by: { uid: req.user.uid, name: req.profile.name, role: req.user.role }, at: t };
    const approved = parsed.status === 'approved';
    await db.update({
      [`specialistPlans/${req.params.pid}/${kind}`]: doc,
      [`users/${req.params.pid}/inbox/plan-${kind}-${t}`]: {
        type: 'appointment',
        title: approved ? `Your ${kind} plan was reviewed` : `Your ${kind} plan was updated`,
        body: `${req.profile.name} (${ROLE_LABELS[req.user.role]}) ${approved ? 'reviewed and approved' : 'updated'} your ${kind} plan.`.slice(0, 240),
        createdAt: t,
        read: false,
        route: kind,
      },
    });
    res.json({ plan: doc });
  });

  router.delete('/:pid/plans/:kind', async (req, res) => {
    const t = now();
    const kind = req.params.kind;
    if (!KINDS.includes(kind)) throw notFound();
    if (!PLAN_ROLES[kind].includes(req.user.role)) throw forbidden('You cannot change this kind of plan.');
    const { rel } = await related(req);
    const existing = await db.get(`specialistPlans/${req.params.pid}/${kind}`);
    if (!existing) throw notFound('There is no specialist plan to remove.');
    if (!canEditPlans(rel, t)) throw badRequest(`You can change a patient's plan from when you accept their appointment until ${PLAN_EDIT_DAYS} days after it.`);
    await db.update({
      [`specialistPlans/${req.params.pid}/${kind}`]: null,
      [`users/${req.params.pid}/inbox/plan-${kind}-${t}`]: {
        type: 'appointment',
        title: `Your ${kind} plan is back to Baymax's`,
        body: `${req.profile.name} removed their ${kind} plan. Baymax's own plan applies again.`.slice(0, 240),
        createdAt: t,
        read: false,
        route: kind,
      },
    });
    res.json({ ok: true });
  });

  router.put('/:pid/diet-reviews/:date', async (req, res) => {
    const t = now();
    if (!DIET_REVIEW_ROLES.includes(req.user.role)) throw forbidden('Only a nutritionist can review food logs.');
    const { rel } = await related(req);
    if (!openSharedAppointment(rel, t, 'foodLog7d')) {
      throw badRequest('The food log can be reviewed while the patient\'s shared data is open (from 30 minutes before an accepted appointment until 60 minutes after it), and only if they shared it.');
    }
    const review = asPlanError(() => parseDietReview(req.body, req.params.date, t));
    const doc = { ...review, by: { uid: req.user.uid, name: req.profile.name }, at: t };
    await db.update({
      [`dietReviews/${req.params.pid}/${req.params.date}`]: doc,
      [`users/${req.params.pid}/inbox/review-${req.params.date}`]: {
        type: 'appointment',
        title: review.status === 'approved' ? 'Your food log was approved' : 'Your nutritionist flagged a day',
        body: `${req.profile.name} ${review.status === 'approved' ? 'approved' : 'flagged'} your food log for ${req.params.date}.${review.note ? ` ${review.note}` : ''}`.slice(0, 240),
        createdAt: t,
        read: false,
        route: 'diet',
      },
    });
    res.json({ review: { date: req.params.date, ...doc } });
  });

  return router;
}

export const exerciseList = () => EXERCISES.map((e) => ({ id: e.id, name: e.name, group: e.group, level: e.level, timed: !!e.timed, baseReps: e.baseReps, baseSeconds: e.baseSeconds }));
