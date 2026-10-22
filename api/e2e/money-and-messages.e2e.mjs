// Payments, refunds, the video-call log and client messages, end to end on the LOCAL emulators: the real Express API with real token
// checks, the real database rules, and the phone's own writes done with the client SDK exactly as the app does them.
import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { serverTimestamp } from 'firebase/database';
import { adminDb, makeUser, reset, signIn, waitForEmulators } from './harness.mjs';
import { createApp } from '../src/app.js';
import { connectFirebase } from '../src/firebase.js';

const MIN = 60_000;
let server;
let base;
let patient;
let doc;
let admin;
let START;
const who = {};

const api = async (name, method, path, body) => {
  const token = await who[name].client.idToken();
  const res = await fetch(`${base}/api${path}`, { method, headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};

const profile = () => ({
  name: 'Hina Malik', type: 'doctor', specialty: 'General', fees: { video: 2000, chat: 1000 },
  availability: { days: [1, 2, 3, 4, 5, 6, 7], start: '00:00', end: '23:30', slotMinutes: 30 }, tzOffsetMinutes: 300, available: true,
});

/** What the phone writes to book and pay (the app's own sequence). */
async function bookAndPay(id, start) {
  const hold = Date.now() + 9 * MIN;
  await who.patient.client.update({
    [`appointments/${id}`]: {
      patientId: patient.uid, patientName: 'Ayesha', specialistId: doc.uid, specialistName: 'Dr. Hina Malik', role: 'doctor', specialty: 'General',
      startAt: start, slotKey: String(start), durationMinutes: 30, type: 'video', status: 'pending_payment', fee: 2000,
      notesForSpecialist: 'hi', shares: { healthSummary: false, foodLog7d: false, activity30d: false }, createdAt: Date.now(), holdUntil: hold,
    },
    [`slots/${doc.uid}/${start}`]: { appt: id, holdUntil: hold },
    [`users/${patient.uid}/appointmentIds/${id}`]: start,
  });
  await who.patient.client.update({
    [`appointments/${id}/payment`]: { transactionId: `TXN-${id}-001`, method: 'card', status: 'paid', consultationFee: 2000, platformFee: 0, total: 2000, brand: 'Visa', last4: '4242', reference: 'sbx_c_abc', mode: 'sandbox', paidAt: Date.now() },
    [`appointments/${id}/status`]: 'requested',
    [`appointments/${id}/holdUntil`]: null,
    [`slots/${doc.uid}/${start}/holdUntil`]: null,
  });
}

before(async () => {
  await waitForEmulators();
  const { auth: a, db } = connectFirebase({ databaseURL: 'https://demo-baymax-default-rtdb.firebaseio.com' });
  const app = createApp({ auth: a, db, origin: 'http://localhost:3000' });
  await new Promise((r) => { server = app.listen(0, r); });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server?.close());

beforeEach(async () => {
  await reset();
  START = Math.ceil((Date.now() + 2 * 86_400_000) / 1_800_000) * 1_800_000;
  patient = await makeUser('patient@example.com');
  doc = await makeUser('doc@example.com');
  admin = await makeUser('admin@example.com');
  await adminDb.ref().update({ [`roles/${doc.uid}`]: 'doctor', [`roles/${admin.uid}`]: 'admin', [`specialists/${doc.uid}`]: profile() });
  for (const [name, user] of [['patient', patient], ['doc', doc], ['admin', admin]]) who[name] = { user, client: await signIn(user) };
});

test('ATC-INT-37 messages: the phone writes, the specialist reads and answers through the API, the phone reads the answer', async () => {
  await bookAndPay('appt-1', START);
  assert.equal((await api('doc', 'POST', '/appointments/appt-1/accept')).status, 200);
  const send = (text) => who.patient.client.set(`chats/appt-1/${Math.random().toString(36).slice(2)}`, { from: patient.uid, side: 'patient', text, at: serverTimestamp() });

  await send('Hello doctor, my back has hurt for two weeks.');
  const list = (await api('doc', 'GET', '/chats')).body;
  assert.equal(list.conversations[0].unread, 1);
  assert.equal((await api('doc', 'GET', '/summary')).body.unreadMessages, 1);

  const open = (await api('doc', 'GET', '/chats/appt-1')).body;
  assert.equal(open.messages.length, 1);
  assert.equal(open.messages[0].side, 'patient');
  assert.equal((await api('doc', 'GET', '/summary')).body.unreadMessages, 0);

  assert.equal((await api('doc', 'POST', '/chats/appt-1', { text: 'Please avoid lifting and book a follow-up.' })).status, 201);
  const phone = await who.patient.client.get('chats/appt-1');
  assert.deepEqual(Object.values(phone).map((m) => m.side).sort(), ['patient', 'specialist']);
  const inbox = await who.patient.client.get(`users/${patient.uid}/inbox/chat-appt-1`);
  assert.match(inbox.title, /Dr\. Hina Malik/);

  // the patient's phone marks the answer as read, and the specialist sees that
  await who.patient.client.set(`chatRead/appt-1/${patient.uid}`, serverTimestamp());
  assert.ok((await api('doc', 'GET', '/chats/appt-1')).body.patientReadAt > 0);
});

test('ATC-INT-38 messages: a stranger cannot read, write or answer a conversation that is not theirs', async () => {
  await bookAndPay('appt-1', START);
  await api('doc', 'POST', '/appointments/appt-1/accept');
  const stranger = await makeUser('stranger@example.com');
  who.stranger = { user: stranger, client: await signIn(stranger) };
  assert.equal((await api('stranger', 'GET', '/chats/appt-1')).status, 403); // not a specialist
  const other = await makeUser('doc2@example.com');
  await adminDb.ref().update({ [`roles/${other.uid}`]: 'doctor', [`specialists/${other.uid}`]: profile() });
  who.other = { user: other, client: await signIn(other) };
  assert.equal((await api('other', 'GET', '/chats/appt-1')).status, 404); // a specialist, but not this one
  assert.equal((await api('other', 'POST', '/chats/appt-1', { text: 'hello' })).status, 404);
  await assert.rejects(who.stranger.client.get('chats/appt-1'), /permission/i);
});

test('ATC-INT-39 payments: declining a paid request refunds it; the phone sees the refund; the administrator sees the totals', async () => {
  await bookAndPay('appt-1', START);
  await bookAndPay('appt-2', START + 1_800_000);
  const before = (await api('doc', 'GET', '/payments')).body;
  assert.equal(before.summary.held.amount, 4000);

  assert.equal((await api('doc', 'POST', '/appointments/appt-1/decline', { reason: 'Away that day' })).status, 200);
  const phone = await who.patient.client.get('appointments/appt-1');
  assert.equal(phone.status, 'declined');
  assert.equal(phone.refund.status, 'refunded');
  assert.equal(phone.refund.amount, 2000);
  assert.equal(phone.payment.status, 'paid'); // the payment record itself is never rewritten

  const mine = (await api('doc', 'GET', '/payments')).body;
  assert.equal(mine.summary.refunded.amount, 2000);
  assert.equal(mine.summary.held.amount, 2000);

  const all = (await api('admin', 'GET', '/admin/payments')).body;
  assert.equal(all.bySpecialist.length, 1);
  assert.equal(all.summary.refunded.count, 1);
  assert.equal((await api('doc', 'GET', '/admin/payments')).status, 403);
  assert.equal((await api('patient', 'GET', '/payments')).status, 403);
  const overview = (await api('admin', 'GET', '/admin/overview')).body;
  assert.equal(overview.payments.refunded.amount, 2000);
});

test('ATC-INT-40 video: the room opens only inside the join window, and joining and leaving reach the administrator\'s figures', async () => {
  const soon = Math.ceil((Date.now() + 2 * MIN) / 1000) * 1000;
  await adminDb.ref().update({
    'appointments/appt-live': {
      patientId: patient.uid, patientName: 'Ayesha', specialistId: doc.uid, specialistName: 'Dr. Hina Malik', role: 'doctor', specialty: 'General',
      startAt: soon, slotKey: String(soon), durationMinutes: 30, type: 'video', status: 'confirmed', fee: 2000, createdAt: Date.now(),
      meetingLink: 'https://meet.jit.si/baymax-abcdefghjkmnpqrstuvw', shares: { healthSummary: false, foodLog7d: false, activity30d: false },
    },
  });
  await bookAndPay('appt-later', START);
  await api('doc', 'POST', '/appointments/appt-later/accept');
  const later = (await api('doc', 'GET', '/appointments/appt-later/call')).body;
  assert.equal(later.canJoin, false);
  assert.equal('room' in later, false);

  const open = (await api('doc', 'GET', '/appointments/appt-live/call')).body;
  assert.equal(open.canJoin, true);
  assert.equal(open.room.domain, 'meet.jit.si');
  assert.equal((await api('doc', 'POST', '/appointments/appt-live/call/event', { event: 'joined' })).status, 201);
  assert.equal((await api('doc', 'POST', '/appointments/appt-live/call/event', { event: 'left' })).status, 201);
  assert.equal((await api('admin', 'GET', '/admin/overview')).body.calls.sessions, 1);
  await assert.rejects(who.patient.client.get('callLog/appt-live'), /permission/i);
});
