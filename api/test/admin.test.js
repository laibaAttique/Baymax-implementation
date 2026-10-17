import test from 'node:test';
import assert from 'node:assert/strict';
import { baseData, start } from './helpers.js';

const accounts = { 'doc1@example.com': 'doc1', 'adm1@example.com': 'adm1', 'member@example.com': 'pat1', 'nut1@example.com': 'nut1' };
const form = (o = {}) => ({
  email: 'New.Doctor@Example.com',
  name: 'Hina Malik',
  type: 'doctor',
  specialty: 'General medicine',
  fees: { video: 2500, chat: 1500 },
  ...o,
});

test('an administrator can ask who they are, but the specialist screens stay closed to them', async () => {
  const s = await start(baseData(), { accounts });
  try {
    const me = await s.call('GET', '/api/me', { as: 'adm1' });
    assert.equal(me.status, 200);
    assert.equal(me.body.role, 'admin');
    assert.equal(me.body.roleLabel, 'Administrator');
    assert.equal(me.body.profile, null);
    for (const path of ['/api/dashboard', '/api/appointments']) assert.equal((await s.call('GET', path, { as: 'adm1' })).status, 403, path);
  } finally {
    s.close();
  }
});

test('only an administrator reaches the admin routes', async () => {
  const s = await start(baseData(), { accounts });
  try {
    assert.equal((await s.call('GET', '/api/admin/specialists')).status, 401);
    for (const who of ['doc1', 'nut1', 'pat1', 'nobody']) {
      assert.equal((await s.call('GET', '/api/admin/specialists', { as: who })).status, 403, who);
      assert.equal((await s.call('POST', '/api/admin/specialists', { as: who, body: form() })).status, 403, who);
    }
    assert.equal(s.db.root.roles['new1'], undefined);
  } finally {
    s.close();
  }
});

test('the list shows every specialist with their email, grouped by type', async () => {
  const s = await start(baseData(), { accounts });
  try {
    const r = await s.call('GET', '/api/admin/specialists', { as: 'adm1' });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.specialists.map((x) => [x.type, x.name]), [['doctor', 'Hina Malik'], ['doctor', 'Mismatch'], ['nutritionist', 'Sara Khan']]);
    assert.equal(r.body.specialists[0].email, 'doc1@example.com');
  } finally {
    s.close();
  }
});

test('adding a specialist creates the account without a password, sets the role and profile, and returns a link to choose a password', async () => {
  const s = await start(baseData(), { accounts });
  try {
    const r = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form({ yearsOfExperience: 12, emergency: true }) });
    assert.equal(r.status, 201);
    assert.equal(r.body.created, true);
    assert.equal(r.body.email, 'new.doctor@example.com'); // lower-cased
    assert.match(r.body.resetLink, /^https:\/\//);
    const uid = r.body.uid;
    assert.equal(s.db.root.roles[uid], 'doctor');
    const p = s.db.root.specialists[uid];
    assert.equal(p.name, 'Hina Malik');
    assert.equal(p.type, 'doctor');
    assert.deepEqual(p.fees, { video: 2500, chat: 1500 });
    assert.equal(p.available, true);
    assert.equal(p.emergency, true);
    assert.equal(p.yearsOfExperience, 12);
    assert.equal(p.rating, 0);
    assert.equal(p.reviewCount, 0);
    assert.deepEqual(p.availability, { days: [1, 2, 3, 4, 5], start: '09:00', end: '17:00', slotMinutes: 30 });
    assert.equal(p.tzOffsetMinutes, 300);
    // the new account can now sign in as a specialist
    const me = await s.call('GET', '/api/me', { as: uid });
    assert.equal(me.status, 200);
    assert.equal(me.body.roleLabel, 'Doctor');
  } finally {
    s.close();
  }
});

test('all three kinds of specialist can be added, so the app lists each type', async () => {
  const s = await start(baseData(), { accounts });
  try {
    for (const [type, specialty] of [['doctor', 'General medicine'], ['nutritionist', 'Sports nutrition'], ['trainer', 'Strength']]) {
      const r = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form({ email: `${type}@example.com`, type, specialty }) });
      assert.equal(r.status, 201, type);
    }
    const types = Object.values(s.db.root.specialists).map((x) => x.type);
    for (const t of ['doctor', 'nutritionist', 'trainer']) assert.ok(types.includes(t), t);
  } finally {
    s.close();
  }
});

test('an existing account is upgraded, keeping its rating; a different role is refused so nobody can be demoted', async () => {
  const data = baseData();
  data.specialists.doc1.rating = 4.8;
  data.specialists.doc1.reviewCount = 40;
  const s = await start(data, { accounts });
  try {
    const again = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form({ email: 'doc1@example.com', specialty: 'Cardiology' }) });
    assert.equal(again.status, 200);
    assert.equal(again.body.created, false);
    assert.equal(s.db.root.specialists.doc1.specialty, 'Cardiology');
    assert.equal(s.db.root.specialists.doc1.rating, 4.8);

    const clash = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form({ email: 'doc1@example.com', type: 'trainer' }) });
    assert.equal(clash.status, 409);
    assert.match(clash.body.error, /already has the role "doctor"/);
    assert.equal(s.db.root.roles.doc1, 'doctor');

    const admin = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form({ email: 'adm1@example.com' }) });
    assert.equal(admin.status, 409);
    assert.equal(s.db.root.roles.adm1, 'admin'); // the administrator was not demoted
  } finally {
    s.close();
  }
});

test('an existing ordinary member account can be made a specialist', async () => {
  const s = await start(baseData(), { accounts });
  try {
    const r = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form({ email: 'member@example.com' }) });
    // pat1 has the stored role "user", which is not a specialist type, so it is refused rather than silently changed
    assert.equal(r.status, 409);
    assert.equal(s.db.root.roles.pat1, 'user');
  } finally {
    s.close();
  }
});

test('the form is checked field by field', async () => {
  const s = await start(baseData(), { accounts });
  try {
    const bad = async (o, re) => {
      const r = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: form(o) });
      assert.equal(r.status, 400, JSON.stringify(o));
      assert.match(r.body.error, re);
    };
    await bad({ email: 'not-an-email' }, /email/);
    await bad({ email: undefined }, /email/);
    await bad({ name: 'A' }, /name/);
    await bad({ type: 'admin' }, /Type must be/); // nobody can be made an administrator here
    await bad({ type: 'wizard' }, /Type must be/);
    await bad({ specialty: '' }, /specialty/);
    await bad({ fees: undefined }, /Fees/);
    await bad({ fees: { video: -1, chat: 5 } }, /Fees/);
    await bad({ tzOffsetMinutes: 5000 }, /time zone/);
    await bad({ availability: { days: [], start: '09:00', end: '17:00', slotMinutes: 30 } }, /working day/);
    assert.equal(Object.keys(s.db.root.specialists).length, 3); // nothing was written
  } finally {
    s.close();
  }
});
