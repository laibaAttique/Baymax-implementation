import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, start } from './helpers.js';

const data = () =>
  baseData({
    appointments: {
      r1: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 120 * MIN, patientName: 'Ayesha Khan', patientId: 'pat1', payment: { status: 'paid', method: 'card', total: 2500, mode: 'sandbox', transactionId: 'T1' } }),
      r2: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 180 * MIN, patientName: 'Bilal Ahmed', patientId: 'pat2', type: 'chat' }),
      late: appointment({ status: 'requested', meetingLink: '', startAt: NOW - 30 * MIN, patientName: 'Too Late', patientId: 'pat3' }),
      ok: appointment({ status: 'confirmed', startAt: NOW + 60 * MIN, patientName: 'Confirmed One', patientId: 'pat4' }),
      other: appointment({ status: 'requested', meetingLink: '', specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', startAt: NOW + 120 * MIN }),
    },
    slots: { doc1: { [NOW + 120 * MIN]: { appt: 'r1' }, [NOW + 180 * MIN]: { appt: 'r2' } } },
    users: { pat1: { profile: { fullName: 'Ayesha Khan', dob: '1996-04-02', medicalConditions: ['Asthma'] } } },
  });

test('requests wait in their own list, not in today\'s sessions, and are counted', async () => {
  const s = await start(data());
  try {
    const d = (await s.call('GET', '/api/dashboard', { as: 'doc1' })).body;
    assert.deepEqual(d.requests.map((a) => a.id), ['r1', 'r2']); // soonest first; the expired one is not offered
    assert.deepEqual(d.today.map((a) => a.id), ['ok']);
    assert.equal(d.counts.pendingRequests, 2);
    assert.equal(d.requests[0].canRespond, true);
    assert.equal(d.requests[0].meetingLink, ''); // no video room yet
    assert.equal(d.requests[0].canJoin, false);
    assert.equal(d.counts.patients, 1); // only the real session's patient
  } finally {
    s.close();
  }
});

test('an unanswered request whose time has passed shows as expired and cannot be answered', async () => {
  const s = await start(data());
  try {
    const list = (await s.call('GET', '/api/appointments', { as: 'doc1' })).body.appointments;
    const late = list.find((a) => a.id === 'late');
    assert.equal(late.phase, 'expired');
    assert.equal(late.canRespond, false);
    const r = await s.call('POST', '/api/appointments/late/accept', { as: 'doc1' });
    assert.equal(r.status, 400);
    assert.match(r.body.error, /expired/);
  } finally {
    s.close();
  }
});

test('accepting creates the video room on the server, confirms the booking, keeps the slot and tells the patient', async () => {
  const s = await start(data());
  try {
    const r = await s.call('POST', '/api/appointments/r1/accept', { as: 'doc1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.appointment.status, 'confirmed');
    const link = s.db.root.appointments.r1.meetingLink;
    assert.match(link, /^https:\/\/meet\.jit\.si\/baymax-[a-z0-9]{20}$/);
    assert.equal(s.db.root.appointments.r1.respondedAt, NOW);
    assert.ok(s.db.root.slots.doc1[NOW + 120 * MIN]); // still booked
    const n = s.db.root.users.pat1.inbox['accept-r1'];
    assert.equal(n.type, 'appointment');
    assert.match(n.title, /accepted/);
    assert.equal(n.route, 'appointments');
    // a different request gets a different, unguessable room
    await s.call('POST', '/api/appointments/r2/accept', { as: 'doc1' });
    const link2 = s.db.root.appointments.r2.meetingLink;
    assert.notEqual(link, link2);
    assert.match(link2, /#config\.startWithVideoMuted=true/); // r2 is chat only: camera and microphone off
    // it cannot be accepted twice
    const again = await s.call('POST', '/api/appointments/r1/accept', { as: 'doc1' });
    assert.equal(again.status, 400);
    assert.match(again.body.error, /already accepted/);
  } finally {
    s.close();
  }
});

test('declining frees the time, keeps the reason and tells the patient; a declined request cannot be accepted', async () => {
  const s = await start(data());
  try {
    const r = await s.call('POST', '/api/appointments/r2/decline', { as: 'doc1', body: { reason: '  On leave that day  ' } });
    assert.equal(r.status, 200);
    assert.equal(r.body.appointment.status, 'declined');
    assert.equal(s.db.root.appointments.r2.declineReason, 'On leave that day');
    assert.equal(s.db.root.slots.doc1[NOW + 180 * MIN], undefined); // free again
    assert.ok(s.db.root.slots.doc1[NOW + 120 * MIN]); // the other request keeps its slot
    assert.equal(s.db.root.users.pat2.inbox['decline-r2'].title, 'Your request was not accepted');
    assert.equal(s.db.root.appointments.r2.meetingLink, ''); // no room was ever made
    const accept = await s.call('POST', '/api/appointments/r2/accept', { as: 'doc1' });
    assert.equal(accept.status, 400);
    assert.match(accept.body.error, /already declined/);
    assert.equal((await s.call('POST', '/api/appointments/r1/decline', { as: 'doc1', body: { reason: 'x'.repeat(201) } })).status, 400);
    assert.equal((await s.call('POST', '/api/appointments/r1/decline', { as: 'doc1', body: {} })).status, 200); // a reason is optional
  } finally {
    s.close();
  }
});

test('only the specialist the request was sent to can answer it', async () => {
  const s = await start(data());
  try {
    for (const action of ['accept', 'decline']) {
      assert.equal((await s.call('POST', `/api/appointments/other/${action}`, { as: 'doc1' })).status, 404, action);
      assert.equal((await s.call('POST', `/api/appointments/r1/${action}`, { as: 'pat1' })).status, 403, action);
      assert.equal((await s.call('POST', `/api/appointments/r1/${action}`)).status, 401, action);
    }
    assert.equal(s.db.root.appointments.r1.status, 'requested');
  } finally {
    s.close();
  }
});

test('the patient\'s shared data stays closed until the request is accepted', async () => {
  const d = data();
  d.appointments.r1.shares = { healthSummary: true, foodLog7d: false, activity30d: false };
  d.appointments.r1.startAt = d.appointments.r1.slotKey = undefined;
  d.appointments.r1.startAt = NOW + 20 * MIN; // inside the prepare window
  d.appointments.r1.slotKey = String(NOW + 20 * MIN);
  const s = await start(d);
  try {
    const before = (await s.call('GET', '/api/appointments/r1', { as: 'doc1' })).body;
    assert.equal(before.sharedData, null);
    assert.match(before.sharedLocked, /Accept the request/);
    assert.equal(s.db.root.accessLog, undefined);
    await s.call('POST', '/api/appointments/r1/accept', { as: 'doc1' });
    const after = (await s.call('GET', '/api/appointments/r1', { as: 'doc1' })).body;
    assert.equal(after.sharedData.healthSummary.medicalConditions[0], 'Asthma');
  } finally {
    s.close();
  }
});

test('notes cannot be written for a request that was not accepted', async () => {
  const d = data();
  d.appointments.r1.startAt = d.appointments.r1.slotKey = undefined;
  d.appointments.r1.startAt = NOW - 5 * MIN;
  d.appointments.r1.slotKey = String(NOW - 5 * MIN);
  const s = await start(d);
  try {
    const r = await s.call('PUT', '/api/appointments/r1/consultation', { as: 'doc1', body: { notes: 'x' } });
    assert.equal(r.status, 400);
    assert.match(r.body.error, /Accept the request first/);
  } finally {
    s.close();
  }
});

test('the other status changes still need an accepted appointment', async () => {
  const s = await start(data());
  try {
    const r = await s.call('POST', '/api/appointments/r1/status', { as: 'doc1', body: { status: 'cancelled' } });
    assert.equal(r.status, 400);
    assert.match(r.body.error, /already requested/); // a request is answered with accept or decline, not cancel
  } finally {
    s.close();
  }
});
