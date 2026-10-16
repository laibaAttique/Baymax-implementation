// Shared helpers for the end-to-end checks. Everything talks to the LOCAL Firebase emulators (never the real project).
//   firebase emulators:start --only auth,database --project demo-baymax   (from ../emulator)
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:9000';
process.env.GCLOUD_PROJECT = 'demo-baymax';

import { initializeApp as initAdmin, getApps as adminApps } from 'firebase-admin/app';
import { getAuth as adminAuth } from 'firebase-admin/auth';
import { getDatabase as adminDatabase } from 'firebase-admin/database';
import { initializeApp as initClient } from 'firebase/app';
import { getAuth, connectAuthEmulator, signInWithEmailAndPassword } from 'firebase/auth';
import { getDatabase, connectDatabaseEmulator, ref, update, get, set, remove } from 'firebase/database';

export const DB_URL = 'https://demo-baymax-default-rtdb.firebaseio.com';

const admin = adminApps()[0] ?? initAdmin({ projectId: 'demo-baymax', databaseURL: DB_URL });
export const auth = adminAuth(admin);
export const adminDb = adminDatabase(admin);

export async function reset() {
  await adminDb.ref().set(null);
  const { users } = await auth.listUsers(1000);
  if (users.length) await auth.deleteUsers(users.map((u) => u.uid));
}

/** Creates an account in the Auth emulator (with a password, which is fine for a fake project). */
export async function makeUser(email, password = 'password123') {
  const u = await auth.createUser({ email, password, displayName: email.split('@')[0] });
  return { uid: u.uid, email, password };
}

let counter = 0;
/** Signs in as [user] with the real client SDK, so the database rules apply exactly as they do on a phone. */
export async function signIn(user) {
  const app = initClient({ apiKey: 'fake-api-key', projectId: 'demo-baymax', databaseURL: DB_URL, authDomain: 'demo-baymax.firebaseapp.com' }, `client-${++counter}`);
  const a = getAuth(app);
  connectAuthEmulator(a, 'http://127.0.0.1:9099', { disableWarnings: true });
  await signInWithEmailAndPassword(a, user.email, user.password);
  const db = getDatabase(app);
  connectDatabaseEmulator(db, '127.0.0.1', 9000);
  return {
    uid: user.uid,
    db,
    ref: (path) => ref(db, path),
    get: async (path) => (await get(ref(db, path))).val(),
    set: (path, v) => set(ref(db, path), v),
    update: (updates) => update(ref(db), updates),
    remove: (path) => remove(ref(db, path)),
    idToken: () => a.currentUser.getIdToken(),
  };
}

/** Resolves to true if the promise is refused by the database rules, false if it went through. */
export async function denied(promise) {
  try {
    await promise;
    return false;
  } catch (e) {
    if (/permission[_ -]denied/i.test(String(e?.code) + String(e?.message))) return true;
    throw e;
  }
}

export async function waitForEmulators(tries = 30) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch('http://127.0.0.1:9099/');
      const d = await fetch('http://127.0.0.1:9000/');
      if (r.ok && d.status < 500) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('The Firebase emulators are not running. Start them: cd ../emulator && firebase emulators:start --only auth,database --project demo-baymax');
}
