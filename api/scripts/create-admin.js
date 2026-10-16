// Creates the Baymax administrator account and saves its login in a private env file.
//
//   node scripts/create-admin.js --email you@example.com
//   node scripts/create-admin.js --email you@example.com --reset-password        (new password for an account that already exists)
//   node scripts/create-admin.js --email you@example.com --out /path/to/file
//
// The password is generated here, on your computer, and written ONLY to the env file (default ../../baymax-admin/.env.admin, readable by
// you alone). It is not printed, not logged and not sent anywhere except to Firebase to set it. Run it with the service-account key set in .env.
import 'dotenv/config';
import { chmodSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { connectFirebase } from '../src/firebase.js';
import { AdminError } from '../src/lib/specialistAdmin.js';
import { createAdminAccount } from '../src/lib/adminAccount.js';

const here = dirname(fileURLToPath(import.meta.url));
const { values: v } = parseArgs({
  options: { email: { type: 'string' }, 'out': { type: 'string' }, 'reset-password': { type: 'boolean', default: false }, url: { type: 'string', default: 'http://localhost:3001' } },
});

const envFile = resolve(v.out ?? resolve(here, '../../baymax-admin/.env.admin'));

try {
  const { auth, db } = connectFirebase({ databaseURL: process.env.FIREBASE_DATABASE_URL });
  const out = await createAdminAccount({ auth, db }, { email: v.email, resetPassword: v['reset-password'] });
  const email = v.email.trim().toLowerCase();
  mkdirSync(dirname(envFile), { recursive: true });
  writeFileSync(
    envFile,
    [
      '# Baymax administrator login. Private: keep this file out of git and out of chat.',
      `# ${out.created ? 'Created' : 'Password reset'} ${new Date().toISOString()}`,
      `BAYMAX_ADMIN_EMAIL=${email}`,
      `BAYMAX_ADMIN_PASSWORD=${out.password}`,
      `BAYMAX_ADMIN_PANEL_URL=${v.url}`,
      '',
    ].join('\n'),
    { mode: 0o600 },
  );
  chmodSync(envFile, 0o600); // also tightens a file that already existed
  console.log(`${out.created ? 'Created' : 'Reset the password of'} the administrator account ${email}.`);
  console.log(`Login saved to ${envFile} (readable only by you). Open it to see the password, then sign in at ${v.url}.`);
  process.exit(0); // the database connection would otherwise keep the script running
} catch (e) {
  if (e instanceof AdminError) {
    console.error(`Error: ${e.message}`);
    process.exit(1);
  }
  console.error(e);
  process.exit(1);
}
