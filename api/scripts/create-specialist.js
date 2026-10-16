// Administrator tool: makes a person a Baymax specialist (the portal's Specialists page does the same from a browser).
//   node scripts/create-specialist.js --email sara@example.com --name "Sara Khan" --type nutritionist --specialty "Sports nutrition" \
//        --video-fee 2000 --chat-fee 1200 [--years 7] [--bio "..."] [--emergency] [--tz 300] \
//        [--days 1,2,3,4,5 --start 09:00 --end 17:00 --slot 30] [--dry-run]
// Run it with the service-account key set in .env. No password is set or seen: it prints a one-time link for the person to choose one.
import 'dotenv/config';
import { parseArgs } from 'node:util';
import { connectFirebase } from '../src/firebase.js';
import { AdminError, makeSpecialist, parseNewSpecialist } from '../src/lib/specialistAdmin.js';

const { values: v } = parseArgs({
  options: {
    email: { type: 'string' }, name: { type: 'string' }, type: { type: 'string' }, specialty: { type: 'string' },
    'video-fee': { type: 'string' }, 'chat-fee': { type: 'string' }, years: { type: 'string', default: '0' }, bio: { type: 'string', default: '' },
    emergency: { type: 'boolean', default: false }, tz: { type: 'string', default: '300' },
    days: { type: 'string', default: '1,2,3,4,5' }, start: { type: 'string', default: '09:00' }, end: { type: 'string', default: '17:00' },
    slot: { type: 'string', default: '30' }, 'dry-run': { type: 'boolean', default: false },
  },
});

let input;
try {
  input = parseNewSpecialist({
    email: v.email,
    name: v.name,
    type: v.type,
    specialty: v.specialty,
    bio: v.bio,
    yearsOfExperience: Number(v.years),
    emergency: v.emergency,
    tzOffsetMinutes: Number(v.tz),
    fees: { video: Number(v['video-fee']), chat: Number(v['chat-fee']) },
    availability: { days: v.days.split(',').map(Number), start: v.start, end: v.end, slotMinutes: Number(v.slot) },
  });
} catch (e) {
  console.error(`Error: ${e.message}`);
  process.exit(1);
}

if (v['dry-run']) {
  console.log('Dry run. Would set up:', JSON.stringify({ email: input.email, role: input.type, profile: input.profile }, null, 2));
  process.exit(0);
}

try {
  const { auth, db } = connectFirebase({ databaseURL: process.env.FIREBASE_DATABASE_URL });
  const out = await makeSpecialist({ auth, db }, input);
  console.log(`${out.created ? 'Created' : 'Found'} the account for ${input.email}; set role "${input.type}" and wrote the public profile for ${input.name} (${out.uid}).`);
  console.log('\nSend this one-time link to the specialist so they can choose their own password:\n');
  console.log(out.resetLink);
  process.exit(0); // the database connection would otherwise keep the script running
} catch (e) {
  console.error(e instanceof AdminError ? `Error: ${e.message}` : e);
  process.exit(1);
}
