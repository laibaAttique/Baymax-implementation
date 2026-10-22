import { Router } from 'express';
import { HttpError } from '../http.js';
import { requireRole } from '../middleware/auth.js';
import { ID, bodyText, queryChoice, queryRange, queryText, checkParam } from '../lib/validate.js';
import { isListed, normalizeAppointment } from '../lib/rules.js';
import { listAppointments } from '../lib/own.js';
import { PAYMENT_BUCKETS, REFUND_MAX_REASON, REFUND_MIN_REASON, byStart, hasPayment, isExpiredPaidRequest, paymentBucket, paymentRow, refundInbox, refundProblem, refundWrites, summarize } from '../lib/payments.js';

/**
 * Records the refund for every paid request that was never answered before its start time. It is safe to run again and again: a request
 * that already has a refund is skipped. The appointment objects in [list] are updated in place so the caller sees the refund.
 */
export async function settleExpired(db, list, t) {
  const updates = {};
  for (const a of list) {
    if (!isExpiredPaidRequest(a, t)) continue;
    Object.assign(updates, refundWrites(a, t, { reason: 'The request expired before the specialist answered.', by: 'system' }));
    updates[`users/${a.patientId}/inbox/refund-${a.id}`] = refundInbox(a, t, 'Your request was not answered in time.');
    a.refund = { status: a.payment.test ? 'refunded' : 'manual', amount: a.payment.total, at: t, reason: 'The request expired before the specialist answered.', by: 'system' };
  }
  if (Object.keys(updates).length) await db.update(updates);
}

/** The filters shared by the specialist's and the administrator's payment lists. */
function filters(query) {
  const { from, to } = queryRange(query);
  const bucket = queryChoice(query.bucket, 'Status', PAYMENT_BUCKETS);
  const q = queryText(query.q, 'The search', 80).trim().toLowerCase();
  return { from, to, bucket, q };
}

function select(list, f, t) {
  return list.filter((a) => {
    if (!hasPayment(a)) return false;
    if (f.from !== undefined && a.startAt < f.from) return false;
    if (f.to !== undefined && a.startAt >= f.to) return false;
    if (f.bucket && paymentBucket(a, t) !== f.bucket) return false;
    if (f.q && !`${a.patientName} ${a.specialistName}`.toLowerCase().includes(f.q)) return false;
    return true;
  }).sort(byStart);
}

/** A specialist's own payments: what they earned, what is on its way, what was refunded. Never another specialist's. */
export function specialistPaymentRoutes({ db, now }) {
  const router = Router();
  router.get('/', async (req, res) => {
    const t = now();
    const f = filters(req.query);
    const all = await listAppointments(db, req.user.uid);
    await settleExpired(db, all, t);
    const rows = select(all, f, t);
    res.json({ serverTime: t, summary: summarize(rows, t), payments: rows.slice(0, 500).map((a) => paymentRow(a, t)), truncated: rows.length > 500 });
  });
  return router;
}

/** Administrator: every payment on the platform, per-specialist totals, and refunds. */
export function adminPaymentRoutes({ db, now }) {
  const router = Router();
  router.use(requireRole('admin'));
  router.param('id', checkParam(ID, 'appointment'));

  const loadAll = async () => {
    const raw = (await db.get('appointments')) ?? {};
    return Object.entries(raw).map(([id, v]) => normalizeAppointment(id, v)).filter((a) => a && isListed(a));
  };

  router.get('/', async (req, res) => {
    const t = now();
    const f = filters(req.query);
    const specialist = queryText(req.query.specialist, 'The specialist', 128);
    const all = await loadAll();
    await settleExpired(db, all, t);
    const rows = select(all, f, t).filter((a) => !specialist || a.specialistId === specialist);
    const groups = new Map();
    for (const a of rows) {
      if (!groups.has(a.specialistId)) groups.set(a.specialistId, { name: a.specialistName, list: [] });
      groups.get(a.specialistId).list.push(a);
    }
    const bySpecialist = [...groups].map(([specialistId, g]) => ({ specialistId, name: g.name, summary: summarize(g.list, t) }))
      .sort((x, y) => y.summary.gross - x.summary.gross || x.name.localeCompare(y.name));
    res.json({
      serverTime: t,
      summary: summarize(rows, t),
      bySpecialist,
      payments: rows.slice(0, 500).map((a) => ({ ...paymentRow(a, t), patientId: a.patientId })),
      truncated: rows.length > 500,
    });
  });

  /** Records a refund. A test payment goes back at once; a live one is marked for the administrator to return through the gateway. */
  router.post('/:id/refund', async (req, res) => {
    const t = now();
    const raw = await db.get(`appointments/${req.params.id}`);
    const a = raw && normalizeAppointment(req.params.id, raw);
    if (!a || !isListed(a)) throw new HttpError(404, 'Appointment not found.');
    const problem = refundProblem(a);
    if (problem) throw new HttpError(409, problem);
    // An appointment that is still going ahead is not refunded here: the specialist declines or cancels it, which refunds automatically.
    const alive = (a.status === 'requested' && a.startAt > t) || (a.status === 'confirmed' && a.endAt > t);
    if (alive) throw new HttpError(409, 'This appointment has not happened yet. Ask the specialist to decline or cancel it first, which refunds automatically.');
    const reason = bodyText(req.body?.reason, 'The reason', { min: REFUND_MIN_REASON, max: REFUND_MAX_REASON, multiline: false });
    await db.update({
      ...refundWrites(a, t, { reason, by: 'admin' }),
      [`users/${a.patientId}/inbox/refund-${a.id}`]: refundInbox(a, t, 'A Baymax administrator refunded this payment.'),
      [`paymentLog/${a.id}/${db.newKey(`paymentLog/${a.id}`)}`]: { event: 'refund', by: req.user.uid, at: t, reason, amount: a.payment.total },
    });
    const updated = normalizeAppointment(a.id, await db.get(`appointments/${a.id}`));
    res.json({ payment: paymentRow(updated, t) });
  });

  return router;
}
