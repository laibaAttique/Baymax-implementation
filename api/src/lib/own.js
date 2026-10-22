import { notFound } from '../http.js';
import { isListed, normalizeAppointment } from './rules.js';

/** Every appointment a specialist can see (held bookings still waiting for payment are not appointments yet). */
export async function listAppointments(db, specialistId) {
  const raw = await db.byChild('appointments', 'specialistId', specialistId);
  return Object.entries(raw).map(([id, v]) => normalizeAppointment(id, v)).filter((a) => a && isListed(a));
}

/** One of the specialist's own appointments. Someone else's looks exactly like one that does not exist. */
export async function ownAppointment(db, specialistId, id) {
  const raw = await db.get(`appointments/${id}`);
  if (!raw || raw.specialistId !== specialistId) throw notFound('Appointment not found.');
  const a = normalizeAppointment(id, raw);
  if (!a || !isListed(a)) throw notFound('Appointment not found.');
  return a;
}
