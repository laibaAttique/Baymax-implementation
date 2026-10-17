import test from 'node:test';
import assert from 'node:assert/strict';
import { NOW, baseData, start } from './helpers.js';

const accounts = { 'adm1@example.com': 'adm1' };
const form = (o = {}) => ({
  name: 'Dr Ayesha Noor',
  type: 'doctor',
  specialty: 'Cardiology',
  licenseNumber: 'PMDC-12345',
  yearsOfExperience: 9,
  fees: { video: 3000, chat: 1800 },
  ...o,
});

test('a member who is not a specialist is told so, with no application yet', async () => {
  const s = await start(baseData());
  try {
    const me = await s.call('GET', '/api/me', { as: 'pat1' });
    assert.equal(me.status, 200);
    assert.equal(me.body.role, 'user');
    assert.equal(me.body.profile, null);
    assert.equal(me.body.application, null);
    // and the specialist screens stay closed to them
    assert.equal((await s.call('GET', '/api/dashboard', { as: 'pat1' })).status, 403);
  } finally {
    s.close();
  }
});

test('registering stores a pending application and grants nothing', async () => {
  const s = await start(baseData());
  try {
    const r = await s.call('POST', '/api/applications', { as: 'newbie', body: form({ email: 'attacker@evil.test', role: 'admin' }) });
    assert.equal(r.status, 201);
    assert.equal(r.body.application.status, 'pending');
    const stored = s.db.root.applications.newbie;
    assert.equal(stored.email, 'newbie@example.com'); // from the signed-in account, never the form
    assert.equal(stored.licenseNumber, 'PMDC-12345');
    assert.equal(stored.profile.type, 'doctor');
    assert.equal(s.db.root.roles.newbie, undefined); // no role
    assert.equal(s.db.root.specialists.newbie, undefined); // not listed in the app
    // still a non-specialist, now with a pending application
    const me = (await s.call('GET', '/api/me', { as: 'newbie' })).body;
    assert.equal(me.role, 'user');
    assert.equal(me.application.status, 'pending');
    assert.equal(JSON.stringify(me).includes('PMDC'), false); // the licence number is not echoed back
    assert.equal((await s.call('GET', '/api/appointments', { as: 'newbie' })).status, 403);
  } finally {
    s.close();
  }
});

test('the registration form is checked, and the licence number is required', async () => {
  const s = await start(baseData());
  try {
    const bad = async (o, re) => {
      const r = await s.call('POST', '/api/applications', { as: 'newbie', body: form(o) });
      assert.equal(r.status, 400, JSON.stringify(o));
      assert.match(r.body.error, re);
    };
    await bad({ licenseNumber: '' }, /licence/);
    await bad({ licenseNumber: '<script>' }, /licence/);
    await bad({ type: 'admin' }, /Type must be/);
    await bad({ name: 'A' }, /name/);
    await bad({ fees: undefined }, /Fees/);
    assert.equal(s.db.root.applications, undefined);
  } finally {
    s.close();
  }
});

test('specialists and administrators cannot register again, and an approved application cannot be overwritten', async () => {
  const s = await start(baseData());
  try {
    assert.equal((await s.call('POST', '/api/applications', { as: 'doc1', body: form() })).status, 409);
    assert.equal((await s.call('POST', '/api/applications', { as: 'adm1', body: form() })).status, 409);
    assert.equal((await s.call('POST', '/api/applications')).status, 401);
  } finally {
    s.close();
  }
});

test('a rejected or pending application can be corrected and sent again', async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: form({ licenseNumber: 'WRONG-1' }) });
    await s.call('POST', '/api/admin/applications/newbie/reject', { as: 'adm1', body: { reason: 'Licence number not found' } });
    const rejected = (await s.call('GET', '/api/me', { as: 'newbie' })).body.application;
    assert.equal(rejected.status, 'rejected');
    assert.equal(rejected.rejectReason, 'Licence number not found');
    const again = await s.call('POST', '/api/applications', { as: 'newbie', body: form({ licenseNumber: 'PMDC-99999' }) });
    assert.equal(again.status, 201);
    assert.equal(s.db.root.applications.newbie.status, 'pending');
    assert.equal(s.db.root.applications.newbie.licenseNumber, 'PMDC-99999');
    assert.equal(s.db.root.applications.newbie.rejectReason, undefined);
  } finally {
    s.close();
  }
});

test('only an administrator sees and decides applications', async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: form() });
    for (const who of ['newbie', 'doc1', 'pat1']) {
      assert.equal((await s.call('GET', '/api/admin/applications', { as: who })).status, 403, who);
      assert.equal((await s.call('POST', '/api/admin/applications/newbie/approve', { as: who })).status, 403, who);
    }
    assert.equal(s.db.root.roles.newbie, undefined);
    const list = (await s.call('GET', '/api/admin/applications', { as: 'adm1' })).body.applications;
    assert.equal(list.length, 1);
    assert.equal(list[0].licenseNumber, 'PMDC-12345'); // the administrator does see it, to check it
    assert.equal(list[0].status, 'pending');
  } finally {
    s.close();
  }
});

test('approving creates the role and the public profile, marks the specialist verified, and lets them sign in as a specialist', async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: form({ bio: 'Cardiologist' }) });
    const r = await s.call('POST', '/api/admin/applications/newbie/approve', { as: 'adm1' });
    assert.equal(r.status, 200);
    assert.equal(s.db.root.roles.newbie, 'doctor');
    const p = s.db.root.specialists.newbie;
    assert.equal(p.name, 'Dr Ayesha Noor');
    assert.equal(p.verified, true);
    assert.equal(p.rating, 0);
    assert.deepEqual(p.fees, { video: 3000, chat: 1800 });
    assert.equal(p.licenseNumber, undefined); // the licence number is not published
    assert.equal(s.db.root.applications.newbie.status, 'approved');
    assert.equal(s.db.root.applications.newbie.reviewedBy, 'adm1');
    const me = (await s.call('GET', '/api/me', { as: 'newbie' })).body;
    assert.equal(me.role, 'doctor');
    assert.equal(me.profile.verified, true);
    assert.equal((await s.call('GET', '/api/dashboard', { as: 'newbie' })).status, 200);
    // approving twice, or registering again, is refused
    assert.equal((await s.call('POST', '/api/admin/applications/newbie/approve', { as: 'adm1' })).status, 409);
    assert.equal((await s.call('POST', '/api/applications', { as: 'newbie', body: form() })).status, 409);
  } finally {
    s.close();
  }
});

test('an account that already holds another role cannot be approved into a new one', async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'nobody', body: form() });
    s.db.root.roles.nobody = 'trainer'; // e.g. set by an administrator in the meantime
    const r = await s.call('POST', '/api/admin/applications/nobody/approve', { as: 'adm1' });
    assert.equal(r.status, 409);
    assert.match(r.body.error, /already has the role "trainer"/);
    assert.equal(s.db.root.specialists.nobody, undefined);
    assert.equal((await s.call('POST', '/api/admin/applications/missing/approve', { as: 'adm1' })).status, 404);
  } finally {
    s.close();
  }
});

test('rejecting records the reason, never creates a role, and an approved application cannot be rejected', async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: form() });
    assert.equal((await s.call('POST', '/api/admin/applications/newbie/reject', { as: 'adm1', body: { reason: 'x'.repeat(301) } })).status, 400);
    assert.equal((await s.call('POST', '/api/admin/applications/newbie/reject', { as: 'adm1', body: {} })).status, 200); // reason optional
    assert.equal(s.db.root.roles.newbie, undefined);
    await s.call('POST', '/api/applications', { as: 'newbie', body: form() });
    await s.call('POST', '/api/admin/applications/newbie/approve', { as: 'adm1' });
    assert.equal((await s.call('POST', '/api/admin/applications/newbie/reject', { as: 'adm1' })).status, 409);
  } finally {
    s.close();
  }
});
