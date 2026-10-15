import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, start } from './helpers.js';

const withAppointments = (extra = {}) =>
  baseData({
    appointments: {
      a1: appointment({ startAt: NOW + 60 * MIN }),
      a2: appointment({ patientName: 'Bilal Ahmed', patientId: 'pat2', startAt: NOW - 10 * MIN }),
      a3: appointment({ patientName: 'Omar Sheikh', patientId: 'pat3', startAt: NOW - 3 * 86_400_000, status: 'completed' }),
      held: appointment({ patientName: 'Held Payer', patientId: 'pat9', startAt: NOW + 90 * MIN, status: 'pending_payment', holdUntil: NOW + 5 * MIN }),
      other: appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', patientName: 'Not Yours', startAt: NOW + 30 * MIN }),
    },
    slots: { doc1: { [NOW + 60 * MIN]: { appt: 'a1' } } },
    users: {
      pat1: {
        profile: { fullName: 'Ayesha Khan', dob: '1996-04-02', gender: 'Female', height: { value: 165, unit: 'cm' }, weight: { value: 68, unit: 'kg' }, calculatedBMI: 25, healthClassification: 'Overweight', medicalConditions: ['Asthma'], foodAllergies: ['Peanuts'], medications: 'Inhaler' },
        foodLog: { '2026-10-19': { e1: { meal: 'Breakfast', name: 'Paratha', kcal: 300, protein: 6, carbs: 40, fat: 12 } }, '2026-10-01': { e2: { meal: 'Lunch', name: 'Old', kcal: 999 } } },
        activity: { '2026-10-18': { workoutDone: true, minutes: 40, kcal: 250 } },
      },
    },
    ...extra,
  });

test('requests without a valid token are turned away', async () => {
  const s = await start(withAppointments());
  try {
    assert.equal((await s.call('GET', '/api/me')).status, 401);
    const garbage = await fetch(`${s.base}/api/me`, { headers: { Authorization: 'Bearer not-a-real-token' } });
    assert.equal(garbage.status, 401);
    const wrongScheme = await fetch(`${s.base}/api/me`, { headers: { Authorization: 'Basic token-doc1' } });
    assert.equal(wrongScheme.status, 401);
    assert.equal((await fetch(`${s.base}/health`)).status, 200); // the only open route
  } finally {
    s.close();
  }
});

test('only specialists with a matching profile get in (403 otherwise, even by typing the address)', async () => {
  const s = await start(withAppointments());
  try {
    for (const who of ['pat1', 'adm1', 'nobody']) {
      for (const path of ['/api/me', '/api/dashboard', '/api/appointments', '/api/appointments/a1']) {
        assert.equal((await s.call('GET', path, { as: who })).status, 403, `${who} ${path}`);
      }
    }
    const noProfile = await s.call('GET', '/api/me', { as: 'ghost' });
    assert.equal(noProfile.status, 403);
    assert.match(noProfile.body.error, /not been set up/);
    const mismatch = await s.call('GET', '/api/me', { as: 'mixed' });
    assert.equal(mismatch.status, 403);
    assert.match(mismatch.body.error, /do not match/);
  } finally {
    s.close();
  }
});

test('/me returns the role and profile', async () => {
  const s = await start(withAppointments());
  try {
    const r = await s.call('GET', '/api/me', { as: 'doc1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.roleLabel, 'Doctor');
    assert.equal(r.body.profile.name, 'Hina Malik');
  } finally {
    s.close();
  }
});

test('the dashboard shows this specialist\'s day only, live session first', async () => {
  const s = await start(withAppointments());
  try {
    const r = await s.call('GET', '/api/dashboard', { as: 'doc1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.greeting, 'Good Morning');
    assert.deepEqual(r.body.today.map((a) => a.id), ['a2', 'a1']);
    assert.equal(r.body.today[0].canJoin, true);
    assert.equal(r.body.today[0].phase, 'live');
    assert.equal(r.body.today[1].canJoin, false);
    assert.equal(r.body.counts.consultationsToday, 2);
    assert.equal(r.body.counts.awaitingNotes, 1);
    assert.ok(!r.body.today.some((a) => a.patientName === 'Not Yours'));
  } finally {
    s.close();
  }
});

test('the appointment list is filterable and never includes another specialist\'s patients', async () => {
  const s = await start(withAppointments());
  try {
    const all = await s.call('GET', '/api/appointments', { as: 'doc1' });
    assert.deepEqual(all.body.appointments.map((a) => a.id), ['a1', 'a2', 'a3']); // newest first
    assert.deepEqual((await s.call('GET', '/api/appointments?status=completed', { as: 'doc1' })).body.appointments.map((a) => a.id), ['a3']);
    assert.deepEqual((await s.call('GET', '/api/appointments?q=bilal', { as: 'doc1' })).body.appointments.map((a) => a.id), ['a2']);
    assert.deepEqual((await s.call('GET', `/api/appointments?from=${NOW - 86_400_000}&to=${NOW + 3_600_000}`, { as: 'doc1' })).body.appointments.map((a) => a.id), ['a2']);
    assert.deepEqual((await s.call('GET', '/api/appointments', { as: 'nut1' })).body.appointments.map((a) => a.id), ['other']);
  } finally {
    s.close();
  }
});

test('a booking still waiting for payment is invisible to the specialist everywhere', async () => {
  const s = await start(withAppointments());
  try {
    const list = await s.call('GET', '/api/appointments', { as: 'doc1' });
    assert.ok(!list.body.appointments.some((a) => a.id === 'held'));
    const dash = await s.call('GET', '/api/dashboard', { as: 'doc1' });
    assert.ok(!dash.body.today.some((a) => a.id === 'held'));
    assert.equal(dash.body.counts.consultationsToday, 2); // the held booking is not counted
    assert.equal(dash.body.counts.patients, 3); // pat1, pat2, pat3 but not pat9
    assert.equal((await s.call('GET', '/api/appointments/held', { as: 'doc1' })).status, 404);
    assert.equal((await s.call('PUT', '/api/appointments/held/consultation', { as: 'doc1', body: { notes: 'x' } })).status, 404);
    assert.equal((await s.call('POST', '/api/appointments/held/status', { as: 'doc1', body: { status: 'cancelled' } })).status, 404);
  } finally {
    s.close();
  }
});

test('the specialist sees whether an appointment is paid', async () => {
  const data = withAppointments();
  data.appointments.a1.payment = { status: 'paid', method: 'card', total: 2500, mode: 'sandbox', transactionId: 'TXN-9', last4: '4242', brand: 'Visa' };
  data.appointments.a2.payment = { status: 'pay_at_clinic', method: 'clinic', total: 2500, mode: 'sandbox', transactionId: 'TXN-8' };
  const s = await start(data);
  try {
    const list = (await s.call('GET', '/api/appointments', { as: 'doc1' })).body.appointments;
    assert.equal(list.find((a) => a.id === 'a1').payment.status, 'paid');
    assert.equal(list.find((a) => a.id === 'a2').payment.status, 'pay_at_clinic');
    assert.equal(list.find((a) => a.id === 'a3').payment, null);
    assert.equal(JSON.stringify(list).includes('4242'), false); // no card details are passed on
  } finally {
    s.close();
  }
});

test('another specialist\'s appointment looks like it does not exist', async () => {
  const s = await start(withAppointments());
  try {
    assert.equal((await s.call('GET', '/api/appointments/other', { as: 'doc1' })).status, 404);
    assert.equal((await s.call('GET', '/api/appointments/nope', { as: 'doc1' })).status, 404);
    assert.equal((await s.call('PUT', '/api/appointments/other/consultation', { as: 'doc1', body: { notes: 'x' } })).status, 404);
    assert.equal((await s.call('POST', '/api/appointments/other/status', { as: 'doc1', body: { status: 'cancelled' } })).status, 404);
  } finally {
    s.close();
  }
});

test('shared data: nothing unless the patient ticked it, and only inside the window', async () => {
  const data = withAppointments();
  data.appointments.a1.shares = { healthSummary: true, foodLog7d: true, activity30d: false };
  data.appointments.a1.startAt = data.appointments.a1.slotKey = undefined;
  data.appointments.a1.startAt = NOW + 20 * MIN; // inside the 30-minute prepare window
  data.appointments.a1.slotKey = String(NOW + 20 * MIN);
  const s = await start(data);
  try {
    const r = await s.call('GET', '/api/appointments/a1', { as: 'doc1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.appointment.canPrepare, true);
    assert.equal(r.body.sharedData.healthSummary.medicalConditions[0], 'Asthma');
    assert.equal(r.body.sharedData.healthSummary.age, 30);
    assert.equal(r.body.sharedData.foodLog7d.length, 7);
    assert.equal(r.body.sharedData.foodLog7d[0].totalKcal, 300);
    assert.ok(!r.body.sharedData.foodLog7d.some((d) => d.date === '2026-10-01')); // outside seven days
    assert.equal(r.body.sharedData.activity30d, undefined); // not ticked
    // opening it was logged
    const log = Object.values(s.db.root.accessLog.a1);
    assert.equal(log.length, 1);
    assert.equal(log[0].specialistId, 'doc1');
    assert.deepEqual(log[0].opened, ['healthSummary', 'foodLog7d']);

    s.clock.now = NOW - 20 * MIN; // 40 minutes before the start: too early
    const early = await s.call('GET', '/api/appointments/a1', { as: 'doc1' });
    assert.equal(early.body.sharedData, null);
    assert.match(early.body.sharedLocked, /30 minutes before/);

    s.clock.now = NOW + 20 * MIN + 30 * MIN + 61 * MIN; // after the grace period
    const late = await s.call('GET', '/api/appointments/a1', { as: 'doc1' });
    assert.equal(late.body.sharedData, null);
    assert.match(late.body.sharedLocked, /ended/);
  } finally {
    s.close();
  }
});

test('an appointment with nothing ticked never reads the patient\'s data', async () => {
  const s = await start(withAppointments());
  try {
    const r = await s.call('GET', '/api/appointments/a2', { as: 'doc1' });
    assert.equal(r.body.sharedData, null);
    assert.equal(r.body.sharedLocked, null);
    assert.equal(s.db.root.accessLog, undefined);
  } finally {
    s.close();
  }
});

test('notes: written after the start, prescriptions for doctors only, and the patient is told', async () => {
  const data = withAppointments();
  data.appointments.n1 = appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', startAt: NOW - 5 * MIN });
  const s = await start(data);
  try {
    const early = await s.call('PUT', '/api/appointments/a1/consultation', { as: 'doc1', body: { notes: 'x' } });
    assert.equal(early.status, 400);
    assert.match(early.body.error, /started/);

    const nut = await s.call('PUT', '/api/appointments/n1/consultation', { as: 'nut1', body: { notes: 'Eat more fibre', prescription: 'Drug' } });
    assert.equal(nut.status, 400);
    assert.match(nut.body.error, /doctor/);

    const ok = await s.call('PUT', '/api/appointments/a2/consultation', { as: 'doc1', body: { notes: 'Rest and fluids', prescription: 'Paracetamol 500mg' } });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.appointment.consultation.prescription, 'Paracetamol 500mg');
    assert.equal(ok.body.appointment.consultation.updatedAt, NOW);
    const inbox = s.db.root.users.pat2.inbox['note-a2'];
    assert.equal(inbox.type, 'appointment');
    assert.equal(inbox.route, 'appointments');
    assert.equal(inbox.read, false);
    assert.ok(inbox.title.length <= 80 && inbox.body.length <= 240);
  } finally {
    s.close();
  }
});

test('cancelling frees the slot and tells the patient; finished appointments cannot be changed again', async () => {
  const s = await start(withAppointments());
  try {
    assert.ok(s.db.root.slots.doc1[NOW + 60 * MIN]);
    const r = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: 'cancelled' } });
    assert.equal(r.status, 200);
    assert.equal(r.body.appointment.status, 'cancelled');
    assert.equal(s.db.root.slots, undefined); // the slot is free again
    assert.equal(s.db.root.users.pat1.inbox['cancel-a1'].title, 'Appointment cancelled');
    const again = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: 'completed' } });
    assert.equal(again.status, 400);
    assert.match(again.body.error, /already cancelled/);
  } finally {
    s.close();
  }
});

test('marking complete or missed follows the clock', async () => {
  const s = await start(withAppointments());
  try {
    const early = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: 'completed' } });
    assert.equal(early.status, 400);
    const live = await s.call('POST', '/api/appointments/a2/status', { as: 'doc1', body: { status: 'completed' } });
    assert.equal(live.status, 200);
    assert.equal(live.body.appointment.status, 'completed');
    const bogus = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: 'deleted' } });
    assert.equal(bogus.status, 400);
  } finally {
    s.close();
  }
});

test('profile edits write only the allowed fields under the caller\'s own uid', async () => {
  const s = await start(withAppointments());
  try {
    const bad = await s.call('PUT', '/api/me/profile', { as: 'doc1', body: { fees: { video: -5, chat: 1 } } });
    assert.equal(bad.status, 400);
    const r = await s.call('PUT', '/api/me/profile', { as: 'doc1', body: { bio: 'Hello', available: false, rating: 5, type: 'trainer', fees: { video: 3000, chat: 1800 } } });
    assert.equal(r.status, 200);
    assert.equal(s.db.root.specialists.doc1.bio, 'Hello');
    assert.equal(s.db.root.specialists.doc1.available, false);
    assert.equal(s.db.root.specialists.doc1.fees.video, 3000);
    assert.equal(s.db.root.specialists.doc1.type, 'doctor'); // not changeable here
    assert.equal(s.db.root.specialists.doc1.rating, undefined); // not changeable here
    assert.equal(s.db.root.specialists.nut1.bio, undefined);
  } finally {
    s.close();
  }
});

test('malformed JSON gets a clean 400 and unknown routes a 404', async () => {
  const s = await start(withAppointments());
  try {
    const res = await fetch(`${s.base}/api/me/profile`, {
      method: 'PUT',
      headers: { Authorization: 'Bearer token-doc1', 'Content-Type': 'application/json' },
      body: '{not json',
    });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /valid JSON/);
    assert.equal((await s.call('GET', '/api/nothing-here', { as: 'doc1' })).status, 404);
  } finally {
    s.close();
  }
});
