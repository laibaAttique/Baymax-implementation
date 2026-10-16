// The whole system, end to end, on the LOCAL emulators: the real Express API (real token checks), the real database rules, the app's
// own writes (done with the client SDK, exactly as the phone does them), and the admin and specialist workflows.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { adminDb, auth, denied, makeUser, reset, signIn, waitForEmulators } from './harness.mjs';
import { createApp } from '../src/app.js';
import { connectFirebase } from '../src/firebase.js';

const run = promisify(execFile);
const DAY = 86_400_000;
const half = 1800_000;

let server;
let base;
const people = {}; // name -> { user, client }

const api = async (who, method, path, body) => {
  const token = await people[who].client.idToken();
  const res = await fetch(`${base}/api${path}`, { method, headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return { status: res.status, body: await res.json().catch(() => null) };
};
const anon = async (method, path, token) => (await fetch(`${base}/api${path}`, { method, headers: token ? { Authorization: `Bearer ${token}` } : {} })).status;

async function join(name, email) {
  const user = await makeUser(email);
  people[name] = { user, client: await signIn(user) };
  return user;
}

before(async () => {
  await waitForEmulators();
  await reset();
  const { auth: a, db } = connectFirebase({ databaseURL: 'https://demo-baymax-default-rtdb.firebaseio.com' });
  const app = createApp({ auth: a, db, origin: 'http://localhost:3000' });
  await new Promise((r) => { server = app.listen(0, r); });
  base = `http://127.0.0.1:${server.address().port}`;
  for (const [n, e] of [['admin', 'admin@example.com'], ['member', 'member@example.com'], ['member2', 'member2@example.com'], ['drnew', 'drnew@example.com'], ['nutadd', 'nutadd@example.com']]) await join(n, e);
});

after(() => server?.close());

test('ATC-INT-10 1. nobody is an administrator until the one-time command is run on the server', async () => {
  assert.equal((await api('admin', 'GET', '/admin/overview')).status, 403);
  const r = await run('node', ['scripts/make-admin.js', '--email', 'admin@example.com'], { cwd: new URL('..', import.meta.url).pathname, env: { ...process.env, FIREBASE_DATABASE_URL: 'https://demo-baymax-default-rtdb.firebaseio.com' } });
  assert.match(r.stdout, /now a Baymax administrator/);
  assert.equal((await api('admin', 'GET', '/admin/overview')).status, 200);
  assert.equal((await api('admin', 'GET', '/me')).body.role, 'admin');
  assert.equal(await anon('GET', '/admin/overview'), 401);
  assert.equal(await anon('GET', '/admin/overview', 'garbage'), 401);
});

test('ATC-INT-11 2. a doctor registers; they get nothing until the administrator approves', async () => {
  const reg = await api('drnew', 'POST', '/applications', { name: 'Dr Ayesha Noor', type: 'doctor', specialty: 'Cardiology', licenseNumber: 'PMDC-12345', yearsOfExperience: 9, fees: { video: 3000, chat: 1800 }, availability: { days: [1, 2, 3, 4, 5, 6, 7], start: '00:00', end: '23:30', slotMinutes: 30 } });
  assert.equal(reg.status, 201);
  const me = (await api('drnew', 'GET', '/me')).body;
  assert.equal(me.role, 'user');
  assert.equal(me.application.status, 'pending');
  assert.equal((await api('drnew', 'GET', '/dashboard')).status, 403);
  assert.equal((await adminDb.ref(`specialists/${people.drnew.user.uid}`).get()).exists(), false);
  // a member cannot see the registration, nor approve their own
  assert.equal((await api('member', 'GET', '/admin/applications')).status, 403);
  assert.equal((await api('drnew', 'POST', `/admin/applications/${people.drnew.user.uid}/approve`)).status, 403);
  // the administrator sees it with the licence number and approves
  const list = (await api('admin', 'GET', '/admin/applications')).body.applications;
  assert.equal(list.length, 1);
  assert.equal(list[0].licenseNumber, 'PMDC-12345');
  assert.equal((await api('admin', 'POST', `/admin/applications/${people.drnew.user.uid}/approve`)).status, 200);
  const after = (await api('drnew', 'GET', '/me')).body;
  assert.equal(after.role, 'doctor');
  assert.equal(after.profile.verified, true);
  assert.equal((await api('drnew', 'GET', '/dashboard')).status, 200);
});

test('ATC-INT-12 3. the administrator adds a nutritionist directly (no password is ever set by the administrator)', async () => {
  const r = await api('admin', 'POST', '/admin/specialists', { email: 'nutadd@example.com', name: 'Sara Khan', type: 'nutritionist', specialty: 'Sports nutrition', fees: { video: 2000, chat: 1200 }, availability: { days: [1, 2, 3, 4, 5, 6, 7], start: '00:00', end: '23:30', slotMinutes: 30 } });
  assert.equal(r.status, 200); // the account existed already in this test
  assert.match(r.body.resetLink, /oobCode=|reset|127\.0\.0\.1/);
  assert.equal((await api('nutadd', 'GET', '/me')).body.role, 'nutritionist');
  const specialists = (await api('admin', 'GET', '/admin/specialists')).body.specialists;
  assert.deepEqual(specialists.map((s) => s.type).sort(), ['doctor', 'nutritionist']);
});

let startAt;
let apptId;
const spec = () => people.drnew.user.uid;

test('ATC-INT-13 4. the member (the phone) sees the specialists, holds a time, pays, and it becomes a request', async () => {
  const m = people.member.client;
  const list = await m.get('specialists');
  assert.equal(Object.keys(list).length, 2);
  assert.equal(list[spec()].verified, true);
  startAt = Math.ceil((Date.now() + 2 * DAY) / half) * half;
  apptId = m.ref('appointments').key ?? 'e2e-appt-1';
  apptId = 'e2e-appt-1';
  const hold = Date.now() + 9 * 60_000;
  await m.update({
    [`appointments/${apptId}`]: { patientId: m.uid, patientName: 'Member One', specialistId: spec(), specialistName: 'Dr Ayesha Noor', role: 'doctor', specialty: 'Cardiology', startAt, slotKey: String(startAt), durationMinutes: 30, type: 'video', status: 'pending_payment', fee: 3000, notesForSpecialist: 'Chest tightness when running', shares: { healthSummary: true, foodLog7d: true, activity30d: false }, createdAt: Date.now(), holdUntil: hold },
    [`slots/${spec()}/${startAt}`]: { appt: apptId, holdUntil: hold },
    [`users/${m.uid}/appointmentIds/${apptId}`]: startAt,
  });
  // nobody else can take the time while it is held
  const m2 = people.member2.client;
  assert.ok(await denied(m2.update({
    'appointments/e2e-other': { patientId: m2.uid, patientName: 'Member Two', specialistId: spec(), specialistName: 'Dr', role: 'doctor', specialty: 'C', startAt, slotKey: String(startAt), durationMinutes: 30, type: 'video', status: 'pending_payment', fee: 3000, createdAt: Date.now(), holdUntil: hold },
    [`slots/${spec()}/${startAt}`]: { appt: 'e2e-other', holdUntil: hold },
  })));
  await m.update({
    [`appointments/${apptId}/payment`]: { transactionId: 'TXN-E2E-1', method: 'card', status: 'paid', consultationFee: 3000, platformFee: 0, total: 3000, brand: 'Visa', last4: '4242', reference: 'sbx_c_e2e', mode: 'sandbox', paidAt: Date.now() },
    [`appointments/${apptId}/status`]: 'requested',
    [`appointments/${apptId}/holdUntil`]: null,
    [`slots/${spec()}/${startAt}/holdUntil`]: null,
  });
  assert.equal((await m.get(`appointments/${apptId}`)).status, 'requested');
});

test('ATC-INT-14 5. the doctor sees the request, not the patient\'s data, and accepting creates the video room', async () => {
  const dash = (await api('drnew', 'GET', '/dashboard')).body;
  assert.equal(dash.requests.length, 1);
  assert.equal(dash.counts.pendingRequests, 1);
  assert.equal(dash.requests[0].patientName, 'Member One');
  assert.equal(dash.requests[0].meetingLink, '');
  const before = (await api('drnew', 'GET', `/appointments/${apptId}`)).body;
  assert.equal(before.sharedData, null); // nothing before accepting
  const accept = await api('drnew', 'POST', `/appointments/${apptId}/accept`);
  assert.equal(accept.status, 200);
  const mine = await people.member.client.get(`appointments/${apptId}`);
  assert.equal(mine.status, 'confirmed');
  assert.match(mine.meetingLink, /^https:\/\/meet\.jit\.si\/baymax-[a-z0-9]{20}$/);
  const inbox = Object.values((await people.member.client.get(`users/${people.member.user.uid}/inbox`)) ?? {});
  assert.ok(inbox.some((n) => /accepted/.test(n.title)), 'the member was told');
  assert.equal((await api('drnew', 'POST', `/appointments/${apptId}/accept`)).status, 400); // only once
});

test('ATC-INT-15 6. My patients: the doctor now has a patient, and a record to work in', async () => {
  const patients = (await api('drnew', 'GET', '/patients')).body.patients;
  assert.deepEqual(patients.map((p) => p.name), ['Member One']);
  const rec = (await api('drnew', 'GET', `/patients/${people.member.user.uid}`)).body;
  assert.equal(rec.access.canEditDiet, true);
  assert.equal(rec.access.canEditWorkout, true);
  assert.equal(rec.access.canReviewDiet, false); // the doctor is not a nutritionist
  assert.equal((await api('drnew', 'GET', `/patients/${people.member2.user.uid}`)).status, 404); // not their patient
});

test('ATC-INT-16 7. the doctor sets a diet and a workout plan; the member can read them but never write them', async () => {
  const pid = people.member.user.uid;
  const diet = await api('drnew', 'PUT', `/patients/${pid}/plans/diet`, { status: 'modified', targetKcal: 1900, proteinG: 120, carbsG: 210, fatG: 60, avoid: ['Fried foods'], tips: ['Drink water before meals'], note: 'Review in 4 weeks' });
  assert.equal(diet.status, 200);
  const day = (n, items) => ({ day: n, rest: !items, items: items ?? [] });
  const workout = await api('drnew', 'PUT', `/patients/${pid}/plans/workout`, { status: 'modified', note: 'Gentle start', schedule: [day(1, [{ exerciseId: 'brisk_walk', sets: 1, seconds: 900 }]), day(2), day(3, [{ exerciseId: 'chair_squat', sets: 3, reps: 10 }]), day(4), day(5, [{ exerciseId: 'brisk_walk', sets: 1, seconds: 900 }]), day(6), day(7)] });
  assert.equal(workout.status, 200);
  const m = people.member.client;
  const plans = await m.get(`specialistPlans/${pid}`);
  assert.equal(plans.diet.targetKcal, 1900);
  assert.equal(plans.diet.by.name, 'Dr Ayesha Noor');
  assert.equal(plans.workout.schedule[0].items[0].exerciseId, 'brisk_walk');
  assert.ok(await denied(m.set(`specialistPlans/${pid}/diet/targetKcal`, 5000)));
  assert.ok(await denied(people.member2.client.get(`specialistPlans/${pid}`)));
  const inbox = Object.values((await m.get(`users/${pid}/inbox`)) ?? {});
  assert.ok(inbox.some((n) => /diet plan was updated/.test(n.title)));
  assert.ok(inbox.some((n) => /workout plan was updated/.test(n.title)));
  // the member can choose to ignore them
  await m.set(`users/${pid}/planChoice/diet`, 'baymax');
  assert.equal((await api('drnew', 'GET', `/patients/${pid}`)).body.patientChoice.diet, 'baymax');
  // a nutritionist may not set a workout plan at all (role), whoever the patient is
  assert.equal((await api('nutadd', 'PUT', `/patients/${pid}/plans/workout`, { status: 'approved' })).status, 403);
  // and may not touch a diet plan for someone who is not their patient yet
  assert.equal((await api('nutadd', 'PUT', `/patients/${pid}/plans/diet`, { status: 'approved' })).status, 404);
});

test('ATC-INT-17 8. the nutritionist reviews a day of the food log (inside the sharing window); the member sees the verdict', async () => {
  const pid = people.member.user.uid;
  const sid = people.nutadd.user.uid;
  // a session that has just started with the nutritionist, food log shared (what the portal would see 10 minutes into a call)
  const start = Math.floor((Date.now() - 10 * 60_000) / 60_000) * 60_000; // started 10 minutes ago, so it is still in progress
  const today = new Date().toISOString().slice(0, 10);
  await adminDb.ref().update({
    'appointments/e2e-appt-nut': { patientId: pid, patientName: 'Member One', specialistId: sid, specialistName: 'Sara Khan', role: 'nutritionist', specialty: 'Sports nutrition', startAt: start, slotKey: String(start), durationMinutes: 30, type: 'video', status: 'confirmed', fee: 2000, meetingLink: 'https://meet.jit.si/baymax-aaaaaaaaaaaaaaaaaaaa', shares: { healthSummary: true, foodLog7d: true, activity30d: false }, createdAt: Date.now() - 3600_000 },
    [`slots/${sid}/${start}`]: { appt: 'e2e-appt-nut' },
    [`users/${pid}/profile`]: { fullName: 'Member One', height: { value: 170, unit: 'cm' }, weight: { value: 70, unit: 'kg' }, medicalConditions: ['Asthma'] },
    [`users/${pid}/foodLog/${today}/e1`]: { meal: 'Lunch', name: 'Biryani', kcal: 650, protein: 25, carbs: 80, fat: 22 },
  });
  const rec = (await api('nutadd', 'GET', `/patients/${pid}`)).body;
  assert.equal(rec.sharedData.healthSummary.medicalConditions[0], 'Asthma');
  assert.equal(rec.sharedData.foodLog7d[0].totalKcal, 650);
  assert.equal(rec.access.canReviewDiet, true);
  const review = await api('nutadd', 'PUT', `/patients/${pid}/diet-reviews/${today}`, { status: 'flagged', note: 'High calorie lunch' });
  assert.equal(review.status, 200);
  const seen = await people.member.client.get(`dietReviews/${pid}/${today}`);
  assert.equal(seen.status, 'flagged');
  assert.equal(seen.by.name, 'Sara Khan');
  assert.ok(await denied(people.member.client.set(`dietReviews/${pid}/${today}/status`, 'approved')));
  // the access to shared data was logged
  const log = Object.values((await adminDb.ref('accessLog/e2e-appt-nut').get()).val());
  assert.ok(log.length >= 1);
  assert.equal(log[0].specialistId, sid);
  // notes, once the session has started
  const notes = await api('nutadd', 'PUT', '/appointments/e2e-appt-nut/consultation', { notes: 'Lower fried foods' });
  assert.equal(notes.status, 200);
  assert.equal((await people.member.client.get('appointments/e2e-appt-nut')).consultation.notes, 'Lower fried foods');
});

test('ATC-INT-18 9. a specialist closes their account: future bookings are cancelled and freed, the patient is told, the sign-in is deleted', async () => {
  const sid = spec();
  const stale = await api('drnew', 'DELETE', '/me', { confirm: 'NOPE' });
  assert.equal(stale.status, 400);
  const del = await api('drnew', 'DELETE', '/me', { confirm: 'DELETE' });
  assert.equal(del.status, 200, JSON.stringify(del.body));
  assert.equal(del.body.accountDeleted, true);
  assert.ok(del.body.cancelled >= 1);
  assert.equal((await people.member.client.get(`appointments/${apptId}`)).status, 'cancelled');
  assert.equal((await adminDb.ref(`slots/${sid}`).get()).exists(), false);
  assert.equal((await adminDb.ref(`specialists/${sid}`).get()).exists(), false);
  assert.equal((await adminDb.ref(`roles/${sid}`).get()).exists(), false);
  await assert.rejects(auth.getUser(sid)); // the sign-in account is gone
  const inbox = Object.values((await people.member.client.get(`users/${people.member.user.uid}/inbox`)) ?? {});
  assert.ok(inbox.some((n) => /cancelled/.test(n.title)));
  // the patient's plans from that doctor remain, as part of the patient's own record
  assert.ok(await people.member.client.get(`specialistPlans/${people.member.user.uid}/workout`));
});

test('ATC-INT-19 10. the administrator can delete another specialist, but not an administrator or themselves', async () => {
  const sid = people.nutadd.user.uid;
  assert.equal((await api('admin', 'DELETE', `/admin/specialists/${people.admin.user.uid}`)).status, 409);
  const del = await api('admin', 'DELETE', `/admin/specialists/${sid}`);
  assert.equal(del.status, 200);
  await assert.rejects(auth.getUser(sid));
  assert.equal((await api('admin', 'GET', '/admin/overview')).body.specialists.total, 0);
  // a session still in progress is cancelled with the account, but what the specialist wrote stays in the patient's record
  const left = await people.member.client.get('appointments/e2e-appt-nut');
  assert.equal(left.status, 'cancelled');
  assert.equal(left.consultation.notes, 'Lower fried foods');
  assert.equal((await people.member.client.get(`dietReviews/${people.member.user.uid}`)) !== null, true);
});
