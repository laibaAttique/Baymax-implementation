import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, profile, start } from './helpers.js';

const DAY = 86_400_000;
const ok = (o = {}) => ({ status: 'completed', startAt: NOW - 3 * DAY, ...o });

const data = () => {
  const d = baseData({
    appointments: {
      // doc1's patients
      p1a: appointment(ok({ patientId: 'pat1', patientName: 'Ayesha Khan', consultation: { notes: 'Rest', prescription: 'Vitamin D', updatedAt: NOW - DAY, updatedBy: 'doc1' } })),
      p1b: appointment({ patientId: 'pat1', patientName: 'Ayesha Khan', status: 'confirmed', startAt: NOW + 2 * DAY }),
      p2: appointment(ok({ patientId: 'pat2', patientName: 'Bilal Ahmed', startAt: NOW - 40 * DAY })), // old: plans can no longer be edited
      req: appointment({ patientId: 'pat3', patientName: 'Only Requested', status: 'requested', meetingLink: '', startAt: NOW + 3 * DAY }), // not a patient yet
      gone: appointment({ patientId: 'pat4', patientName: 'Cancelled One', status: 'cancelled', startAt: NOW + DAY }),
      // nut1's patient
      n1: appointment(ok({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', patientId: 'pat1', patientName: 'Ayesha Khan', startAt: NOW - 20 * MIN, status: 'confirmed', shares: { healthSummary: true, foodLog7d: true, activity30d: false } })),
      // trainer's patient
      t1: appointment(ok({ specialistId: 'tr1', specialistName: 'Ali Raza', role: 'trainer', patientId: 'pat1', patientName: 'Ayesha Khan', startAt: NOW - DAY })),
    },
    slots: { doc1: { [NOW + 2 * DAY]: { appt: 'p1b' } } },
    users: {
      pat1: {
        profile: { fullName: 'Ayesha Khan', dob: '1996-04-02', medicalConditions: ['Asthma'], height: { value: 165, unit: 'cm' }, weight: { value: 68, unit: 'kg' } },
        foodLog: { '2026-10-19': { e1: { meal: 'Breakfast', name: 'Paratha', kcal: 300, protein: 6, carbs: 40, fat: 12 } } },
      },
    },
  });
  d.roles.tr1 = 'trainer';
  d.specialists.tr1 = profile('trainer', 'Ali Raza');
  return d;
};

const dietBody = (o = {}) => ({ status: 'modified', targetKcal: 1900, proteinG: 120, carbsG: 210, fatG: 60, avoid: ['Fried foods'], tips: ['Drink water before meals'], note: 'Follow for 4 weeks', ...o });
const day = (n, items) => ({ day: n, rest: !items, items: items ?? [] });
const workoutBody = (o = {}) => ({
  status: 'modified',
  note: 'Build up slowly',
  schedule: [day(1, [{ exerciseId: 'brisk_walk', sets: 1, seconds: 600 }]), day(2), day(3, [{ exerciseId: 'chair_squat', sets: 3, reps: 10, note: 'Slow and controlled' }]), day(4), day(5, [{ exerciseId: 'brisk_walk', sets: 1, seconds: 900 }]), day(6), day(7)],
  ...o,
});

// ---- My patients ------------------------------------------------------------------------------------------------------------------

test('My patients lists only people with an accepted appointment, with search and counts', async () => {
  const s = await start(data());
  try {
    const r = await s.call('GET', '/api/patients', { as: 'doc1' });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.patients.map((p) => p.name).sort(), ['Ayesha Khan', 'Bilal Ahmed']); // not the request-only or cancelled ones
    const ayesha = r.body.patients.find((p) => p.name === 'Ayesha Khan');
    assert.equal(ayesha.appointments, 2);
    assert.equal(ayesha.notesWritten, 1);
    assert.equal(ayesha.nextVisit, NOW + 2 * DAY);
    assert.equal(ayesha.canEditPlans, true);
    assert.equal(r.body.patients.find((p) => p.name === 'Bilal Ahmed').canEditPlans, false);
    assert.deepEqual((await s.call('GET', '/api/patients?q=bil', { as: 'doc1' })).body.patients.map((p) => p.name), ['Bilal Ahmed']);
    assert.equal((await s.call('GET', '/api/patients', { as: 'pat1' })).status, 403);
    assert.equal((await s.call('GET', '/api/patients')).status, 401);
  } finally {
    s.close();
  }
});

test('a patient record shows the specialist\'s own history, never another specialist\'s, and 404 for a stranger', async () => {
  const s = await start(data());
  try {
    const r = (await s.call('GET', '/api/patients/pat1', { as: 'doc1' })).body;
    assert.equal(r.patient.name, 'Ayesha Khan');
    assert.deepEqual(r.appointments.map((a) => a.id), ['p1b', 'p1a']); // newest first, only doc1's
    assert.equal(r.appointments[1].consultation.prescription, 'Vitamin D');
    assert.equal(r.plans.diet, null);
    for (const id of ['pat3', 'pat4', 'nobody']) assert.equal((await s.call('GET', `/api/patients/${id}`, { as: 'doc1' })).status, 404, id);
    assert.equal((await s.call('GET', '/api/patients/pat2', { as: 'nut1' })).status, 404); // pat2 is doc1's patient, not nut1's
  } finally {
    s.close();
  }
});

test('the record opens the patient\'s shared data only while a consented appointment is in its window, and logs it', async () => {
  const s = await start(data());
  try {
    const open = (await s.call('GET', '/api/patients/pat1', { as: 'nut1' })).body; // n1 started 20 minutes ago, food log shared
    assert.equal(open.sharedData.healthSummary.medicalConditions[0], 'Asthma');
    assert.equal(open.sharedData.foodLog7d.length, 7);
    assert.equal(open.sharedData.activity30d, undefined);
    const log = Object.values(s.db.root.accessLog.n1);
    assert.equal(log[0].via, 'patient-record');
    assert.equal(log[0].specialistId, 'nut1');
    const closed = (await s.call('GET', '/api/patients/pat1', { as: 'doc1' })).body; // doc1's appointments shared nothing
    assert.equal(closed.sharedData, null);
    assert.equal(closed.sharedLocked, null);
    s.clock.now = NOW + 3 * DAY; // long after the window
    const later = (await s.call('GET', '/api/patients/pat1', { as: 'nut1' })).body;
    assert.equal(later.sharedData, null);
    assert.match(later.sharedLocked, /opens 30 minutes before/);
  } finally {
    s.close();
  }
});

// ---- plans ------------------------------------------------------------------------------------------------------------------------

test('a nutritionist sets a diet plan; the patient is told and the plan is stored with who set it', async () => {
  const s = await start(data());
  try {
    const r = await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: dietBody() });
    assert.equal(r.status, 200);
    const p = s.db.root.specialistPlans.pat1.diet;
    assert.equal(p.status, 'modified');
    assert.equal(p.targetKcal, 1900);
    assert.deepEqual(p.avoid, ['Fried foods']);
    assert.deepEqual(p.by, { uid: 'nut1', name: 'Sara Khan', role: 'nutritionist' });
    assert.equal(p.at, NOW);
    const note = Object.values(s.db.root.users.pat1.inbox).find((n) => n.route === 'diet');
    assert.match(note.title, /diet plan was updated/);
    // the patient's record now shows it
    assert.equal((await s.call('GET', '/api/patients/pat1', { as: 'nut1' })).body.plans.diet.targetKcal, 1900);
  } finally {
    s.close();
  }
});

test('diet plan: approving as is, doctors allowed, trainers refused, and bad numbers explained', async () => {
  const s = await start(data());
  try {
    const approve = await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: { status: 'approved', note: 'Looks right' } });
    assert.equal(approve.status, 200);
    assert.equal(s.db.root.specialistPlans.pat1.diet.status, 'approved');
    assert.equal(Object.values(s.db.root.users.pat1.inbox).find((n) => n.route === 'diet').title, 'Your diet plan was reviewed');
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'doc1', body: dietBody() })).status, 200);
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'tr1', body: dietBody() })).status, 403);
    const bad = async (o, re) => {
      const r = await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: dietBody(o) });
      assert.equal(r.status, 400, JSON.stringify(o));
      assert.match(r.body.error, re);
    };
    await bad({ targetKcal: 300 }, /calorie target/);
    await bad({ targetKcal: 6000 }, /calorie target/);
    await bad({ proteinG: 400, carbsG: 400, fatG: 100, targetKcal: 1900 }, /differs from the 1900 kcal target/);
    await bad({ carbsG: undefined, fatG: undefined, targetKcal: 1900 }, /together/);
    await bad({ status: 'maybe' }, /Approve as is/);
    await bad({ avoid: ['x'] }, /2 to 50/);
    await bad({ tips: Array(11).fill('Drink more water please') }, /at most 10/);
    await bad({ targetKcal: undefined, proteinG: undefined, carbsG: undefined, fatG: undefined, avoid: [], tips: [] }, /Change at least one thing/);
    await bad({ note: 'x'.repeat(601) }, /600/);
  } finally {
    s.close();
  }
});

test('plans can only be changed for your own patients, while their appointment is recent, and not on a mere request', async () => {
  const s = await start(data());
  try {
    assert.equal((await s.call('PUT', '/api/patients/pat2/plans/diet', { as: 'doc1', body: dietBody() })).status, 400); // 40 days ago
    assert.match((await s.call('PUT', '/api/patients/pat2/plans/diet', { as: 'doc1', body: dietBody() })).body.error, /30 days/);
    assert.equal((await s.call('PUT', '/api/patients/pat3/plans/diet', { as: 'doc1', body: dietBody() })).status, 404); // only a request
    assert.equal((await s.call('PUT', '/api/patients/pat2/plans/diet', { as: 'nut1', body: dietBody() })).status, 404); // not nut1's patient
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/sleep', { as: 'doc1', body: dietBody() })).status, 404);
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'pat1', body: dietBody() })).status, 403);
    assert.equal(s.db.root.specialistPlans, undefined);
  } finally {
    s.close();
  }
});

test('a trainer sets a workout plan from the library only, and the schedule is checked', async () => {
  const s = await start(data());
  try {
    const r = await s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'tr1', body: workoutBody() });
    assert.equal(r.status, 200);
    const w = s.db.root.specialistPlans.pat1.workout;
    assert.equal(w.schedule.length, 7);
    assert.deepEqual(w.schedule[0], { day: 1, rest: false, items: [{ exerciseId: 'brisk_walk', sets: 1, seconds: 600 }] });
    assert.deepEqual(w.schedule[2].items[0], { exerciseId: 'chair_squat', sets: 3, reps: 10, note: 'Slow and controlled' });
    assert.equal(w.schedule[1].rest, true);
    assert.deepEqual(w.by, { uid: 'tr1', name: 'Ali Raza', role: 'trainer' });
    assert.equal(Object.values(s.db.root.users.pat1.inbox).find((n) => n.route === 'workout').title, 'Your workout plan was updated');
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'nut1', body: workoutBody() })).status, 403);
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'doc1', body: workoutBody() })).status, 200);
    assert.equal((await s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'tr1', body: { status: 'approved' } })).status, 200);
    assert.equal(s.db.root.specialistPlans.pat1.workout.status, 'approved');

    const bad = async (o, re) => {
      const r2 = await s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'tr1', body: workoutBody(o) });
      assert.equal(r2.status, 400, JSON.stringify(o).slice(0, 80));
      assert.match(r2.body.error, re);
    };
    const sched = workoutBody().schedule;
    await bad({ schedule: sched.slice(0, 6) }, /seven days/);
    await bad({ schedule: [...sched.slice(0, 6), day(1)] }, /only once/);
    await bad({ schedule: sched.map((d) => (d.day === 1 ? day(1, [{ exerciseId: 'made_up_move', sets: 1, reps: 5 }]) : d)) }, /not an exercise/);
    await bad({ schedule: sched.map((d) => (d.day === 3 ? day(3, [{ exerciseId: 'chair_squat', sets: 0, reps: 10 }]) : d)) }, /Sets/);
    await bad({ schedule: sched.map((d) => (d.day === 3 ? day(3, [{ exerciseId: 'chair_squat', sets: 3 }]) : d)) }, /Reps/);
    await bad({ schedule: sched.map((d) => (d.day === 1 ? day(1, [{ exerciseId: 'brisk_walk', sets: 1 }]) : d)) }, /Seconds/);
    await bad({ schedule: sched.map((d) => (d.day === 2 ? { day: 2, rest: true, items: [{ exerciseId: 'brisk_walk', sets: 1, seconds: 60 }] } : d)) }, /rest day/);
    await bad({ schedule: sched.map((d) => (d.rest ? d : day(d.day))) }, /At least one day/);
    await bad({ schedule: sched.map((d) => (d.day === 1 ? { day: 1, rest: false, items: [] } : d)) }, /1 to 8/);
    await bad({ schedule: sched.map((d) => (d.day === 1 ? { day: 1, rest: false, items: Array(9).fill({ exerciseId: 'chair_squat', sets: 1, reps: 5 }) } : d)) }, /1 to 8/);
  } finally {
    s.close();
  }
});

test('a specialist can remove their plan, which tells the patient the Baymax plan applies again', async () => {
  const s = await start(data());
  try {
    await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: dietBody() });
    assert.equal((await s.call('DELETE', '/api/patients/pat1/plans/diet', { as: 'tr1' })).status, 403);
    assert.equal((await s.call('DELETE', '/api/patients/pat1/plans/diet', { as: 'nut1' })).status, 200);
    assert.equal(s.db.root.specialistPlans, undefined);
    assert.ok(Object.values(s.db.root.users.pat1.inbox).some((n) => /back to Baymax/.test(n.title)));
    assert.equal((await s.call('DELETE', '/api/patients/pat1/plans/diet', { as: 'nut1' })).status, 404); // nothing left to remove
  } finally {
    s.close();
  }
});

// ---- food log review --------------------------------------------------------------------------------------------------------------

test('a nutritionist approves or flags a day of the food log, and the patient is told', async () => {
  const s = await start(data());
  try {
    const approve = await s.call('PUT', '/api/patients/pat1/diet-reviews/2026-10-19', { as: 'nut1', body: { status: 'approved' } });
    assert.equal(approve.status, 200);
    assert.equal(s.db.root.dietReviews.pat1['2026-10-19'].status, 'approved');
    assert.deepEqual(s.db.root.dietReviews.pat1['2026-10-19'].by, { uid: 'nut1', name: 'Sara Khan' });
    const flag = await s.call('PUT', '/api/patients/pat1/diet-reviews/2026-10-18', { as: 'nut1', body: { status: 'flagged', note: 'Too many fried items' } });
    assert.equal(flag.status, 200);
    assert.match(s.db.root.users.pat1.inbox['review-2026-10-18'].title, /flagged/);
    assert.match(s.db.root.users.pat1.inbox['review-2026-10-18'].body, /Too many fried items/);
    // visible on the record, as this nutritionist's own reviews
    const rec = (await s.call('GET', '/api/patients/pat1', { as: 'nut1' })).body;
    assert.deepEqual(rec.reviews.map((r) => [r.date, r.status]), [['2026-10-19', 'approved'], ['2026-10-18', 'flagged']]);
    assert.equal(rec.access.canReviewDiet, true);
    // re-reviewing replaces it
    await s.call('PUT', '/api/patients/pat1/diet-reviews/2026-10-18', { as: 'nut1', body: { status: 'approved' } });
    assert.equal(s.db.root.dietReviews.pat1['2026-10-18'].status, 'approved');
  } finally {
    s.close();
  }
});

test('food log review rules: nutritionists only, shared food log only, inside the window, valid dates, a reason when flagging', async () => {
  const s = await start(data());
  try {
    const put = (as, date, body) => s.call('PUT', `/api/patients/pat1/diet-reviews/${date}`, { as, body });
    assert.equal((await put('doc1', '2026-10-19', { status: 'approved' })).status, 403); // a doctor is not a nutritionist
    assert.equal((await put('tr1', '2026-10-19', { status: 'approved' })).status, 403);
    assert.match((await put('nut1', '2026-10-19', { status: 'flagged' })).body.error, /why you are flagging/);
    assert.match((await put('nut1', '2026-10-19', { status: 'maybe' })).body.error, /Approve/);
    assert.match((await put('nut1', 'yesterday', { status: 'approved' })).body.error, /date must look like/);
    assert.match((await put('nut1', '2026-09-01', { status: 'approved' })).body.error, /last 7 days/);
    s.clock.now = NOW + 3 * DAY; // the window closed
    assert.match((await put('nut1', '2026-10-21', { status: 'approved' })).body.error, /shared data is open/);
    assert.equal(s.db.root.dietReviews, undefined);
    // a patient who did not share the food log cannot be reviewed
    s.clock.now = NOW;
    s.db.root.appointments.n1.shares.foodLog7d = false;
    assert.match((await put('nut1', '2026-10-19', { status: 'approved' })).body.error, /only if they shared it/);
  } finally {
    s.close();
  }
});

// ---- prescriptions, summary, exercises --------------------------------------------------------------------------------------------

test('a doctor sees every prescription they wrote; others do not', async () => {
  const s = await start(data());
  try {
    const r = await s.call('GET', '/api/prescriptions', { as: 'doc1' });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.prescriptions.map((p) => [p.patientName, p.prescription]), [['Ayesha Khan', 'Vitamin D']]);
    assert.equal((await s.call('GET', '/api/prescriptions', { as: 'nut1' })).status, 403);
    assert.equal((await s.call('GET', '/api/prescriptions', { as: 'tr1' })).status, 403);
  } finally {
    s.close();
  }
});

test('the menu summary counts requests and sessions awaiting notes; the exercise list excludes warm-up and cool-down', async () => {
  const s = await start(data());
  try {
    const sum = (await s.call('GET', '/api/summary', { as: 'doc1' })).body;
    assert.equal(sum.pendingRequests, 1);
    assert.equal(typeof sum.awaitingNotes, 'number');
    const ex = (await s.call('GET', '/api/exercises', { as: 'tr1' })).body.exercises;
    assert.ok(ex.length > 50);
    assert.ok(ex.some((e) => e.id === 'brisk_walk' && e.timed));
    assert.ok(!ex.some((e) => e.id === 'warmup' || e.id === 'cooldown'));
    assert.equal((await s.call('GET', '/api/exercises', { as: 'pat1' })).status, 403);
  } finally {
    s.close();
  }
});

// ---- closing an account -----------------------------------------------------------------------------------------------------------

test('closing your own account needs typing DELETE and a recent sign-in', async () => {
  const s = await start(data());
  try {
    assert.equal((await s.call('DELETE', '/api/me', { as: 'doc1', body: {} })).status, 400);
    const stale = await s.call('DELETE', '/api/me', { as: 'doc1', body: { confirm: 'DELETE' }, old: true });
    assert.equal(stale.status, 401);
    assert.equal(stale.body.code, 'reauth-required');
    assert.equal(s.db.root.roles.doc1, 'doctor'); // nothing happened
    assert.deepEqual(s.auth.deleted, []);
  } finally {
    s.close();
  }
});

test('closing an account cancels future bookings, frees the times, tells patients, keeps past records, and deletes the sign-in', async () => {
  const s = await start(data());
  try {
    const r = await s.call('DELETE', '/api/me', { as: 'doc1', body: { confirm: 'DELETE' } });
    assert.equal(r.status, 200);
    assert.equal(r.body.cancelled, 2); // the confirmed future one and the request
    assert.equal(r.body.accountDeleted, true);
    assert.equal(s.db.root.appointments.p1b.status, 'cancelled');
    assert.equal(s.db.root.appointments.req.status, 'cancelled');
    assert.equal(s.db.root.appointments.p1a.status, 'completed'); // the past record stays
    assert.equal(s.db.root.appointments.p1a.consultation.prescription, 'Vitamin D');
    assert.equal(s.db.root.slots, undefined); // all of this specialist's slot records are gone, not just the cancelled ones
    assert.match(s.db.root.users.pat1.inbox['closed-p1b'].title, /cancelled/);
    assert.equal(s.db.root.roles.doc1, undefined);
    assert.equal(s.db.root.specialists.doc1, undefined);
    assert.deepEqual(s.auth.deleted, ['doc1']);
    // the other specialists are untouched
    assert.equal(s.db.root.roles.nut1, 'nutritionist');
    assert.equal(s.db.root.appointments.n1.status, 'confirmed');
  } finally {
    s.close();
  }
});

test('an account that is also a member of the mobile app only loses its specialist side', async () => {
  const d = data();
  d.users.doc1 = { profile: { fullName: 'Hina Malik' } };
  const s = await start(d);
  try {
    const r = await s.call('DELETE', '/api/me', { as: 'doc1', body: { confirm: 'DELETE' } });
    assert.equal(r.body.accountDeleted, false);
    assert.equal(r.body.keptMemberAccount, true);
    assert.deepEqual(s.auth.deleted, []);
    assert.equal(s.db.root.roles.doc1, undefined);
    assert.ok(s.db.root.users.doc1.profile); // their member data is untouched
  } finally {
    s.close();
  }
});

test('an administrator can overview the system and delete a specialist, but not an administrator or themselves', async () => {
  const s = await start(data());
  try {
    const o = (await s.call('GET', '/api/admin/overview', { as: 'adm1' })).body;
    assert.equal(o.specialists.doctor, 2);
    assert.equal(o.specialists.trainer, 1);
    assert.equal(o.appointments.byStatus.completed, 3);
    assert.equal(o.applications.pending, 0);
    assert.equal((await s.call('GET', '/api/admin/overview', { as: 'doc1' })).status, 403);
    assert.equal((await s.call('DELETE', '/api/admin/specialists/nut1', { as: 'doc1' })).status, 403);
    const del = await s.call('DELETE', '/api/admin/specialists/nut1', { as: 'adm1' });
    assert.equal(del.status, 200);
    assert.equal(s.db.root.roles.nut1, undefined);
    assert.equal(s.db.root.specialists.nut1, undefined);
    assert.ok(s.auth.deleted.includes('nut1'));
    assert.equal((await s.call('DELETE', '/api/admin/specialists/adm1', { as: 'adm1' })).status, 409);
    assert.equal((await s.call('DELETE', '/api/admin/specialists/nobody', { as: 'adm1' })).status, 404);
    s.db.root.roles.adm2 = 'admin';
    assert.equal((await s.call('DELETE', '/api/admin/specialists/adm2', { as: 'adm1' })).status, 409); // another administrator is protected
  } finally {
    s.close();
  }
});

test('an applicant can withdraw a registration without losing their sign-in account', async () => {
  const s = await start(baseData());
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: { name: 'New Person', type: 'trainer', specialty: 'Yoga', licenseNumber: 'LIC-12345', fees: { video: 1000, chat: 500 } } });
    assert.ok(s.db.root.applications.newbie);
    assert.equal((await s.call('DELETE', '/api/applications', { as: 'newbie' })).status, 200);
    assert.equal(s.db.root.applications, undefined);
    assert.deepEqual(s.auth.deleted, []); // the account itself is untouched
    assert.equal((await s.call('DELETE', '/api/applications', { as: 'newbie' })).status, 404);
    assert.equal((await s.call('DELETE', '/api/applications', { as: 'doc1' })).status, 409); // specialists delete via their profile
  } finally {
    s.close();
  }
});
