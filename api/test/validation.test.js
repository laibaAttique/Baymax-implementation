import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, start } from './helpers.js';
import { bodyText, queryChoice, queryInt, queryRange, queryText } from '../src/lib/validate.js';
import { makeLimiter } from '../src/lib/limiter.js';
import { activeClientIds, roleCards } from '../src/lib/roleCards.js';
import { normalizeAppointment } from '../src/lib/rules.js';

const DAY = 86_400_000;
const data = () => baseData({ appointments: { a1: appointment({ startAt: NOW + 60 * MIN }) } });

test('query values are checked, not guessed', () => {
  assert.equal(queryInt(undefined, 'x'), undefined);
  assert.equal(queryInt('', 'x'), undefined);
  assert.equal(queryInt('42', 'x'), 42);
  for (const bad of ['4.5', 'abc', '1e3x', ['1', '2'], '-1']) assert.throws(() => queryInt(bad, 'x', { min: 0 }), (e) => e.status === 400, String(bad));
  assert.equal(queryText(undefined, 'q'), '');
  assert.throws(() => queryText(['a', 'b'], 'q'), (e) => e.status === 400);
  assert.throws(() => queryText('x'.repeat(81), 'q'), (e) => e.status === 400);
  assert.equal(queryChoice('paid', 'x', ['paid']), 'paid');
  assert.throws(() => queryChoice('paid2', 'x', ['paid']), (e) => e.status === 400);
  assert.throws(() => queryRange({ from: '10', to: '5' }), (e) => e.status === 400);
  assert.deepEqual(queryRange({ from: '5', to: '10' }), { from: 5, to: 10 });
});

test('body text is trimmed, bounded and free of control characters', () => {
  assert.equal(bodyText('  ok  ', 'x'), 'ok');
  assert.throws(() => bodyText('', 'x'), (e) => /cannot be empty/.test(e.message));
  assert.throws(() => bodyText('ab', 'x', { min: 3 }), (e) => /at least 3/.test(e.message));
  assert.throws(() => bodyText('a\nb', 'x', { multiline: false }), (e) => e.status === 400);
  assert.equal(bodyText('a\nb', 'x'), 'a\nb');
});

test('the limiter counts per key and forgets after the window', () => {
  let t = 0;
  const l = makeLimiter({ limit: 2, windowMs: 1000, now: () => t });
  l.hit('a');
  l.hit('a');
  assert.throws(() => l.hit('a'), (e) => e.status === 429);
  l.hit('b'); // another person is not affected
  t = 1001;
  l.hit('a');
});

test('addresses with odd characters are refused before the database is touched', async () => {
  const s = await start(data());
  try {
    for (const path of ['/api/appointments/a.b', '/api/appointments/a$b', '/api/appointments/' + 'x'.repeat(65), '/api/appointments/a%20b', '/api/chats/a.b', '/api/patients/a.b']) {
      const r = await s.call('GET', path, { as: 'doc1' });
      assert.equal(r.status, 400, path);
    }
    assert.equal((await s.call('POST', '/api/appointments/a.b/accept', { as: 'doc1' })).status, 400);
    assert.equal((await s.call('PUT', '/api/patients/pat1/diet-reviews/not-a-date', { as: 'doc1', body: { status: 'approved' } })).status, 400);
    assert.equal((await s.call('POST', '/api/admin/applications/a.b/approve', { as: 'adm1' })).status, 400);
    assert.equal((await s.call('DELETE', '/api/admin/specialists/a$b', { as: 'adm1' })).status, 400);
  } finally {
    s.close();
  }
});

test('filters on the appointment and patient lists must make sense', async () => {
  const s = await start(data());
  try {
    for (const q of ['status=weird', 'from=abc', 'to=1.5', `from=${NOW}&to=${NOW - 1}`, 'q=' + 'x'.repeat(81), 'q=a&q=b']) {
      assert.equal((await s.call('GET', `/api/appointments?${q}`, { as: 'doc1' })).status, 400, q);
    }
    assert.equal((await s.call('GET', '/api/patients?q=' + 'x'.repeat(81), { as: 'doc1' })).status, 400);
    assert.equal((await s.call('GET', '/api/appointments?status=confirmed&q=ayesha', { as: 'doc1' })).status, 200);
  } finally {
    s.close();
  }
});

test('a body must be a JSON object sent as JSON', async () => {
  const s = await start(data());
  try {
    const raw = (body, type = 'application/json') => fetch(`${s.base}/api/appointments/a1/decline`, { method: 'POST', headers: { Authorization: 'Bearer token-doc1', 'Content-Type': type }, body });
    assert.equal((await raw('[1,2]')).status, 400);
    assert.equal((await raw('"text"')).status, 400);
    assert.equal((await raw('null')).status, 400);
    assert.equal((await raw('{not json')).status, 400);
    assert.equal((await raw('reason=x', 'text/plain')).status, 415);
    assert.equal((await raw('x'.repeat(25_000))).status, 413);
  } finally {
    s.close();
  }
});

test('one person cannot make more than 120 writes a minute', async () => {
  const s = await start(baseData({ appointments: { a1: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 60 * MIN }) } }));
  try {
    let last;
    for (let i = 0; i < 121; i++) last = await s.call('POST', '/api/appointments/a1/decline', { as: 'doc1', body: {} });
    assert.equal(last.status, 429);
    assert.equal((await s.call('GET', '/api/appointments', { as: 'doc1' })).status, 200); // reading is not limited by this
    assert.equal((await s.call('POST', '/api/appointments/a1/decline', { as: 'nut1', body: {} })).status !== 429, true); // another person is not affected
  } finally {
    s.close();
  }
});

test('each role gets its own four overview cards, with only numbers the data can give', () => {
  const norm = (over) => normalizeAppointment(over.id ?? 'x', appointment(over));
  const all = [
    norm({ id: 'p1', status: 'completed', startAt: NOW - 2 * DAY, patientId: 'a' }),
    norm({ id: 'p2', status: 'completed', startAt: NOW - 3 * DAY, patientId: 'b', consultation: { notes: 'n', prescription: 'rx', updatedAt: 1 } }),
    norm({ id: 'p3', status: 'completed', startAt: NOW - 90 * DAY, patientId: 'c' }), // too old to count
    norm({ id: 'p4', status: 'confirmed', startAt: NOW + 2 * DAY, patientId: 'a', type: 'video' }),
    norm({ id: 'p5', status: 'confirmed', startAt: NOW + 10 * DAY, patientId: 'd', type: 'video' }), // beyond 7 days
    norm({ id: 'p6', status: 'requested', startAt: NOW + 2 * DAY, patientId: 'e', meetingLink: '' }),
  ];
  const counts = { patients: 3, consultationsToday: 0 };
  assert.deepEqual(activeClientIds(all, NOW).sort(), ['a', 'b', 'd']);
  const doctor = roleCards('doctor', { all, now: NOW, counts, extra: { unreadMessages: 4 } });
  assert.deepEqual(doctor.map((c) => c.key), ['patients', 'today', 'prescriptions', 'messages']);
  assert.equal(doctor.find((c) => c.key === 'prescriptions').value, 1); // p1 has none; p2 has one; p3 is too old
  assert.equal(doctor.find((c) => c.key === 'messages').warn, true);
  const nutri = roleCards('nutritionist', { all, now: NOW, counts, extra: { dietReviewsWaiting: 2 } });
  assert.deepEqual(nutri.map((c) => [c.key, c.value]), [['dietReviews', 2], ['video', 1], ['clients', 3], ['messages', 0]]);
  const trainer = roleCards('trainer', { all, now: NOW, counts, extra: { workoutsToReview: 3 } });
  assert.deepEqual(trainer.map((c) => c.key), ['workouts', 'video', 'trainees', 'messages']);
});

test('the overview of each role returns its own cards', async () => {
  const s = await start(data());
  try {
    const doc = (await s.call('GET', '/api/dashboard', { as: 'doc1' })).body;
    assert.deepEqual(doc.cards.map((c) => c.key), ['patients', 'today', 'prescriptions', 'messages']);
    const nut = (await s.call('GET', '/api/dashboard', { as: 'nut1' })).body;
    assert.deepEqual(nut.cards.map((c) => c.key), ['dietReviews', 'video', 'clients', 'messages']);
  } finally {
    s.close();
  }
});
