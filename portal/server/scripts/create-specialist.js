// Administrator tool: makes a person a Baymax specialist.
//   node scripts/create-specialist.js --email sara@example.com --name "Sara Khan" --type nutritionist --specialty "Sports nutrition" \
//        --video-fee 2000 --chat-fee 1200 [--years 7] [--bio "..."] [--emergency] [--tz 300] \
//        [--days 1,2,3,4,5 --start 09:00 --end 17:00 --slot 30] [--dry-run]
//
// It (1) finds or creates the Firebase sign-in account (no password is set or seen here), (2) writes roles/{uid}, which the database
// rules let nobody but an administrator change, (3) writes the public profile specialists/{uid} that the mobile app lists, and
// (4) prints a one-time link the specialist uses to choose their own password. Run it with the service-account key set in .env.
import 'dotenv/config';
import { parseArgs } from 'node:util';
import { connectFirebase } from '../src/firebase.js';
import { SPECIALIST_ROLES, parseProfileUpdate } from '../src/lib/rules.js';

const { values: v } = parseArgs({
  options: {
    email: { type: 'string' }, name: { type: 'string' }, type: { type: 'string' }, specialty: { type: 'string' },
    'video-fee': { type: 'string' }, 'chat-fee': { type: 'string' }, years: { type: 'string', default: '0' }, bio: { type: 'string', default: '' },
    emergency: { type: 'boolean', default: false }, tz: { type: 'string', default: '300' },
    days: { type: 'string', default: '1,2,3,4,5' }, start: { type: 'string', default: '09:00' }, end: { type: 'string', default: '17:00' },
    slot: { type: 'string', default: '30' }, 'dry-run': { type: 'boolean', default: false },
  },
});

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

if (!v.email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.email)) fail('--email is required and must be an email address.');
if (!v.name?.trim()) fail('--name is required.');
if (!SPECIALIST_ROLES.includes(v.type)) fail(`--type must be one of: ${SPECIALIST_ROLES.join(', ')}.`);
if (!v.specialty?.trim()) fail('--specialty is required.');
const tz = Number(v.tz);
if (!Number.isInteger(tz) || tz < -720 || tz > 840) fail('--tz must be minutes east of UTC, e.g. 300 for Pakistan.');

const parsed = parseProfileUpdate({
  specialty: v.specialty,
  bio: v.bio,
  yearsOfExperience: Number(v.years),
  emergency: v.emergency,
  available: true,
  fees: { video: Number(v['video-fee']), chat: Number(v['chat-fee']) },
  availability: { days: v.days.split(',').map(Number), start: v.start, end: v.end, slotMinutes: Number(v.slot) },
});
if (parsed.error) fail(parsed.error);

const profile = { name: v.name.trim(), type: v.type, tzOffsetMinutes: tz, ...parsed.value };

if (v['dry-run']) {
  console.log('Dry run. Would set up:', JSON.stringify({ email: v.email, role: v.type, profile }, null, 2));
  process.exit(0);
}

const { auth, db } = connectFirebase({ databaseURL: process.env.FIREBASE_DATABASE_URL });

let user;
try {
  user = await auth.getUserByEmail(v.email);
  console.log(`Found the existing account for ${v.email}.`);
} catch (e) {
  if (e.code !== 'auth/user-not-found') throw e;
  user = await auth.createUser({ email: v.email, displayName: v.name.trim() });
  console.log(`Created the account for ${v.email}.`);
}

const existing = (await db.get(`specialists/${user.uid}`)) ?? {};
await db.update({
  [`roles/${user.uid}`]: v.type,
  // Rating and review count are kept if the person already had a profile.
  [`specialists/${user.uid}`]: { rating: 0, reviewCount: 0, ...existing, ...profile, updatedAt: Date.now() },
});
console.log(`Set role "${v.type}" and wrote the public profile for ${profile.name} (${user.uid}).`);

const link = await auth.generatePasswordResetLink(v.email);
console.log('\nSend this one-time link to the specialist so they can choose their own password:\n');
console.log(link);
