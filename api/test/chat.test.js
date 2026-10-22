import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, start } from './helpers.js';
import { CHAT_GRACE_MS, chatState, conversationRow, messageList, parseMessage, unreadFor } from '../src/lib/chat.js';
import { normalizeAppointment } from '../src/lib/rules.js';

const DAY = 86_400_000;
const msg = (side, text, at) => ({ from: side === 'patient' ? 'pat1' : 'doc1', side, text, at });

const data = () =>
  baseData({
    appointments: {
      c1: appointment({ status: 'confirmed', startAt: NOW + 60 * MIN, patientName: 'Ayesha Khan', patientId: 'pat1' }),
      done: appointment({ status: 'completed', startAt: NOW - 2 * DAY, patientName: 'Done Patient', patientId: 'pat2' }),
      old: appointment({ status: 'completed', startAt: NOW - 5 * DAY, patientName: 'Old Patient', patientId: 'pat3' }),
      ancient: appointment({ status: 'completed', startAt: NOW - 200 * DAY, patientName: 'Ancient', patientId: 'pat4' }),
      req: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 90 * MIN, patientName: 'Waiting', patientId: 'pat5' }),
      dec: appointment({ status: 'declined', startAt: NOW + 90 * MIN, patientName: 'Declined', patientId: 'pat6' }),
      other: appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', patientName: 'Not Mine', patientId: 'pat7' }),
    },
    chats: {
      c1: { m1: msg('patient', 'Hello doctor', NOW - 10 * MIN), m2: msg('specialist', 'Hello, how can I help?', NOW - 9 * MIN), m3: msg('patient', 'My back hurts', NOW - 2 * MIN) },
      done: { m1: msg('patient', 'Thank you', NOW - DAY) },
      other: { m1: msg('patient', 'private', NOW - MIN) },
    },
    chatRead: { c1: { doc1: NOW - 9.5 * MIN } },
  });

test('a conversation exists only for an accepted appointment, and closes 24 hours after the slot', () => {
  const st = (over) => chatState(normalizeAppointment('x', appointment(over)), NOW);
  assert.deepEqual(st({ status: 'confirmed' }), { canRead: true, canSend: true, reason: '' });
  assert.equal(st({ status: 'completed', startAt: NOW - 3 * 60 * MIN }).canSend, true);
  assert.equal(st({ status: 'requested' }).canRead, false);
  assert.equal(st({ status: 'declined' }).canRead, false);
  assert.equal(st({ status: 'cancelled' }).canRead, false);
  assert.equal(st({ status: 'pending_payment' }).canRead, false);
  const a = normalizeAppointment('x', appointment({ status: 'completed', startAt: NOW - 3 * DAY }));
  assert.deepEqual([chatState(a, NOW).canRead, chatState(a, NOW).canSend], [true, false]);
  assert.equal(chatState(a, a.endAt + CHAT_GRACE_MS - 1).canSend, true);
  assert.equal(chatState(a, a.endAt + CHAT_GRACE_MS).canSend, false);
});

test('a message is trimmed and must be 1 to 1000 characters of plain text', () => {
  assert.equal(parseMessage({ text: '  hello  ' }), 'hello');
  assert.equal(parseMessage({ text: 'line one\r\nline two' }), 'line one\nline two');
  assert.equal(parseMessage({ text: 'x'.repeat(1000) }).length, 1000);
  for (const bad of [{}, { text: '' }, { text: '   ' }, { text: 5 }, { text: ['a'] }, { text: 'x'.repeat(1001) }, { text: 'bell\u0007' }, { text: 'nul\u0000' }, null]) {
    assert.throws(() => parseMessage(bad), (e) => e.status === 400, JSON.stringify(bad));
  }
});

test('malformed stored messages are dropped, the rest ordered by time, and unread counts only the patient\'s newer ones', () => {
  const list = messageList({
    b: msg('patient', 'second', 20), a: msg('specialist', 'first', 10), junk: { text: 5, at: 1, side: 'patient' }, nosnd: { text: 'x', at: 1, side: 'admin' }, empty: msg('patient', '', 30), noat: { text: 'x', side: 'patient' },
  });
  assert.deepEqual(list.map((m) => m.text), ['first', 'second']);
  assert.equal(unreadFor(list, 0), 1);
  assert.equal(unreadFor(list, 20), 0);
  assert.equal(unreadFor(list, undefined), 1);
  const row = conversationRow(normalizeAppointment('c', appointment({ patientName: 'Z' })), { a: msg('patient', 'q'.repeat(300), NOW - MIN) }, 0, NOW);
  assert.equal(row.last.text.length, 120);
  assert.equal(row.unread, 1);
});

test('the list shows accepted conversations with the last message and unread count, newest first', async () => {
  const s = await start(data());
  try {
    const r = (await s.call('GET', '/api/chats', { as: 'doc1' })).body;
    const ids = r.conversations.map((c) => c.appointmentId);
    assert.deepEqual(ids, ['c1', 'done', 'old']); // newest activity first; none of requested, declined, ancient or someone else's
    const c1 = r.conversations[0];
    assert.deepEqual({ unread: c1.unread, count: c1.messageCount, last: c1.last.text, from: c1.last.side }, { unread: 1, count: 3, last: 'My back hurts', from: 'patient' });
    assert.equal(r.conversations[2].last, null); // no messages yet
    assert.equal(r.unreadTotal, 2); // one in c1 (after the doctor last looked), one in done
    assert.equal((await s.call('GET', '/api/summary', { as: 'doc1' })).body.unreadMessages, 2);
    assert.equal((await s.call('GET', '/api/chats', { as: 'pat1' })).status, 403);
    assert.equal((await s.call('GET', '/api/chats')).status, 401);
  } finally {
    s.close();
  }
});

test('opening a conversation returns its messages, marks them read, and polling returns only newer ones', async () => {
  const s = await start(data());
  try {
    const r = (await s.call('GET', '/api/chats/c1', { as: 'doc1' })).body;
    assert.deepEqual(r.messages.map((m) => m.text), ['Hello doctor', 'Hello, how can I help?', 'My back hurts']);
    assert.equal(r.state.canSend, true);
    assert.equal(r.appointment.patientName, 'Ayesha Khan');
    assert.equal(s.db.root.chatRead.c1.doc1, NOW);
    assert.equal((await s.call('GET', '/api/summary', { as: 'doc1' })).body.unreadMessages, 1); // only 'done' is left unread
    const newer = (await s.call('GET', `/api/chats/c1?since=${NOW - 2 * MIN}`, { as: 'doc1' })).body;
    assert.deepEqual(newer.messages, []);
    const some = (await s.call('GET', `/api/chats/c1?since=${NOW - 9 * MIN}`, { as: 'doc1' })).body;
    assert.deepEqual(some.messages.map((m) => m.text), ['My back hurts']);
  } finally {
    s.close();
  }
});

test('someone else\'s conversation, or one that cannot exist, is refused', async () => {
  const s = await start(data());
  try {
    assert.equal((await s.call('GET', '/api/chats/other', { as: 'doc1' })).status, 404);
    assert.equal((await s.call('GET', '/api/chats/missing', { as: 'doc1' })).status, 404);
    assert.equal((await s.call('GET', '/api/chats/bad.id', { as: 'doc1' })).status, 400);
    assert.equal((await s.call('GET', '/api/chats/req', { as: 'doc1' })).status, 403);
    assert.equal((await s.call('GET', '/api/chats/dec', { as: 'doc1' })).status, 403);
    assert.equal((await s.call('POST', '/api/chats/other', { as: 'doc1', body: { text: 'hi' } })).status, 404);
    assert.equal((await s.call('POST', '/api/chats/req', { as: 'doc1', body: { text: 'hi' } })).status, 403);
    assert.equal(s.db.root.chatRead.other, undefined); // a refused read marks nothing
  } finally {
    s.close();
  }
});

test('sending a message stores it, marks the specialist as caught up and tells the patient once per conversation', async () => {
  const s = await start(data());
  try {
    const r = await s.call('POST', '/api/chats/c1', { as: 'doc1', body: { text: '  Please rest and avoid lifting.  ' } });
    assert.equal(r.status, 201);
    assert.equal(r.body.message.text, 'Please rest and avoid lifting.');
    const stored = Object.values(s.db.root.chats.c1).find((m) => m.text.startsWith('Please rest'));
    assert.deepEqual({ from: stored.from, side: stored.side, at: stored.at }, { from: 'doc1', side: 'specialist', at: NOW });
    assert.equal(s.db.root.chatRead.c1.doc1, NOW);
    assert.match(s.db.root.users.pat1.inbox['chat-c1'].title, /Dr\. Hina Malik/);
    s.clock.now += MIN;
    await s.call('POST', '/api/chats/c1', { as: 'doc1', body: { text: 'Second note' } });
    assert.equal(Object.keys(s.db.root.users.pat1.inbox).filter((k) => k.startsWith('chat-')).length, 1);
    assert.equal(s.db.root.users.pat1.inbox['chat-c1'].body, 'Second note');
  } finally {
    s.close();
  }
});

test('a bad message is refused and nothing is stored', async () => {
  const s = await start(data());
  try {
    for (const body of [{}, { text: '' }, { text: '   ' }, { text: 5 }, { text: 'x'.repeat(1001) }, { text: 'a\u0000b' }]) {
      const r = await s.call('POST', '/api/chats/c1', { as: 'doc1', body });
      assert.equal(r.status, 400, JSON.stringify(body).slice(0, 40));
    }
    assert.equal(Object.keys(s.db.root.chats.c1).length, 3);
  } finally {
    s.close();
  }
});

test('a conversation closed for new messages can still be read', async () => {
  const s = await start(data());
  try {
    s.clock.now = NOW + 3 * DAY;
    const read = await s.call('GET', '/api/chats/done', { as: 'doc1' });
    assert.equal(read.status, 200);
    assert.equal(read.body.state.canSend, false);
    const send = await s.call('POST', '/api/chats/done', { as: 'doc1', body: { text: 'late' } });
    assert.equal(send.status, 403);
    assert.match(send.body.error, /closed/);
  } finally {
    s.close();
  }
});

test('at most 20 messages a minute per conversation', async () => {
  const s = await start(data());
  try {
    for (let i = 0; i < 20; i++) assert.equal((await s.call('POST', '/api/chats/c1', { as: 'doc1', body: { text: `m${i}` } })).status, 201);
    const r = await s.call('POST', '/api/chats/c1', { as: 'doc1', body: { text: 'one too many' } });
    assert.equal(r.status, 429);
    s.clock.now += 61_000;
    assert.equal((await s.call('POST', '/api/chats/c1', { as: 'doc1', body: { text: 'fine again' } })).status, 201);
  } finally {
    s.close();
  }
});
