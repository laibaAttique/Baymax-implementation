// Client messages (the "Client Messages" menu of the nutritionist and trainer panels, FR11.9 and FR12.9): a text conversation between a
// patient and the specialist, tied to one appointment. Pure functions: no database, no clock of their own.
//
// Data (Realtime Database):  chats/{appointmentId}/{messageKey} = { from: uid, side: 'patient'|'specialist', text, at }
//                            chatRead/{appointmentId}/{uid}     = ms of the last time that person opened the conversation
// The patient's phone writes its own messages straight to the database (the rules check it); a specialist's messages go through this API.
import { bodyText } from './validate.js';

const HOUR = 3_600_000;

export const MAX_MESSAGE = 1000;
/** A conversation stays open for new messages this long after the slot ends, so follow-up questions can be asked and answered. */
export const CHAT_GRACE_MS = 24 * HOUR;
/** The newest messages sent back in one answer. */
export const PAGE_SIZE = 200;
/** Conversations older than this (days after the session) are left out of the list; they can still be opened by address. */
export const LIST_DAYS = 90;

/**
 * Whether a conversation can be read and written to right now.
 *  - Only an accepted appointment (confirmed, completed, or missed) has a conversation; a request waiting for an answer, a declined or a
 *    cancelled one does not.
 *  - Messages can be sent from the moment of acceptance until 24 hours after the slot ends.
 */
export function chatState(a, now) {
  if (a.status === 'requested') return { canRead: false, canSend: false, reason: 'Accept the request to start the conversation.' };
  if (a.status === 'cancelled' || a.status === 'declined') return { canRead: false, canSend: false, reason: `This appointment was ${a.status}, so there is no conversation.` };
  if (!['confirmed', 'completed', 'no_show'].includes(a.status)) return { canRead: false, canSend: false, reason: 'There is no conversation for this appointment.' };
  if (now >= a.endAt + CHAT_GRACE_MS) return { canRead: true, canSend: false, reason: 'This conversation is closed. It stays open for 24 hours after the session.' };
  return { canRead: true, canSend: true, reason: '' };
}

/** Checks the text of a new message. Throws a 400 with a message the person can act on. */
export function parseMessage(body) {
  return bodyText(body?.text, 'The message', { min: 1, max: MAX_MESSAGE });
}

/** The stored messages as a clean, ordered list. Anything malformed (a hand-edited record) is dropped, never shown. */
export function messageList(raw) {
  return Object.entries(raw ?? {})
    .filter(([, m]) => m && typeof m.text === 'string' && m.text.length > 0 && Number.isFinite(m.at) && (m.side === 'patient' || m.side === 'specialist'))
    .map(([id, m]) => ({ id, side: m.side, text: m.text.slice(0, MAX_MESSAGE), at: m.at }))
    .sort((x, y) => x.at - y.at || x.id.localeCompare(y.id));
}

/** How many messages from the patient the specialist has not opened yet. */
export const unreadFor = (messages, readAt) => messages.filter((m) => m.side === 'patient' && m.at > (readAt ?? 0)).length;

/**
 * One row of the conversation list: the appointment, the last message, and how many are unread. [rawMessages] and [readAt] are what
 * the database holds for this appointment.
 */
export function conversationRow(a, rawMessages, readAt, now) {
  const messages = messageList(rawMessages);
  const last = messages[messages.length - 1] ?? null;
  const state = chatState(a, now);
  return {
    appointmentId: a.id,
    patientId: a.patientId,
    patientName: a.patientName || 'Patient',
    type: a.type,
    status: a.status,
    startAt: a.startAt,
    canSend: state.canSend,
    last: last && { text: last.text.slice(0, 120), at: last.at, side: last.side },
    unread: unreadFor(messages, readAt),
    messageCount: messages.length,
  };
}

/** Newest activity first; a conversation with no messages yet is ordered by its appointment time. */
export const byActivity = (x, y) => (y.last?.at ?? y.startAt) - (x.last?.at ?? x.startAt) || x.appointmentId.localeCompare(y.appointmentId);

/** The inbox notice that tells the patient a specialist wrote to them. One notice per conversation, replaced by each new message. */
export function messageInbox(a, text, t) {
  return {
    type: 'appointment',
    title: `New message from ${a.specialistName || 'your specialist'}`,
    body: text.length > 100 ? `${text.slice(0, 97)}...` : text,
    createdAt: t,
    read: false,
    route: 'appointments',
  };
}
