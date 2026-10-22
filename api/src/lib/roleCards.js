// The four summary cards on each specialist's overview (FR10.3, FR11.3, FR12.3). Only numbers the stored data can honestly give:
// "High-Risk Alerts", "Clients on Track" and "Form Correction Flags" need the AI engine's output, which is not connected to the portal.
import { REAL_STATUSES } from './rules.js';

const DAY = 86_400_000;

/** People with a real appointment that ended in the last 30 days or has not happened yet. */
export function activeClientIds(all, now) {
  return [...new Set(all.filter((a) => REAL_STATUSES.includes(a.status) && a.endAt > now - 30 * DAY).map((a) => a.patientId))];
}

/** Sessions that ended in the last 30 days and have no prescription yet (doctors only). */
export function pendingPrescriptions(all, now) {
  return all.filter((a) => (a.status === 'completed' || (a.status === 'confirmed' && a.endAt <= now)) && a.endAt > now - 30 * DAY && !a.consultation?.prescription).length;
}

/** Accepted video calls that have not ended and start within a week. */
export function upcomingVideo(all, now) {
  return all.filter((a) => a.status === 'confirmed' && a.type === 'video' && a.endAt > now && a.startAt < now + 7 * DAY).length;
}

/**
 * [extra] holds what needs the database: `unreadMessages`, `dietReviewsWaiting` (nutritionist) and `workoutsToReview` (trainer).
 * Each card is { key, label, value, hint, warn }.
 */
export function roleCards(role, { all, now, counts, extra }) {
  const messages = { key: 'messages', label: 'Unread messages', value: extra.unreadMessages ?? 0, hint: 'From patients, in Messages', warn: (extra.unreadMessages ?? 0) > 0 };
  if (role === 'doctor') {
    const pending = pendingPrescriptions(all, now);
    return [
      { key: 'patients', label: 'Total patients', value: counts.patients, hint: 'With an accepted appointment', warn: false },
      { key: 'today', label: 'Consultations today', value: counts.consultationsToday, hint: 'Accepted, starting today', warn: false },
      { key: 'prescriptions', label: 'Pending prescriptions', value: pending, hint: 'Sessions in the last 30 days with no prescription', warn: pending > 0 },
      messages,
    ];
  }
  if (role === 'nutritionist') {
    const waiting = extra.dietReviewsWaiting ?? 0;
    return [
      { key: 'dietReviews', label: 'Pending diet reviews', value: waiting, hint: 'Patients whose shared food log is open and has unreviewed days', warn: waiting > 0 },
      { key: 'video', label: 'Video consultations', value: upcomingVideo(all, now), hint: 'Accepted, next 7 days', warn: false },
      { key: 'clients', label: 'Active clients', value: activeClientIds(all, now).length, hint: 'Seen in the last 30 days or booked', warn: false },
      messages,
    ];
  }
  const toReview = extra.workoutsToReview ?? 0;
  return [
    { key: 'workouts', label: 'Workouts to review', value: toReview, hint: 'Active trainees whose plan you have not reviewed', warn: toReview > 0 },
    { key: 'video', label: 'Video consultations', value: upcomingVideo(all, now), hint: 'Accepted, next 7 days', warn: false },
    { key: 'trainees', label: 'Active trainees', value: activeClientIds(all, now).length, hint: 'Seen in the last 30 days or booked', warn: false },
    messages,
  ];
}
