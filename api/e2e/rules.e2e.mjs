// The real database rules (app/database.rules.json), tested with real signed-in users against the emulator.
import test, { before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { serverTimestamp } from 'firebase/database';
import { adminDb, denied, makeUser, reset, signIn, waitForEmulators } from './harness.mjs';

const DAY = 86_400_000;
const slotStart = () => Math.ceil((Date.now() + 2 * DAY) / 1800_000) * 1800_000; // a half-hour mark, two days ahead
let A, B, DOC, ADMIN; // accounts
let a, b; // signed-in clients (members A and B)
let START;

const profile = (type = 'doctor') => ({
  name: 'Hina Malik', type, specialty: 'General', fees: { video: 2000, chat: 1000 },
  availability: { days: [1, 2, 3, 4, 5, 6, 7], start: '00:00', end: '23:30', slotMinutes: 30 }, tzOffsetMinutes: 300, available: true,
});

const holdWrites = (c, id, { start = START, type = 'video', fee = 2000, spec = DOC.uid, hold = Date.now() + 9 * 60_000 } = {}) => ({
  [`appointments/${id}`]: {
    patientId: c.uid, patientName: 'Ayesha', specialistId: spec, specialistName: 'Dr. Hina Malik', role: 'doctor', specialty: 'General',
    startAt: start, slotKey: String(start), durationMinutes: 30, type, status: 'pending_payment', fee,
    notesForSpecialist: 'hi', shares: { healthSummary: true, foodLog7d: false, activity30d: false }, createdAt: Date.now(), holdUntil: hold,
  },
  [`slots/${spec}/${start}`]: { appt: id, holdUntil: hold },
  [`users/${c.uid}/appointmentIds/${id}`]: start,
});

const payWrites = (id, spec = DOC.uid, start = START, { total = 2000, platform = 0, fee = 2000 } = {}) => ({
  [`appointments/${id}/payment`]: {
    transactionId: 'TXN-E2E-0001', method: 'card', status: 'paid', consultationFee: fee, platformFee: platform, total,
    brand: 'Visa', last4: '4242', reference: 'sbx_c_abc', mode: 'sandbox', paidAt: Date.now(),
  },
  [`appointments/${id}/status`]: 'requested',
  [`appointments/${id}/holdUntil`]: null,
  [`slots/${spec}/${start}/holdUntil`]: null,
});

before(async () => {
  await waitForEmulators();
});

beforeEach(async () => {
  await reset();
  START = slotStart();
  A = await makeUser('a@example.com');
  B = await makeUser('b@example.com');
  DOC = await makeUser('doc@example.com');
  ADMIN = await makeUser('admin@example.com');
  await adminDb.ref().update({
    [`roles/${DOC.uid}`]: 'doctor',
    [`roles/${ADMIN.uid}`]: 'admin',
    [`specialists/${DOC.uid}`]: profile(),
  });
  a = await signIn(A);
  b = await signIn(B);
});

test('ATC-INT-20 nothing is readable without signing in, and members cannot read or write the protected nodes', async () => {
  const anon = await fetch('http://127.0.0.1:9000/specialists.json?ns=demo-baymax-default-rtdb');
  assert.equal(anon.status, 401);
  assert.ok(await a.get(`specialists/${DOC.uid}`)); // a signed-in member can read the specialist list
  for (const path of ['applications', 'accessLog', 'roles']) assert.ok(await denied(a.get(path)), `read ${path}`);
  assert.ok(await denied(a.set(`roles/${A.uid}`, 'admin')), 'promote self');
  assert.ok(await denied(a.set(`specialists/${A.uid}`, profile())), 'list self as specialist');
  assert.ok(await denied(a.set(`specialists/${DOC.uid}/fees/video`, 1)), 'change a specialist fee');
  assert.ok(await denied(a.set('config/payments/platformFee', 0)), 'change the platform fee');
  assert.ok(await denied(a.set(`applications/${A.uid}`, { status: 'approved' })), 'approve self');
});

test('ATC-INT-21 a member can hold a free time, and nobody else can take it while it is held', async () => {
  await a.update(holdWrites(a, 'appt-a'));
  assert.equal((await a.get('appointments/appt-a')).status, 'pending_payment');
  assert.ok(await a.get(`slots/${DOC.uid}/${START}`));
  assert.ok(await denied(b.update(holdWrites(b, 'appt-b'))), 'the same slot a second time');
  assert.equal((await adminDb.ref('appointments/appt-b').get()).exists(), false); // nothing was written
  // another time is fine
  await b.update(holdWrites(b, 'appt-b2', { start: START + 1800_000 }));
});

test('ATC-INT-22 a hold must look right: own patient id, real fee, a hold of at most ten minutes, a real specialist, a future time', async () => {
  assert.ok(await denied(a.update(holdWrites(a, 'x1', { fee: 1 }))), 'a cheaper fee than the specialist charges');
  assert.ok(await denied(a.update(holdWrites(a, 'x2', { type: 'chat' }))), 'the video fee on a chat booking');
  assert.ok(await denied(a.update(holdWrites(a, 'x3', { hold: Date.now() + 60 * 60_000 }))), 'a one hour hold');
  assert.ok(await denied(a.update(holdWrites(a, 'x4', { spec: 'nobody' }))), 'a specialist that does not exist');
  assert.ok(await denied(a.update(holdWrites(a, 'x5', { start: Date.now() - 3600_000 }))), 'a time in the past');
  const forB = holdWrites(a, 'x6');
  forB['appointments/x6'].patientId = B.uid;
  assert.ok(await denied(a.update(forB)), 'booking in someone else\'s name');
  const withLink = holdWrites(a, 'x7');
  withLink['appointments/x7'].meetingLink = 'https://meet.jit.si/mine';
  assert.ok(await denied(a.update(withLink)), 'a phone writing its own video link');
  const confirmed = holdWrites(a, 'x8');
  confirmed['appointments/x8'].status = 'confirmed';
  assert.ok(await denied(a.update(confirmed)), 'creating an already confirmed booking');
});

test('ATC-INT-23 paying turns the hold into a request; the amounts must add up; a member cannot confirm or add a link', async () => {
  await a.update(holdWrites(a, 'appt-a'));
  assert.ok(await denied(a.update(payWrites('appt-a', DOC.uid, START, { total: 1 }))), 'a total that does not add up');
  assert.ok(await denied(a.update(payWrites('appt-a', DOC.uid, START, { fee: 5, total: 5 }))), 'a fee below the specialist\'s');
  assert.ok(await denied(a.update(payWrites('appt-a', DOC.uid, START, { platform: 99, total: 2099 }))), 'a platform fee that is not the configured one');
  assert.ok(await denied(a.set('appointments/appt-a/status', 'confirmed')), 'confirming without paying');
  assert.ok(await denied(a.set('appointments/appt-a/meetingLink', 'https://meet.jit.si/x')), 'writing a video link');
  await a.update(payWrites('appt-a'));
  const done = await a.get('appointments/appt-a');
  assert.equal(done.status, 'requested');
  assert.equal(done.holdUntil, undefined);
  assert.equal(done.payment.total, 2000);
  assert.equal((await a.get(`slots/${DOC.uid}/${START}`)).holdUntil, undefined); // locked for good, no expiry
  assert.ok(await denied(b.update(holdWrites(b, 'appt-b'))), 'the time stays taken after payment');
});

test('ATC-INT-24 a platform fee set by an administrator must be matched exactly', async () => {
  await adminDb.ref('config/payments/platformFee').set(150);
  await a.update(holdWrites(a, 'appt-a'));
  assert.ok(await denied(a.update(payWrites('appt-a'))), 'zero platform fee when 150 is set');
  await a.update(payWrites('appt-a', DOC.uid, START, { platform: 150, total: 2150 }));
  assert.equal((await a.get('appointments/appt-a')).status, 'requested');
});

test('ATC-INT-25 only the two people involved can read an appointment, and a member cannot touch the specialist\'s notes or anyone else\'s booking', async () => {
  await a.update(holdWrites(a, 'appt-a'));
  assert.ok(await a.get('appointments/appt-a'));
  assert.ok(await denied(b.get('appointments/appt-a')), 'another member reading it');
  assert.ok(await denied(b.set('appointments/appt-a/status', 'cancelled')), 'another member cancelling it');
  assert.ok(await denied(a.set('appointments/appt-a/consultation', { notes: 'I am fine' })), 'a member writing the specialist\'s notes');
  assert.ok(await denied(a.get('appointments')), 'listing every appointment');
  const doc = await signIn(DOC);
  assert.ok(await doc.get('appointments/appt-a'), 'the specialist reading their own appointment');
  assert.ok(await denied(doc.set('appointments/appt-a/status', 'confirmed')), 'a specialist writing from a phone: they use the portal server');
});

test('ATC-INT-26 cancelling a held or requested booking frees the time; an expired hold can be taken over', async () => {
  await a.update(holdWrites(a, 'appt-a'));
  await a.update({ 'appointments/appt-a/status': 'cancelled', [`slots/${DOC.uid}/${START}`]: null });
  assert.equal(await a.get(`slots/${DOC.uid}/${START}`), null);
  await b.update(holdWrites(b, 'appt-b')); // free again

  // an expired hold (someone left the payment screen with the app killed) can be taken over
  await adminDb.ref('slots/' + DOC.uid + '/' + (START + 1800_000)).set({ appt: 'ghost', holdUntil: Date.now() - 1000 });
  await b.update(holdWrites(b, 'appt-b2', { start: START + 1800_000 }));
  assert.equal((await b.get(`slots/${DOC.uid}/${START + 1800_000}`)).appt, 'appt-b2');
  // a live hold cannot
  await adminDb.ref('slots/' + DOC.uid + '/' + (START + 3600_000)).set({ appt: 'ghost2', holdUntil: Date.now() + 5 * 60_000 });
  assert.ok(await denied(a.update(holdWrites(a, 'appt-a2', { start: START + 3600_000 }))));

  // paid requests can be cancelled by their owner, and only by them
  await b.update(payWrites('appt-b'));
  assert.ok(await denied(a.update({ 'appointments/appt-b/status': 'cancelled' })));
  await b.update({ 'appointments/appt-b/status': 'cancelled', [`slots/${DOC.uid}/${START}`]: null });
  assert.equal((await b.get('appointments/appt-b')).status, 'cancelled');
});

test('ATC-INT-27 once the specialist accepts (portal server), the member keeps reading it but cannot cancel after the start or rewrite it', async () => {
  await a.update(holdWrites(a, 'appt-a'));
  await a.update(payWrites('appt-a'));
  await adminDb.ref('appointments/appt-a').update({ status: 'confirmed', meetingLink: 'https://meet.jit.si/baymax-abc' }); // what the portal does
  const mine = await a.get('appointments/appt-a');
  assert.equal(mine.status, 'confirmed');
  assert.equal(mine.meetingLink, 'https://meet.jit.si/baymax-abc');
  assert.ok(await denied(a.set('appointments/appt-a/meetingLink', 'https://evil.example/x')), 'replacing the link');
  assert.ok(await denied(a.set('appointments/appt-a', { ...mine, fee: 1 })), 'rewriting the appointment');
  await adminDb.ref('appointments/appt-a').update({ startAt: Date.now() - 1000, slotKey: String(Date.now() - 1000) });
  assert.ok(await denied(a.set('appointments/appt-a/status', 'cancelled')), 'cancelling after the start');
});

test('ATC-INT-28 a member can keep and delete their own saved card tokens, and nothing else about cards', async () => {
  await a.set('users/' + A.uid + '/savedCards/c1', { token: 'sbx_tok_abcdef12', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030 });
  assert.ok(await a.get('users/' + A.uid + '/savedCards/c1'));
  assert.ok(await denied(a.set('users/' + A.uid + '/savedCards/c2', { token: 'sbx_tok_abcdef12', brand: 'Visa', last4: '4242', expMonth: 12, expYear: 2030, number: '4242424242424242' })), 'a full card number');
  assert.ok(await denied(a.set('users/' + A.uid + '/savedCards/c3', { token: 'sbx_tok_abcdef12', brand: 'Amex', last4: '4242', expMonth: 12, expYear: 2030 })), 'an unsupported brand');
  assert.ok(await denied(b.get('users/' + A.uid + '/savedCards')), 'another member reading the cards');
  await a.remove('users/' + A.uid + '/savedCards/c1');
});

test('ATC-INT-29 a specialist changing their fee or slot length after a booking does not lock the member out of paying or cancelling', async () => {
  await a.update(holdWrites(a, 'appt-a'));
  await adminDb.ref(`specialists/${DOC.uid}`).update({ fees: { video: 3500, chat: 2000 }, availability: { days: [1, 2, 3, 4, 5, 6, 7], start: '00:00', end: '23:30', slotMinutes: 45 } });
  await a.update(payWrites('appt-a')); // the booking keeps the fee it was made at
  assert.equal((await a.get('appointments/appt-a')).status, 'requested');
  await a.update({ 'appointments/appt-a/status': 'cancelled', [`slots/${DOC.uid}/${START}`]: null });
  assert.equal((await a.get('appointments/appt-a')).status, 'cancelled');
});

test('ATC-INT-30 specialist plans and food log reviews: a member reads only their own and can never write them; the plan choice is theirs', async () => {
  await adminDb.ref().update({
    [`specialistPlans/${A.uid}/diet`]: { status: 'modified', targetKcal: 1800, by: { uid: DOC.uid, name: 'Hina', role: 'doctor' }, at: Date.now() },
    [`dietReviews/${A.uid}/2026-10-18`]: { status: 'flagged', note: 'x', by: { uid: DOC.uid, name: 'Hina' }, at: Date.now() },
    [`specialistPlans/${B.uid}/diet`]: { status: 'approved', by: { uid: DOC.uid, name: 'Hina', role: 'doctor' }, at: Date.now() },
  });
  assert.equal((await a.get(`specialistPlans/${A.uid}/diet`)).targetKcal, 1800);
  assert.equal((await a.get(`dietReviews/${A.uid}/2026-10-18`)).status, 'flagged');
  assert.ok(await denied(a.get(`specialistPlans/${B.uid}/diet`)), 'another member\'s plan');
  assert.ok(await denied(a.get(`dietReviews/${B.uid}`)), 'another member\'s reviews');
  assert.ok(await denied(a.set(`specialistPlans/${A.uid}/diet/targetKcal`, 5000)), 'a member editing the plan their specialist set');
  assert.ok(await denied(a.set(`specialistPlans/${A.uid}/workout`, { status: 'approved' })), 'a member inventing a workout plan');
  assert.ok(await denied(a.set(`dietReviews/${A.uid}/2026-10-18/status`, 'approved')), 'a member approving their own food log');
  assert.ok(await denied(a.remove(`specialistPlans/${A.uid}`)), 'a member deleting it (they switch back with the choice instead)');
  // the member's own choice
  await a.set(`users/${A.uid}/planChoice/diet`, 'baymax');
  assert.equal(await a.get(`users/${A.uid}/planChoice/diet`), 'baymax');
  assert.ok(await denied(a.set(`users/${A.uid}/planChoice/diet`, 'whatever')), 'an unknown choice');
  assert.ok(await denied(a.set(`users/${A.uid}/planChoice/sleep`, 'baymax')), 'an unknown plan kind');
  assert.ok(await denied(b.set(`users/${A.uid}/planChoice/diet`, 'specialist')), 'someone else\'s choice');
});

/** An accepted appointment between member [c] and the doctor, as the portal server leaves it. */
async function acceptedAppointment(c, id, { status = 'confirmed', start = START } = {}) {
  await c.update(holdWrites(c, id, { start }));
  await c.update(payWrites(id, DOC.uid, start));
  await adminDb.ref(`appointments/${id}`).update({ status, meetingLink: 'https://meet.jit.si/baymax-abcdefghjkmnpqrstuvw' });
}


test('ATC-INT-34 chat: a member writes only their own messages, to their own accepted appointment, one at a time', async () => {
  await acceptedAppointment(a, 'appt-a');
  const mk = (c, text) => ({ from: c.uid, side: 'patient', text, at: serverTimestamp() });
  await a.set('chats/appt-a/m1', mk(a, 'My back hurts'));
  assert.equal((await a.get('chats/appt-a/m1')).text, 'My back hurts');
  assert.equal((await a.get('chats/appt-a/m1')).side, 'patient');

  assert.ok(await denied(a.set('chats/appt-a/m1', mk(a, 'rewritten'))), 'rewriting a sent message');
  assert.ok(await denied(a.remove('chats/appt-a/m1')), 'deleting a sent message');
  assert.ok(await denied(a.set('chats/appt-a/m2', { ...mk(a, 'x'), side: 'specialist' })), 'posing as the specialist');
  assert.ok(await denied(a.set('chats/appt-a/m3', { ...mk(a, 'x'), from: B.uid })), 'posing as another member');
  assert.ok(await denied(a.set('chats/appt-a/m4', mk(a, ''))), 'an empty message');
  assert.ok(await denied(a.set('chats/appt-a/m5', mk(a, 'x'.repeat(1001)))), 'a message over 1000 characters');
  assert.ok(await denied(a.set('chats/appt-a/m6', { ...mk(a, 'x'), at: Date.now() - 86_400_000 })), 'a back-dated message');
  assert.ok(await denied(a.set('chats/appt-a/m7', { ...mk(a, 'x'), extra: 'field' })), 'an unknown field');
  assert.ok(await denied(a.set('chats/appt-a/m8', 'just text')), 'a message that is not an object');
  assert.ok(await denied(b.set('chats/appt-a/m9', mk(b, 'hi'))), 'another member writing into this conversation');
  assert.ok(await denied(b.set('chats/appt-b/m1', mk(b, 'hi'))), 'a conversation for an appointment that does not exist');
  assert.equal(Object.keys((await adminDb.ref('chats/appt-a').get()).val()).length, 1);
});

test('ATC-INT-35 chat: only the two people in the appointment can read it, and only an accepted one can be written to', async () => {
  await acceptedAppointment(a, 'appt-a');
  await a.update(holdWrites(a, 'appt-held', { start: START + 1800_000 }));
  const mk = (c, text) => ({ from: c.uid, side: 'patient', text, at: serverTimestamp() });
  await a.set('chats/appt-a/m1', mk(a, 'hello'));
  const doc = await signIn(DOC);
  assert.equal((await doc.get('chats/appt-a/m1')).text, 'hello', 'the specialist reads it');
  assert.ok(await denied(b.get('chats/appt-a')), 'another member reading it');
  assert.ok(await denied(a.get('chats')), 'listing every conversation');
  assert.ok(await denied(doc.set('chats/appt-a/m2', { from: DOC.uid, side: 'specialist', text: 'hi', at: serverTimestamp() })), 'a specialist writing from a phone: they use the portal server');
  assert.ok(await denied(a.set('chats/appt-held/m1', mk(a, 'too early'))), 'a booking that is only held');

  // a request that is paid but not yet accepted has no conversation
  await a.update(holdWrites(a, 'appt-req', { start: START + 3600_000 }));
  await a.update(payWrites('appt-req', DOC.uid, START + 3600_000));
  assert.ok(await denied(a.set('chats/appt-req/m1', mk(a, 'before acceptance'))), 'a request nobody accepted');

  // a conversation closes 24 hours after the slot
  await adminDb.ref('appointments/appt-a').update({ startAt: Date.now() - 3 * 86_400_000, slotKey: String(Date.now() - 3 * 86_400_000) });
  assert.ok(await denied(a.set('chats/appt-a/m3', mk(a, 'too late'))), 'a message after the conversation closed');
  assert.equal((await a.get('chats/appt-a/m1')).text, 'hello', 'the history can still be read');
});

test('ATC-INT-36 chat: a member marks their own messages read, nobody marks them for someone else, and the server\'s callLog and paymentLog stay closed', async () => {
  await acceptedAppointment(a, 'appt-a');
  await a.set(`chatRead/appt-a/${A.uid}`, serverTimestamp());
  assert.ok(await a.get(`chatRead/appt-a/${A.uid}`));
  assert.ok(await denied(a.set(`chatRead/appt-a/${DOC.uid}`, Date.now())), 'marking read as the specialist');
  assert.ok(await denied(a.set(`chatRead/appt-a/${A.uid}`, Date.now() + 3_600_000)), 'a read time in the future');
  assert.ok(await denied(b.set(`chatRead/appt-a/${B.uid}`, Date.now())), 'another member');
  assert.ok(await denied(b.get('chatRead/appt-a')), 'another member reading the read marks');
  await adminDb.ref().update({ 'callLog/appt-a/e1': { uid: DOC.uid, role: 'doctor', event: 'joined', at: Date.now() }, 'paymentLog/appt-a/p1': { event: 'refund', by: 'x', at: Date.now() } });
  for (const path of ['callLog', 'callLog/appt-a', 'paymentLog/appt-a']) assert.ok(await denied(a.get(path)), `read ${path}`);
  assert.ok(await denied(a.set('callLog/appt-a/e2', { event: 'left' })), 'writing to the call log');
  assert.ok(await denied(a.set('appointments/appt-a/refund', { status: 'refunded', amount: 2000, at: Date.now(), by: 'system', reason: 'x' })), 'a member refunding themselves');
});
