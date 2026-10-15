import { HttpError, forbidden } from '../http.js';
import { SPECIALIST_ROLES } from '../lib/rules.js';

/**
 * Checks the Firebase ID token the web app sends as `Authorization: Bearer <token>`, then reads the person's role from
 * `roles/{uid}` in the database. Roles can only be set by an administrator (the database rules refuse every write from a client),
 * so nobody can promote themselves. A missing role is a plain member and is turned away from the portal.
 */
export function authenticate({ auth, db }) {
  return async (req, _res, next) => {
    const header = req.get('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!token) throw new HttpError(401, 'Please sign in.');
    let decoded;
    try {
      decoded = await auth.verifyIdToken(token);
    } catch {
      throw new HttpError(401, 'Your session has expired. Please sign in again.');
    }
    const role = await db.get(`roles/${decoded.uid}`);
    req.user = { uid: decoded.uid, email: decoded.email ?? '', role: typeof role === 'string' ? role : 'user' };
    next();
  };
}

/** Only these roles may continue; anyone else gets 403 even if they type the address by hand (FR10.9, FR11.9, FR12.9). */
export function requireRole(...roles) {
  return (req, _res, next) => {
    if (!roles.includes(req.user?.role)) throw forbidden('This area is only for Baymax specialists.');
    next();
  };
}

export const requireSpecialist = requireRole(...SPECIALIST_ROLES);
