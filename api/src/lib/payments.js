// Module 15 on the web: what a specialist earned, what the platform collected, and refunds. Pure functions over normalised
// appointments (lib/rules.js). The gateway is the app's TEST gateway: a "refund" here returns sandbox money, so nothing real moves.

export const PAYMENT_BUCKETS = ['held', 'upcoming', 'earned', 'clinic', 'due', 'refunded'];

/** Appointments that carry a payment record, or a refund. */
export const hasPayment = (a) => !!a.payment || !!a.refund;

/**
 * Where a payment stands for the specialist and for the administrator:
 *  - refunded: the money went back to the patient.
 *  - held: paid, but the request is still waiting for the specialist's answer.
 *  - upcoming: paid, accepted, and the session has not ended.
 *  - earned: paid and the session took place (or its time has passed).
 *  - due: paid, but the appointment was cancelled, declined or never answered, and no refund has been recorded yet.
 *  - clinic: the patient pays at the visit; nothing was taken online.
 *  - void: a pay-at-clinic appointment that did not go ahead; nothing is owed.
 */
export function paymentBucket(a, now) {
  if (a.refund) return 'refunded';
  if (!a.payment) return 'unpaid';
  const dead = a.status === 'cancelled' || a.status === 'declined' || (a.status === 'requested' && a.startAt <= now);
  if (a.payment.status === 'pay_at_clinic') return dead ? 'void' : 'clinic';
  if (dead) return 'due';
  if (a.status === 'requested') return 'held';
  if (a.status === 'confirmed' && a.endAt > now) return 'upcoming';
  return 'earned';
}

/** One row of a payments table. Never card details: only the method and the transaction reference. */
export function paymentRow(a, now) {
  return {
    appointmentId: a.id,
    patientName: a.patientName,
    specialistId: a.specialistId,
    specialistName: a.specialistName,
    startAt: a.startAt,
    status: a.status,
    type: a.type,
    bucket: paymentBucket(a, now),
    payment: a.payment,
    refund: a.refund,
  };
}

/** Totals for a list of appointments, in PKR. The specialist's share is the consultation fee; the platform fee belongs to Baymax. */
export function summarize(list, now) {
  const out = {
    count: 0,
    earned: { count: 0, amount: 0 },
    upcoming: { count: 0, amount: 0 },
    held: { count: 0, amount: 0 },
    clinicDue: { count: 0, amount: 0 },
    due: { count: 0, amount: 0 },
    refunded: { count: 0, amount: 0 },
    platformFees: 0,
    gross: 0,
    testPayments: 0,
  };
  for (const a of list) {
    if (!hasPayment(a)) continue;
    out.count++;
    const bucket = paymentBucket(a, now);
    const p = a.payment;
    if (bucket === 'refunded') {
      out.refunded.count++;
      out.refunded.amount += a.refund.amount || p?.total || 0;
      continue;
    }
    if (!p) continue;
    if (p.test) out.testPayments++;
    if (bucket === 'void') continue;
    if (bucket === 'due') {
      out.due.count++;
      out.due.amount += p.total;
      continue;
    }
    if (bucket === 'clinic') {
      out.clinicDue.count++;
      out.clinicDue.amount += p.consultationFee || p.total;
      continue;
    }
    const share = p.consultationFee || p.total - p.platformFee;
    if (bucket === 'earned' || bucket === 'upcoming' || bucket === 'held') {
      out[bucket].count++;
      out[bucket].amount += share;
      out.platformFees += p.platformFee;
      out.gross += p.total;
    }
  }
  return out;
}

/** Why a payment cannot be refunded now, or null. */
export function refundProblem(a) {
  if (!a.payment) return 'This appointment has no payment.';
  if (a.refund) return 'This payment was already refunded.';
  if (a.payment.status !== 'paid') return 'Nothing was taken online for this appointment, so there is nothing to refund.';
  return null;
}

/**
 * The database writes that record a refund on an appointment, or {} if none applies. A sandbox payment is returned at once. A live
 * payment is marked `manual`: an administrator must return it through the gateway, because this server holds no gateway keys.
 */
export function refundWrites(a, t, { reason, by }) {
  if (refundProblem(a)) return {};
  return {
    [`appointments/${a.id}/refund`]: {
      status: a.payment.test ? 'refunded' : 'manual',
      amount: a.payment.total,
      at: t,
      reason: String(reason).slice(0, 200),
      by,
    },
  };
}

/** A request that was paid for but never answered before its start time: its money goes back too. */
export const isExpiredPaidRequest = (a, now) => a.status === 'requested' && a.startAt <= now && a.payment?.status === 'paid' && !a.refund;

/** The inbox message that tells the patient about a refund. */
export function refundInbox(a, t, why) {
  const sandbox = a.payment?.test !== false;
  return {
    type: 'appointment',
    title: 'Your payment was refunded',
    body: `${why} PKR ${a.payment.total.toLocaleString('en-US')} ${sandbox ? 'was returned (test payment: no real money moved).' : 'will be returned to you. Baymax support will contact you.'}`.slice(0, 240),
    createdAt: t,
    read: false,
    route: 'appointments',
  };
}

export const REFUND_MIN_REASON = 3;
export const REFUND_MAX_REASON = 200;

/** Newest first, then a stable order. */
export const byStart = (x, y) => y.startAt - x.startAt || x.id.localeCompare(y.id);
