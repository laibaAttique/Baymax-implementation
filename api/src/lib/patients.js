// A specialist's patients: people who have a real (accepted) appointment with them. Pure functions over normalised appointments.
import { PLAN_EDIT_DAYS } from './plans.js';
import { REAL_STATUSES, appointmentState } from './rules.js';

const DAY = 86_400_000;

/** The appointments a specialist has with one patient that actually took place or are going to. */
export const relatedTo = (list, patientId) => list.filter((a) => a.patientId === patientId && REAL_STATUSES.includes(a.status));

/** Plans can be changed while a confirmed or completed appointment is within [PLAN_EDIT_DAYS] days after its end. */
export function canEditPlans(related, now) {
  return related.some((a) => (a.status === 'confirmed' || a.status === 'completed') && now <= a.endAt + PLAN_EDIT_DAYS * DAY);
}

/** The appointment whose consent window is open right now (so its shared data may be read), if any, newest first. */
export function openSharedAppointment(related, now, need) {
  return [...related]
    .sort((x, y) => y.startAt - x.startAt)
    .find((a) => appointmentState(a, now).canViewShared && (need ? a.shares[need] : a.shares.healthSummary || a.shares.foodLog7d || a.shares.activity30d));
}

/** The "My patients" list: one row per patient, most recent first. [q] matches part of the name. */
export function patientSummaries(list, now, q = '') {
  const needle = q.trim().toLowerCase();
  const groups = new Map();
  for (const a of list) {
    if (!REAL_STATUSES.includes(a.status)) continue;
    if (!groups.has(a.patientId)) groups.set(a.patientId, []);
    groups.get(a.patientId).push(a);
  }
  const rows = [];
  for (const [patientId, items] of groups) {
    items.sort((x, y) => y.startAt - x.startAt);
    const name = items[0].patientName || 'Patient';
    if (needle && !name.toLowerCase().includes(needle)) continue;
    const past = items.filter((a) => a.endAt <= now);
    const next = items.filter((a) => a.status === 'confirmed' && a.startAt > now).sort((x, y) => x.startAt - y.startAt)[0];
    rows.push({
      patientId,
      name,
      appointments: items.length,
      lastVisit: past[0]?.startAt ?? null,
      nextVisit: next?.startAt ?? null,
      notesWritten: items.filter((a) => a.consultation).length,
      canEditPlans: canEditPlans(items, now),
    });
  }
  return rows.sort((x, y) => (y.nextVisit ?? y.lastVisit ?? 0) - (x.nextVisit ?? x.lastVisit ?? 0) || x.name.localeCompare(y.name));
}
