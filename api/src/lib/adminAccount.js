// Creating the first administrator: a sign-in account with a generated password, and the admin role.
// Used by scripts/create-admin.js, which writes the credentials to a private env file instead of printing them.
import { randomInt } from 'node:crypto';
import { AdminError } from './specialistAdmin.js';

const UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER = 'abcdefghijkmnpqrstuvwxyz';
const DIGIT = '23456789';
const SYMBOL = '!#$%*+-=?';
const ALL = UPPER + LOWER + DIGIT + SYMBOL;

/** A random password with at least one upper-case letter, lower-case letter, digit and symbol; look-alike characters are left out. */
export function generatePassword(length = 20, rand = randomInt) {
  if (length < 12) throw new Error('A generated password must be at least 12 characters.');
  const pick = (set) => set[rand(set.length)];
  const chars = [pick(UPPER), pick(LOWER), pick(DIGIT), pick(SYMBOL)];
  while (chars.length < length) chars.push(pick(ALL));
  for (let i = chars.length - 1; i > 0; i--) {
    const j = rand(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/**
 * Makes [email] an administrator and returns the password that was set: { uid, created, password }.
 * A brand-new account gets a generated password. An account that already exists keeps its password (it may be someone's Baymax app
 * login) unless [resetPassword] is true. A doctor, nutritionist or trainer is never converted.
 */
export async function createAdminAccount({ auth, db }, { email, resetPassword = false, makePassword = generatePassword }) {
  const address = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!EMAIL.test(address) || address.length > 120) throw new AdminError(400, 'Enter a valid email address.');

  let user = null;
  try {
    user = await auth.getUserByEmail(address);
  } catch (e) {
    if (e?.code !== 'auth/user-not-found') throw e;
  }

  if (!user) {
    const password = makePassword();
    const created = await auth.createUser({ email: address, password, displayName: 'Baymax administrator' });
    await db.update({ [`roles/${created.uid}`]: 'admin' });
    return { uid: created.uid, created: true, password };
  }

  const role = await db.get(`roles/${user.uid}`);
  if (role && role !== 'user' && role !== 'admin') throw new AdminError(409, `${address} is already a ${role}. Use a different email for the administrator.`);
  if (!resetPassword) {
    throw new AdminError(
      409,
      `An account for ${address} already exists, so its password was not changed and nothing was saved. ` +
        'To make it an administrator and keep its password, run make-admin.js. To give it a new generated password, run this again with --reset-password.',
    );
  }
  const password = makePassword();
  await auth.updateUser(user.uid, { password });
  await db.update({ [`roles/${user.uid}`]: 'admin' });
  return { uid: user.uid, created: false, password };
}
