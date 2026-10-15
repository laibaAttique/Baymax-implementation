import { createApp } from '../src/app.js';
import { memoryDb } from '../src/lib/db.js';

export const MIN = 60_000;
// Monday 19 Oct 2026, 10:00 in Pakistan (UTC+5) = 05:00 UTC.
export const NOW = Date.UTC(2026, 9, 19, 5, 0);

const fakeAuth = {
  async verifyIdToken(token) {
    if (!token.startsWith('token-')) throw new Error('bad token');
    const uid = token.slice(6);
    return { uid, email: `${uid}@example.com` };
  },
};

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
export async function start(data, { now = NOW } = {}) {
  const db = memoryDb(data);
  const clock = { now };
  const app = createApp({ auth: fakeAuth, db, now: () => clock.now });
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = async (method, path, { as, body } = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: { ...(as ? { Authorization: `Bearer token-${as}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json().catch(() => null) };
  };
  return { db, clock, call, base, close: () => server.close() };
}
