import test from 'node:test';
import assert from 'node:assert/strict';
import { MIN, NOW, appointment, baseData, start } from './helpers.js';
import { callSummary, parseRoom } from '../src/lib/call.js';

const ROOM = 'baymax-abcdefghjkmnpqrstuvw';
const LINK = `https://meet.jit.si/${ROOM}`;

const data = () =>
  baseData({
    appointments: {
      soon: appointment({ startAt: NOW + 3 * MIN, meetingLink: LINK }),
      later: appointment({ startAt: NOW + 60 * MIN, meetingLink: LINK }),
      live: appointment({ startAt: NOW - 5 * MIN, meetingLink: LINK, type: 'chat' }),
      over: appointment({ startAt: NOW - 90 * MIN, meetingLink: LINK }),
      requested: appointment({ status: 'requested', startAt: NOW + 3 * MIN, meetingLink: '' }),
      cancelled: appointment({ status: 'cancelled', startAt: NOW + 3 * MIN, meetingLink: LINK }),
      foreign: appointment({ startAt: NOW + 3 * MIN, meetingLink: 'https://evil.example/baymax-abcdefghjkmnpqrstuvw' }),
      other: appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', startAt: NOW + 3 * MIN, meetingLink: LINK }),
    },
  });

test('only a room on the configured meeting server, with a server-made name, is ever handed to the page', () => {
  assert.deepEqual(parseRoom(LINK, 'https://meet.jit.si'), { domain: 'meet.jit.si', room: ROOM, startMuted: false });
  assert.equal(parseRoom(`${LINK}#config.startWithVideoMuted=true`, 'https://meet.jit.si').startMuted, true);
  for (const bad of ['http://meet.jit.si/' + ROOM, 'https://evil.example/' + ROOM, 'https://meet.jit.si/room', 'https://meet.jit.si/', 'javascript:alert(1)', 'not a url', '']) {
    assert.equal(parseRoom(bad, 'https://meet.jit.si'), null, bad);
  }
});

test('the call log turns joins and leaves into minutes, and an unclosed join ends with the slot', () => {
  const T = 1_000_000_000_000;
  const end = T + 30 * MIN;
  assert.deepEqual(callSummary({}, end), { joins: 0, firstJoinAt: null, lastLeftAt: null, minutes: 0 });
  assert.deepEqual(
    callSummary({ a: { event: 'joined', at: T }, b: { event: 'left', at: T + 10 * MIN }, c: { event: 'joined', at: T + 12 * MIN }, d: { event: 'left', at: T + 20 * MIN } }, end),
    { joins: 2, firstJoinAt: T, lastLeftAt: T + 20 * MIN, minutes: 18 },
  );
  assert.equal(callSummary({ a: { event: 'joined', at: T + 20 * MIN } }, end).minutes, 10); // closed tab: counts until the slot ends
  assert.equal(callSummary({ a: { event: 'joined', at: T }, b: { event: 'joined', at: T + MIN } }, end).joins, 1); // a double join is one join
  assert.equal(callSummary({ a: { event: 'bogus', at: T }, b: null, c: { event: 'left', at: T } }, end).joins, 0);
});

test('the room name is given out only while the specialist may join', async () => {
  const s = await start(data());
  try {
    const open = (await s.call('GET', '/api/appointments/soon/call', { as: 'doc1' })).body;
    assert.equal(open.canJoin, true);
    assert.deepEqual(open.room, { domain: 'meet.jit.si', room: ROOM, startMuted: false });
    assert.equal(open.displayName, 'Hina Malik');
    const chat = (await s.call('GET', '/api/appointments/live/call', { as: 'doc1' })).body;
    assert.equal(chat.canJoin, true);
    for (const [id, text] of [['later', /opens 5 minutes before/], ['over', /time has passed/], ['requested', /Accept the request/], ['cancelled', /cancelled/], ['foreign', /no valid video room/]]) {
      const r = (await s.call('GET', `/api/appointments/${id}/call`, { as: 'doc1' })).body;
      assert.equal(r.canJoin, false, id);
      assert.equal('room' in r, false, `${id} must not reveal a room`);
      assert.match(r.reason, text, id);
    }
    assert.equal((await s.call('GET', '/api/appointments/other/call', { as: 'doc1' })).status, 404); // someone else's
    assert.equal((await s.call('GET', '/api/appointments/bad.id/call', { as: 'doc1' })).status, 400);
    assert.equal((await s.call('GET', '/api/appointments/soon/call', { as: 'pat1' })).status, 403);
  } finally {
    s.close();
  }
});

test('joining and leaving are logged and add up in the appointment page', async () => {
  const s = await start(data());
  try {
    const bad = await s.call('POST', '/api/appointments/soon/call/event', { as: 'doc1', body: { event: 'danced' } });
    assert.equal(bad.status, 400);
    assert.equal((await s.call('POST', '/api/appointments/later/call/event', { as: 'doc1', body: { event: 'joined' } })).status, 400); // room not open
    assert.equal((await s.call('POST', '/api/appointments/requested/call/event', { as: 'doc1', body: { event: 'joined' } })).status, 400);
    assert.equal((await s.call('POST', '/api/appointments/other/call/event', { as: 'doc1', body: { event: 'joined' } })).status, 404);

    assert.equal((await s.call('POST', '/api/appointments/live/call/event', { as: 'doc1', body: { event: 'joined' } })).status, 201);
    s.clock.now = NOW + 12 * MIN;
    const left = await s.call('POST', '/api/appointments/live/call/event', { as: 'doc1', body: { event: 'left' } });
    assert.equal(left.status, 201);
    assert.equal(left.body.summary.minutes, 12);

    const detail = (await s.call('GET', '/api/appointments/live', { as: 'doc1' })).body;
    assert.equal(detail.call.joins, 1);
    assert.equal(detail.call.minutes, 12);
    const entries = Object.values(s.db.root.callLog.live);
    assert.deepEqual(entries.map((e) => [e.event, e.uid, e.role]), [['joined', 'doc1', 'doctor'], ['left', 'doc1', 'doctor']]);
  } finally {
    s.close();
  }
});

test('leaving is still logged after the slot has ended, so a call that overran closes', async () => {
  const s = await start(data());
  try {
    await s.call('POST', '/api/appointments/live/call/event', { as: 'doc1', body: { event: 'joined' } });
    s.clock.now = NOW + 40 * MIN;
    assert.equal((await s.call('POST', '/api/appointments/live/call/event', { as: 'doc1', body: { event: 'left' } })).status, 201);
    assert.equal((await s.call('POST', '/api/appointments/live/call/event', { as: 'doc1', body: { event: 'joined' } })).status, 400);
  } finally {
    s.close();
  }
});
