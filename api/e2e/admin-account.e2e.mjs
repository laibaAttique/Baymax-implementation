// scripts/create-admin.js on the emulator: the login it saves must really work, and the file must be private.
import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtempSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { adminDb, auth, makeUser, reset, signIn, waitForEmulators } from './harness.mjs';
import { createApp } from '../src/app.js';
import { connectFirebase } from '../src/firebase.js';

const run = promisify(execFile);
const serverDir = new URL('..', import.meta.url).pathname;
const dir = mkdtempSync(join(tmpdir(), 'baymax-admin-'));
const envFile = join(dir, '.env.admin');
const script = (args) => run('node', ['scripts/create-admin.js', ...args], { cwd: serverDir, env: { ...process.env, FIREBASE_DATABASE_URL: 'https://demo-baymax-default-rtdb.firebaseio.com' } });
const read = () => Object.fromEntries(readFileSync(envFile, 'utf8').split('\n').filter((l) => l && !l.startsWith('#')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));

let base, server;
before(async () => {
  await waitForEmulators();
  await reset();
  const { auth: a, db } = connectFirebase({ databaseURL: 'https://demo-baymax-default-rtdb.firebaseio.com' });
  server = await new Promise((r) => { const s = createApp({ auth: a, db }).listen(0, () => r(s)); });
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => server?.close());

const overview = async (client) => (await fetch(`${base}/api/admin/overview`, { headers: { Authorization: `Bearer ${await client.idToken()}` } })).status;

test('ATC-INT-31 the saved login signs in and is accepted by the admin API; the file is private and the password is not printed', async () => {
  const out = await script(['--email', 'boss@example.com', '--out', envFile]);
  assert.match(out.stdout, /Created the administrator account boss@example\.com/);
  const saved = read();
  assert.equal(saved.BAYMAX_ADMIN_EMAIL, 'boss@example.com');
  assert.ok(saved.BAYMAX_ADMIN_PASSWORD.length >= 20);
  assert.equal(out.stdout.includes(saved.BAYMAX_ADMIN_PASSWORD), false, 'the password must not be printed');
  assert.equal(out.stderr.includes(saved.BAYMAX_ADMIN_PASSWORD), false);
  assert.equal(statSync(envFile).mode & 0o777, 0o600, 'only the owner can read the file');
  const uid = (await auth.getUserByEmail('boss@example.com')).uid;
  assert.equal((await adminDb.ref(`roles/${uid}`).get()).val(), 'admin');
  const client = await signIn({ uid, email: saved.BAYMAX_ADMIN_EMAIL, password: saved.BAYMAX_ADMIN_PASSWORD });
  assert.equal(await overview(client), 200);
});

test('ATC-INT-32 running it again does not change the password or the file, unless a reset is requested', async () => {
  const before = readFileSync(envFile, 'utf8');
  await assert.rejects(script(['--email', 'boss@example.com', '--out', envFile]), (e) => /already exists/.test(e.stderr) && e.code === 1);
  assert.equal(readFileSync(envFile, 'utf8'), before);
  const old = read();
  await script(['--email', 'boss@example.com', '--out', envFile, '--reset-password']);
  const fresh = read();
  assert.notEqual(fresh.BAYMAX_ADMIN_PASSWORD, old.BAYMAX_ADMIN_PASSWORD);
  assert.equal(statSync(envFile).mode & 0o777, 0o600);
  const uid = (await auth.getUserByEmail('boss@example.com')).uid;
  await signIn({ uid, email: fresh.BAYMAX_ADMIN_EMAIL, password: fresh.BAYMAX_ADMIN_PASSWORD }); // the new one works
  await assert.rejects(signIn({ uid, email: old.BAYMAX_ADMIN_EMAIL, password: old.BAYMAX_ADMIN_PASSWORD })); // the old one no longer does
});

test('ATC-INT-33 an ordinary member who is not an admin cannot use the admin API, and an existing member account is not hijacked', async () => {
  const member = await makeUser('member@example.com', 'members-own-password');
  const client = await signIn(member);
  assert.equal(await overview(client), 403);
  await assert.rejects(script(['--email', 'member@example.com', '--out', join(dir, 'other.env')]), /already exists/);
  await signIn(member); // their own password still works
});
