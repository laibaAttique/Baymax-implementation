// One-time setup: makes an EXISTING account a Baymax administrator, so that person can add specialists from the portal's
// "Specialists" page instead of the command line.
//   node scripts/make-admin.js --email you@example.com
// The account must already exist (for example your Baymax app login). An account that is already a doctor, nutritionist or trainer
// is refused, so one account is never two things.
import 'dotenv/config';
import { parseArgs } from 'node:util';
import { connectFirebase } from '../src/firebase.js';

const { values: v } = parseArgs({ options: { email: { type: 'string' } } });
const email = (v.email ?? '').trim().toLowerCase();
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error('Error: --email is required and must be an email address.');
  process.exit(1);
}

try {
  const { auth, db } = connectFirebase({ databaseURL: process.env.FIREBASE_DATABASE_URL });
  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      console.error(`Error: there is no account for ${email}. Sign up in the Baymax app first, or check the spelling.`);
      process.exit(1);
    }
    throw e;
  }
  const role = await db.get(`roles/${user.uid}`);
  if (role === 'admin') {
    console.log(`${email} is already an administrator.`);
  } else if (role && role !== 'user') {
    console.error(`Error: ${email} is already a ${role}. Use a different account for the administrator.`);
    process.exit(1);
  } else {
    await db.update({ [`roles/${user.uid}`]: 'admin' });
    console.log(`${email} is now a Baymax administrator. Sign in to the admin panel to approve specialists.`);
  }
  process.exit(0); // the database connection would otherwise keep the script running
} catch (e) {
  console.error(e);
  process.exit(1);
}
