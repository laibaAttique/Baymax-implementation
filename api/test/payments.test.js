import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, start } from './helpers.js';
import { normalizeAppointment } from '../src/lib/rules.js';
import { paymentBucket, refundProblem, refundWrites, summarize } from '../src/lib/payments.js';

const DAY = 86_400_000;
const pay = (over = {}) => ({ status: 'paid', method: 'card', total: 2150, consultationFee: 2000, platformFee: 150, mode: 'sandbox', transactionId: 'TXN-1', paidAt: NOW - DAY, ...over });
const norm = (id, over) => normalizeAppointment(id, appointment(over));

const data = () =>
  baseData({
    roles: { doc1: 'doctor', nut1: 'nutritionist', pat1: 'user', adm1: 'admin', pat2: 'user' },
    appointments: {
      earned: appointment({ status: 'completed', startAt: NOW - 2 * DAY, patientName: 'Earned One', patientId: 'pat1', payment: pay() }),
      upcoming: appointment({ status: 'confirmed', startAt: NOW + 2 * 60 * MIN, patientName: 'Upcoming One', patientId: 'pat2', payment: pay({ total: 1150, consultationFee: 1000, platformFee: 150 }) }),
      held: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 5 * 60 * MIN, patientName: 'Held One', patientId: 'pat3', payment: pay() }),
      clinic: appointment({ status: 'confirmed', startAt: NOW + 3 * 60 * MIN, patientName: 'Clinic One', patientId: 'pat4', payment: { status: 'pay_at_clinic', method: 'clinic', total: 2000, consultationFee: 2000, platformFee: 0, mode: 'sandbox', transactionId: 'TXN-C' } }),
      cancelledByPatient: appointment({ status: 'cancelled', startAt: NOW + 4 * 60 * MIN, patientName: 'Cancelled One', patientId: 'pat5', payment: pay() }),
      unpaid: appointment({ status: 'confirmed', startAt: NOW + 6 * 60 * MIN, patientName: 'No Payment', patientId: 'pat6' }),
      other: appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', status: 'completed', startAt: NOW - DAY, patientName: 'Not Mine', patientId: 'pat7', payment: pay({ total: 9999, consultationFee: 9000, platformFee: 999 }) }),
    },
    slots: { doc1: { [NOW + 5 * 60 * MIN]: { appt: 'held' } } },
  });

test('every payment is in exactly one bucket', () => {
  const b = (over) => paymentBucket(norm('x', over), NOW);
  assert.equal(b({ status: 'completed', payment: pay() }), 'earned');
  assert.equal(b({ status: 'no_show', payment: pay() }), 'earned');
  assert.equal(b({ status: 'confirmed', startAt: NOW + 60 * MIN, payment: pay() }), 'upcoming');
  assert.equal(b({ status: 'confirmed', startAt: NOW - 3 * 60 * MIN, payment: pay() }), 'earned'); // the slot has ended
  assert.equal(b({ status: 'requested', startAt: NOW + 60 * MIN, payment: pay() }), 'held');
  assert.equal(b({ status: 'requested', startAt: NOW - MIN, payment: pay() }), 'due'); // expired, nobody answered
  assert.equal(b({ status: 'declined', payment: pay() }), 'due');
  assert.equal(b({ status: 'cancelled', payment: pay() }), 'due');
  assert.equal(b({ status: 'confirmed', payment: { ...pay(), status: 'pay_at_clinic', method: 'clinic' } }), 'clinic');
  assert.equal(b({ status: 'cancelled', payment: { ...pay(), status: 'pay_at_clinic', method: 'clinic' } }), 'void');
  assert.equal(b({ status: 'completed' }), 'unpaid');
  assert.equal(b({ status: 'cancelled', payment: pay(), refund: { status: 'refunded', amount: 2150, at: NOW } }), 'refunded');
});

test('totals split the specialist\'s share from the platform fee and leave refunds out of both', () => {
  const list = [
    norm('a', { status: 'completed', payment: pay() }),
    norm('b', { status: 'confirmed', startAt: NOW + 60 * MIN, payment: pay({ total: 1150, consultationFee: 1000, platformFee: 150 }) }),
    norm('c', { status: 'requested', startAt: NOW + 60 * MIN, payment: pay() }),
    norm('d', { status: 'declined', payment: pay(), refund: { status: 'refunded', amount: 2150, at: NOW } }),
    norm('e', { status: 'confirmed', startAt: NOW + 60 * MIN, payment: { ...pay({ total: 2000 }), status: 'pay_at_clinic', method: 'clinic' } }),
    norm('f', { status: 'cancelled', payment: pay() }),
  ];
  const s = summarize(list, NOW);
  assert.deepEqual(s.earned, { count: 1, amount: 2000 });
  assert.deepEqual(s.upcoming, { count: 1, amount: 1000 });
  assert.deepEqual(s.held, { count: 1, amount: 2000 });
  assert.deepEqual(s.refunded, { count: 1, amount: 2150 });
  assert.deepEqual(s.due, { count: 1, amount: 2150 });
  assert.deepEqual(s.clinicDue, { count: 1, amount: 2000 });
  assert.equal(s.platformFees, 450); // earned + upcoming + held; not the refunded or the due one
  assert.equal(s.gross, 2150 + 1150 + 2150);
});

test('only a paid, un-refunded payment can be refunded, and a live one is left for the gateway', () => {
  assert.equal(refundProblem(norm('a', { payment: pay() })), null);
  assert.match(refundProblem(norm('a', {})), /no payment/);
  assert.match(refundProblem(norm('a', { payment: { ...pay(), status: 'pay_at_clinic', method: 'clinic' } })), /Nothing was taken online/);
  assert.match(refundProblem(norm('a', { payment: pay(), refund: { status: 'refunded', amount: 1, at: 1 } })), /already refunded/);
  assert.equal(refundWrites(norm('a', { payment: pay() }), NOW, { reason: 'r', by: 'admin' })['appointments/a/refund'].status, 'refunded');
  assert.equal(refundWrites(norm('a', { payment: pay({ mode: 'live' }) }), NOW, { reason: 'r', by: 'admin' })['appointments/a/refund'].status, 'manual');
  assert.deepEqual(refundWrites(norm('a', {}), NOW, { reason: 'r', by: 'admin' }), {});
});

test('a specialist sees only their own payments, with totals', async () => {
  const s = await start(data());
  try {
    const r = await s.call('GET', '/api/payments', { as: 'doc1' });
    assert.equal(r.status, 200);
    const ids = r.body.payments.map((p) => p.appointmentId).sort();
    assert.deepEqual(ids, ['cancelledByPatient', 'clinic', 'earned', 'held', 'upcoming']); // not 'other', not 'unpaid'
    assert.equal(r.body.summary.earned.amount, 2000);
    assert.equal(r.body.summary.upcoming.amount, 1000);
    assert.equal(r.body.summary.due.count, 1);
    // never card details
    assert.equal(JSON.stringify(r.body).includes('4242'), false);
    assert.equal(r.body.payments.every((p) => !('last4' in (p.payment ?? {})) && !('brand' in (p.payment ?? {}))), true);
    const filtered = (await s.call('GET', '/api/payments?bucket=earned', { as: 'doc1' })).body;
    assert.deepEqual(filtered.payments.map((p) => p.appointmentId), ['earned']);
    assert.equal((await s.call('GET', '/api/payments?bucket=nonsense', { as: 'doc1' })).status, 400);
    assert.equal((await s.call('GET', `/api/payments?from=${NOW}&to=${NOW - 1}`, { as: 'doc1' })).status, 400);
    assert.equal((await s.call('GET', '/api/payments', { as: 'pat1' })).status, 403);
    assert.equal((await s.call('GET', '/api/payments')).status, 401);
  } finally {
    s.close();
  }
});

test('declining a paid request returns the money and tells the patient; a pay-at-clinic request has nothing to return', async () => {
  const d = data();
  d.appointments.heldClinic = appointment({ status: 'requested', meetingLink: '', startAt: NOW + 7 * 60 * MIN, patientId: 'pat8', payment: { status: 'pay_at_clinic', method: 'clinic', total: 2000, mode: 'sandbox', transactionId: 'TXN-C2' } });
  const s = await start(d);
  try {
    const r = await s.call('POST', '/api/appointments/held/decline', { as: 'doc1', body: { reason: 'Away that day' } });
    assert.equal(r.status, 200);
    const refund = s.db.root.appointments.held.refund;
    assert.deepEqual({ status: refund.status, amount: refund.amount, by: refund.by }, { status: 'refunded', amount: 2150, by: 'specialist' });
    assert.match(s.db.root.users.pat3.inbox['refund-held'].body, /2,150/);
    assert.match(s.db.root.users.pat3.inbox['decline-held'].body, /refunded/);
    await s.call('POST', '/api/appointments/heldClinic/decline', { as: 'doc1', body: {} });
    assert.equal(s.db.root.appointments.heldClinic.refund, undefined);
    assert.equal(s.db.root.users.pat8.inbox['refund-heldClinic'], undefined);
  } finally {
    s.close();
  }
});

test('cancelling a paid, accepted appointment returns the money', async () => {
  const s = await start(data());
  try {
    const r = await s.call('POST', '/api/appointments/upcoming/status', { as: 'doc1', body: { status: 'cancelled' } });
    assert.equal(r.status, 200);
    assert.equal(s.db.root.appointments.upcoming.refund.status, 'refunded');
    assert.equal(s.db.root.appointments.upcoming.refund.amount, 1150);
    assert.ok(s.db.root.users.pat2.inbox['refund-upcoming']);
  } finally {
    s.close();
  }
});

test('a paid request nobody answered before its start time is refunded once, whoever opens the list first', async () => {
  const d = data();
  d.appointments.lapsed = appointment({ status: 'requested', meetingLink: '', startAt: NOW - 30 * MIN, patientId: 'pat9', payment: pay() });
  const s = await start(d);
  try {
    await s.call('GET', '/api/payments', { as: 'doc1' });
    const first = s.db.root.appointments.lapsed.refund;
    assert.equal(first.by, 'system');
    assert.match(first.reason, /expired/);
    s.clock.now += 5 * MIN;
    await s.call('GET', '/api/payments', { as: 'doc1' });
    assert.equal(s.db.root.appointments.lapsed.refund.at, first.at); // not refunded a second time
  } finally {
    s.close();
  }
});

test('the administrator sees every payment and per-specialist totals; nobody else does', async () => {
  const s = await start(data());
  try {
    const r = await s.call('GET', '/api/admin/payments', { as: 'adm1' });
    assert.equal(r.status, 200);
    assert.equal(r.body.payments.length, 6); // includes the other specialist's
    assert.equal(r.body.bySpecialist.length, 2);
    assert.equal(r.body.summary.platformFees > 0, true);
    const mine = (await s.call('GET', '/api/admin/payments?specialist=nut1', { as: 'adm1' })).body;
    assert.deepEqual(mine.payments.map((p) => p.appointmentId), ['other']);
    assert.equal((await s.call('GET', '/api/admin/payments?q=earned', { as: 'adm1' })).body.payments.length, 1);
    for (const who of ['doc1', 'pat1']) assert.equal((await s.call('GET', '/api/admin/payments', { as: who })).status, 403, who);
  } finally {
    s.close();
  }
});

test('an administrator refund needs a reason, a paid payment and an appointment that is over', async () => {
  const s = await start(data());
  try {
    const url = (id) => `/api/admin/payments/${id}/refund`;
    assert.equal((await s.call('POST', url('earned'), { as: 'adm1', body: {} })).status, 400);
    assert.equal((await s.call('POST', url('earned'), { as: 'adm1', body: { reason: 'ab' } })).status, 400);
    assert.equal((await s.call('POST', url('earned'), { as: 'adm1', body: { reason: 'x'.repeat(201) } })).status, 400);
    assert.equal((await s.call('POST', url('upcoming'), { as: 'adm1', body: { reason: 'Patient asked' } })).status, 409); // still going ahead
    assert.equal((await s.call('POST', url('clinic'), { as: 'adm1', body: { reason: 'Patient asked' } })).status, 409); // nothing was taken online
    assert.equal((await s.call('POST', url('unpaid'), { as: 'adm1', body: { reason: 'Patient asked' } })).status, 409);
    assert.equal((await s.call('POST', url('missing'), { as: 'adm1', body: { reason: 'Patient asked' } })).status, 404);
    assert.equal((await s.call('POST', url('bad.id'), { as: 'adm1', body: { reason: 'Patient asked' } })).status, 400);
    assert.equal((await s.call('POST', url('earned'), { as: 'doc1', body: { reason: 'Patient asked' } })).status, 403);

    const ok = await s.call('POST', url('cancelledByPatient'), { as: 'adm1', body: { reason: 'Cancelled in time' } });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.payment.bucket, 'refunded');
    assert.equal(s.db.root.appointments.cancelledByPatient.refund.by, 'admin');
    assert.ok(s.db.root.users.pat5.inbox['refund-cancelledByPatient']);
    const log = Object.values(s.db.root.paymentLog.cancelledByPatient);
    assert.deepEqual({ event: log[0].event, by: log[0].by, amount: log[0].amount }, { event: 'refund', by: 'adm1', amount: 2150 });
    assert.equal((await s.call('POST', url('cancelledByPatient'), { as: 'adm1', body: { reason: 'Again please' } })).status, 409); // only once
  } finally {
    s.close();
  }
});

test('a live payment is marked for a manual refund, never silently returned', async () => {
  const d = data();
  d.appointments.live = appointment({ status: 'completed', startAt: NOW - 2 * DAY, patientId: 'pat9', payment: pay({ mode: 'live' }) });
  const s = await start(d);
  try {
    const r = await s.call('POST', '/api/admin/payments/live/refund', { as: 'adm1', body: { reason: 'Service not delivered' } });
    assert.equal(r.status, 200);
    assert.equal(s.db.root.appointments.live.refund.status, 'manual');
    assert.match(s.db.root.users.pat9.inbox['refund-live'].body, /support will contact/);
  } finally {
    s.close();
  }
});

test('the overview adds payment, call and message figures', async () => {
  const d = data();
  d.callLog = { earned: { e1: { event: 'joined', at: NOW - 2 * DAY + 5 * MIN }, e2: { event: 'left', at: NOW - 2 * DAY + 25 * MIN } } };
  d.chats = { earned: { m1: { side: 'patient', from: 'pat1', text: 'hi', at: NOW - DAY }, m2: { side: 'specialist', from: 'doc1', text: 'hello', at: NOW - DAY + 1 } } };
  const s = await start(d);
  try {
    const o = (await s.call('GET', '/api/admin/overview', { as: 'adm1' })).body;
    assert.equal(o.payments.count, 6);
    assert.equal(o.payments.testPayments > 0, true);
    assert.deepEqual(o.calls, { sessions: 1, minutes: 20 });
    assert.deepEqual(o.messages, { conversations: 1, total: 2 });
  } finally {
    s.close();
  }
});

test('closing a specialist account returns the money for appointments that will never happen', async () => {
  const s = await start(data());
  try {
    const r = await s.call('DELETE', '/api/admin/specialists/doc1', { as: 'adm1' });
    assert.equal(r.status, 200);
    assert.equal(s.db.root.appointments.upcoming.refund.by, 'system');
    assert.equal(s.db.root.appointments.held.refund.status, 'refunded');
    assert.equal(s.db.root.appointments.earned.refund, undefined); // a finished session is not refunded
    assert.equal(s.db.root.appointments.clinic.refund, undefined); // nothing was taken
  } finally {
    s.close();
  }
});
