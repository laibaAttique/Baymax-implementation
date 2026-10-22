import { Router } from 'express';
import { forbidden } from '../http.js';
import { ID, checkParam } from '../lib/validate.js';
import { LIST_DAYS, PAGE_SIZE, byActivity, chatState, conversationRow, messageInbox, messageList, parseMessage, unreadFor } from '../lib/chat.js';
import { makeLimiter } from '../lib/limiter.js';
import { listAppointments, ownAppointment } from '../lib/own.js';

const DAY = 86_400_000;

/** Appointments that have (or can have) a conversation, newest activity first is decided by the caller. */
const chatCandidates = (list, now) => list.filter((a) => chatState(a, now).canRead && a.endAt > now - LIST_DAYS * DAY);

/** The number of patient messages this specialist has not opened. Used by the menu badge and the overview card. */
export async function unreadTotal(db, list, uid, now) {
  let total = 0;
  for (const a of chatCandidates(list, now)) {
    const [raw, readAt] = await Promise.all([db.get(`chats/${a.id}`), db.get(`chatRead/${a.id}/${uid}`)]);
    total += unreadFor(messageList(raw), readAt);
  }
  return total;
}

/**
 * Client messages for a specialist. A conversation belongs to one accepted appointment and only that appointment's specialist can open
 * it (anyone else's looks like one that does not exist). The patient's phone writes its own messages to the database directly; the
 * database rules check them. A specialist's messages are written here so they are validated on the server.
 */
export function chatRoutes({ db, now }) {
  const router = Router();
  router.param('id', checkParam(ID, 'appointment'));
  // 20 messages a minute per specialist and conversation is far more than a person types, and stops a stuck script.
  const sendLimit = makeLimiter({ limit: 20, windowMs: 60_000, now });

  router.get('/', async (req, res) => {
    const t = now();
    const list = chatCandidates(await listAppointments(db, req.user.uid), t);
    const rows = [];
    for (const a of list) {
      const [raw, readAt] = await Promise.all([db.get(`chats/${a.id}`), db.get(`chatRead/${a.id}/${req.user.uid}`)]);
      rows.push(conversationRow(a, raw, readAt, t));
    }
    rows.sort(byActivity);
    res.json({ serverTime: t, conversations: rows.slice(0, 100), unreadTotal: rows.reduce((n, r) => n + r.unread, 0) });
  });

  /** Opens the conversation. Opening it marks the patient's messages as read. `since` (ms) returns only newer messages, for polling. */
  router.get('/:id', async (req, res) => {
    const t = now();
    const a = await ownAppointment(db, req.user.uid, req.params.id);
    const state = chatState(a, t);
    if (!state.canRead) throw forbidden(state.reason);
    const since = Number(req.query.since);
    const [raw, patientReadAt] = await Promise.all([db.get(`chats/${a.id}`), db.get(`chatRead/${a.id}/${a.patientId}`)]);
    const all = messageList(raw);
    const messages = (Number.isFinite(since) && since > 0 ? all.filter((m) => m.at > since) : all).slice(-PAGE_SIZE);
    // Only a person who actually opened the conversation marks it read.
    await db.update({ [`chatRead/${a.id}/${req.user.uid}`]: t });
    res.json({
      serverTime: t,
      appointment: { id: a.id, patientName: a.patientName || 'Patient', type: a.type, status: a.status, startAt: a.startAt, endAt: a.endAt },
      state,
      messages,
      patientReadAt: patientReadAt ?? 0,
    });
  });

  router.post('/:id', async (req, res) => {
    const t = now();
    const a = await ownAppointment(db, req.user.uid, req.params.id);
    const state = chatState(a, t);
    if (!state.canSend) throw forbidden(state.reason);
    const text = parseMessage(req.body);
    sendLimit.hit(`${req.user.uid}:${a.id}`, 'You are sending messages too quickly. Please wait a moment.');
    const key = db.newKey(`chats/${a.id}`);
    const message = { from: req.user.uid, side: 'specialist', text, at: t };
    await db.update({
      [`chats/${a.id}/${key}`]: message,
      [`chatRead/${a.id}/${req.user.uid}`]: t,
      [`users/${a.patientId}/inbox/chat-${a.id}`]: messageInbox(a, text, t),
    });
    res.status(201).json({ message: { id: key, side: 'specialist', text, at: t } });
  });

  return router;
}
