import { createApp } from '../src/app.js';
import { memoryDb } from '../src/lib/db.js';

export const MIN = 60_000;
// Monday 19 Oct 2026, 10:00 in Pakistan (UTC+5) = 05:00 UTC.
export const NOW = Date.UTC(2026, 9, 19, 5, 0);

/** A fake of the parts of Firebase Auth the API uses. Accounts live in memory; createUser must never be given a password. */
function makeFakeAuth(accounts = {}) {
  const byEmail = new Map(Object.entries(accounts).map(([email, uid]) => [email, { uid, email }]));
  let n = 0;
  return {
    byEmail,
    deleted: [],
    async verifyIdToken(token) {
      // "token-x" signed in just now; "old-x" signed in an hour ago (closing an account needs a recent sign-in)
      if (token.startsWith('token-')) return { uid: token.slice(6), email: `${token.slice(6)}@example.com`, auth_time: Math.floor(NOW / 1000) };
      if (token.startsWith('old-')) return { uid: token.slice(4), email: `${token.slice(4)}@example.com`, auth_time: Math.floor(NOW / 1000) - 3600 };
      throw new Error('bad token');
    },
    async deleteUser(uid) {
      this.deleted.push(uid);
    },
    async getUserByEmail(email) {
      const u = byEmail.get(email);
      if (!u) throw Object.assign(new Error('not found'), { code: 'auth/user-not-found' });
      return u;
    },
    async createUser({ email, displayName, password }) {
      if (password !== undefined) throw new Error('an administrator must never set a password');
      const u = { uid: `new${++n}`, email, displayName };
      byEmail.set(email, u);
      return u;
    },
    async getUsers(ids) {
      const uids = new Set(ids.map((i) => i.uid));
      return { users: [...byEmail.values()].filter((u) => uids.has(u.uid)) };
    },
    async generatePasswordResetLink(email) {
      return `https://example.test/reset?email=${encodeURIComponent(email)}`;
    },
  };
}

export function appointment(overrides = {}) {
  const start = overrides.startAt ?? NOW + 60 * MIN;
  return {
    patientId: 'pat1',
    patientName: 'Ayesha Khan',
    specialistId: 'doc1',
    specialistName: 'Dr. Hina Malik',
    role: 'doctor',
    specialty: 'General medicine',
    startAt: start,
    slotKey: String(start),
    durationMinutes: 30,
    type: 'video',
    status: 'confirmed',
    fee: 2500,
    meetingLink: 'https://meet.example/baymax-abc',
    notesForSpecialist: 'Tired all the time',
    shares: { healthSummary: false, foodLog7d: false, activity30d: false },
    createdAt: NOW - 1000,
    ...overrides,
  };
}

export const profile = (type, name) => ({
  name,
  type,
  specialty: 'General',
  fees: { video: 2000, chat: 1000 },
  availability: { days: [1, 2, 3, 4, 5], start: '09:00', end: '17:00', slotMinutes: 30 },
  tzOffsetMinutes: 300,
  available: true,
});

export function baseData(extra = {}) {
  return {
    roles: { doc1: 'doctor', nut1: 'nutritionist', pat1: 'user', adm1: 'admin', ghost: 'doctor', mixed: 'trainer' },
    specialists: { doc1: profile('doctor', 'Hina Malik'), nut1: profile('nutritionist', 'Sara Khan'), mixed: profile('doctor', 'Mismatch') },
    ...extra,
  };
}

/** Starts the API on a free port with an in-memory database. */
export async function start(data, { now = NOW, accounts = {} } = {}) {
  const db = memoryDb(data);
  const clock = { now };
  const auth = makeFakeAuth(accounts);
  const app = createApp({ auth, db, now: () => clock.now });
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { as, body, old } = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: { ...(as ? { Authorization: `Bearer ${old ? 'old' : 'token'}-${as}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
  return { db, clock, call, base, auth, close: () => server.close() };
}
