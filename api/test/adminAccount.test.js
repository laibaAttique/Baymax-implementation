import test from 'node:test';
import assert from 'node:assert/strict';
import { createAdminAccount, generatePassword } from '../src/lib/adminAccount.js';
import { memoryDb } from '../src/lib/db.js';

function fakeAuth(accounts = {}) {
  const byEmail = new Map(Object.entries(accounts).map(([email, uid]) => [email, { uid, email }]));
  const log = { created: [], updated: [] };
  return {
    log,
    async getUserByEmail(email) {
      const u = byEmail.get(email);
      if (!u) throw Object.assign(new Error('x'), { code: 'auth/user-not-found' });
      return u;
    },
    async createUser(data) {
      const u = { uid: `new${log.created.length + 1}`, email: data.email };
      byEmail.set(data.email, u);
      log.created.push(data);
      return u;
    },
    async updateUser(uid, data) {
      log.updated.push({ uid, ...data });
    },
  };
}

test('a generated password is long, random, and has every kind of character', () => {
  const seen = new Set();
  for (let i = 0; i < 200; i++) {
    const p = generatePassword();
    seen.add(p);
    assert.equal(p.length, 20);
    assert.match(p, /[A-Z]/);
    assert.match(p, /[a-z]/);
    assert.match(p, /[0-9]/);
    assert.match(p, /[!#$%*+\-=?]/);
    assert.doesNotMatch(p, /[O0Il1]/); // no look-alike characters
  }
  assert.equal(seen.size, 200);
  assert.throws(() => generatePassword(8), /at least 12/);
});

test('a new administrator gets an account, a generated password and the admin role', async () => {
  const auth = fakeAuth();
  const db = memoryDb();
  const out = await createAdminAccount({ auth, db }, { email: ' Admin@Example.com ' });
  assert.equal(out.created, true);
  assert.equal(out.password.length, 20);
  assert.equal(auth.log.created[0].email, 'admin@example.com');
  assert.equal(auth.log.created[0].password, out.password);
  assert.equal(db.root.roles[out.uid], 'admin');
});

test('an existing account keeps its password unless a reset is asked for, and nothing is changed when refused', async () => {
  const auth = fakeAuth({ 'member@example.com': 'u1' });
  const db = memoryDb({ roles: { u1: 'user' } });
  await assert.rejects(createAdminAccount({ auth, db }, { email: 'member@example.com' }), /already exists.*not changed/s);
  assert.deepEqual(auth.log.updated, []);
  assert.equal(db.root.roles.u1, 'user');
  const out = await createAdminAccount({ auth, db }, { email: 'member@example.com', resetPassword: true });
  assert.equal(out.created, false);
  assert.deepEqual(auth.log.updated, [{ uid: 'u1', password: out.password }]);
  assert.equal(db.root.roles.u1, 'admin');
});

test('a specialist account is never converted, and a bad email is refused', async () => {
  const auth = fakeAuth({ 'doc@example.com': 'u2' });
  const db = memoryDb({ roles: { u2: 'doctor' } });
  await assert.rejects(createAdminAccount({ auth, db }, { email: 'doc@example.com', resetPassword: true }), /already a doctor/);
  assert.deepEqual(auth.log.updated, []);
  assert.equal(db.root.roles.u2, 'doctor');
  await assert.rejects(createAdminAccount({ auth, db }, { email: 'nope' }), /valid email/);
  await assert.rejects(createAdminAccount({ auth, db }, {}), /valid email/);
});

test('an administrator who already exists can be given a new password on request', async () => {
  const auth = fakeAuth({ 'a@example.com': 'u3' });
  const db = memoryDb({ roles: { u3: 'admin' } });
  await assert.rejects(createAdminAccount({ auth, db }, { email: 'a@example.com' }), /already exists/);
  const out = await createAdminAccount({ auth, db }, { email: 'a@example.com', resetPassword: true });
  assert.equal(out.created, false);
  assert.equal(db.root.roles.u3, 'admin');
});
