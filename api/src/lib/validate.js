// Input checks shared by every route. They run before a route reads the database, so a malformed address, query or body is refused
// with a plain 400 instead of reaching Firebase (which would throw on a path containing . # $ [ ] or /).
import { HttpError, badRequest } from '../http.js';

/** Appointment ids are Firebase push keys (letters, digits, - and _). */
export const ID = /^[A-Za-z0-9_-]{1,64}$/;
/** Firebase Auth user ids. */
export const UID = /^[A-Za-z0-9]{1,128}$/;
/** A calendar day, 2026-10-19. */
export const DAY = /^\d{4}-\d{2}-\d{2}$/;

/** `router.param('id', checkParam(ID, 'appointment'))`: a bad id answers 400 before any handler runs. */
export const checkParam = (pattern, label, message = `That ${label} id is not valid.`) => (_req, _res, next, value) => {
  if (typeof value !== 'string' || !pattern.test(value)) return next(badRequest(message));
  next();
};

/** Request bodies must be a JSON object (not an array, a number or a string). A missing body is fine: it reads as {}. */
export function requireObjectBody(req, _res, next) {
  if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method) && req.body !== undefined && (req.body === null || typeof req.body !== 'object' || Array.isArray(req.body))) {
    return next(badRequest('The request body must be a JSON object.'));
  }
  next();
}

/** A body that has data must say so: `Content-Type: application/json`. Anything else would be silently ignored by the JSON parser. */
export function requireJsonContentType(req, _res, next) {
  const len = Number(req.get('content-length') ?? 0);
  if (['POST', 'PUT', 'PATCH'].includes(req.method) && len > 0 && !req.is('application/json')) {
    return next(new HttpError(415, 'Send the request as application/json.'));
  }
  next();
}

/** An optional whole number from a query string. Empty or missing is `undefined`; anything else that is not an integer is a 400. */
export function queryInt(value, label, { min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER } = {}) {
  if (value === undefined || value === '') return undefined;
  const n = Number(value);
  if (typeof value !== 'string' || !Number.isInteger(n) || n < min || n > max) throw badRequest(`${label} must be a whole number.`);
  return n;
}

/** An optional short text from a query string (a search). Arrays (`?q=a&q=b`) and long strings are refused. */
export function queryText(value, label, max = 80) {
  if (value === undefined) return '';
  if (typeof value !== 'string' || value.length > max) throw badRequest(`${label} must be text of at most ${max} characters.`);
  return value;
}

/** An optional choice from a fixed list. */
export function queryChoice(value, label, allowed) {
  if (value === undefined || value === '') return undefined;
  if (typeof value !== 'string' || !allowed.includes(value)) throw badRequest(`${label} must be one of: ${allowed.join(', ')}.`);
  return value;
}

/** from/to in ms. `to` must not be before `from`. */
export function queryRange(query) {
  const from = queryInt(query.from, 'The start of the date range', { min: 0 });
  const to = queryInt(query.to, 'The end of the date range', { min: 0 });
  if (from !== undefined && to !== undefined && to < from) throw badRequest('The end of the date range is before its start.');
  return { from, to };
}

/** A required piece of text from a body, trimmed, with length limits and no control characters (newlines and tabs are allowed). */
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;
export function bodyText(value, label, { min = 1, max = 1000, multiline = true } = {}) {
  if (typeof value !== 'string') throw badRequest(`${label} must be text.`);
  const text = value.replace(/\r\n/g, '\n').trim();
  if (text.length < min) throw badRequest(min <= 1 ? `${label} cannot be empty.` : `${label} must be at least ${min} characters.`);
  if (text.length > max) throw badRequest(`${label} can be at most ${max} characters.`);
  if (CONTROL.test(text) || (!multiline && /[\n\t]/.test(text))) throw badRequest(`${label} contains characters that are not allowed.`);
  return text;
}
