// The video room (FR-3, FR10.5): who may open it, what the browser is told about it, and the log of who joined.
import { JOIN_EARLY_MS } from './rules.js';

/**
 * Splits a stored meeting link into the parts the Jitsi embed needs. The link is made by this server when a request is accepted, so it
 * must be on the configured meeting server; anything else (an old or hand-edited record) is refused instead of being loaded in the page.
 */
export function parseRoom(link, meetingBase) {
  try {
    const u = new URL(link);
    const base = new URL(meetingBase);
    if (u.protocol !== 'https:' || u.host !== base.host) return null;
    const room = decodeURIComponent(u.pathname.replace(/^\//, ''));
    if (!/^baymax-[a-z0-9]{10,40}$/.test(room)) return null;
    return { domain: u.host, room, startMuted: /startWithVideoMuted=true/.test(u.hash) };
  } catch {
    return null;
  }
}

/**
 * What the call page shows. The room's name is only handed over when the person may join now, so the page cannot open it early.
 * `reason` is what to tell the specialist when they may not.
 */
export function callInfo(a, now, state, meetingBase) {
  const opensAt = a.startAt - JOIN_EARLY_MS;
  const base = { appointmentId: a.id, type: a.type, patientName: a.patientName, startAt: a.startAt, endAt: a.endAt, opensAt, serverTime: now };
  if (a.status === 'requested') return { ...base, canJoin: false, reason: 'Accept the request first. The video room is created when you accept.' };
  if (a.status !== 'confirmed') return { ...base, canJoin: false, reason: `This appointment is ${a.status.replace('_', ' ')}, so there is no call.` };
  if (now < opensAt) return { ...base, canJoin: false, reason: 'The room opens 5 minutes before the start.' };
  if (now >= a.endAt) return { ...base, canJoin: false, reason: 'The session time has passed.' };
  const room = a.meetingLink ? parseRoom(a.meetingLink, meetingBase) : null;
  if (!state.canJoin || !room) return { ...base, canJoin: false, reason: 'This appointment has no valid video room. Ask the patient to book again.' };
  return { ...base, canJoin: true, reason: '', room };
}

export const CALL_EVENTS = ['joined', 'left'];
export const MAX_CALL_EVENTS = 200;

/**
 * Turns the log of joins and leaves into numbers: how many times the specialist joined, when first and last, and the minutes spent in
 * the room. A join with no matching leave counts until the slot ends (a closed tab never says goodbye), but never past it.
 */
export function callSummary(events, endAt) {
  const list = Object.values(events ?? {}).filter((e) => e && CALL_EVENTS.includes(e.event) && Number.isFinite(e.at)).sort((x, y) => x.at - y.at);
  let joins = 0;
  let ms = 0;
  let open = null;
  let firstJoinAt = null;
  let lastLeftAt = null;
  for (const e of list) {
    if (e.event === 'joined') {
      if (open === null) {
        open = e.at;
        joins++;
        firstJoinAt ??= e.at;
      }
    } else if (open !== null) {
      ms += Math.max(0, Math.min(e.at, endAt + JOIN_EARLY_MS) - open);
      lastLeftAt = e.at;
      open = null;
    }
  }
  if (open !== null) ms += Math.max(0, endAt - open);
  return { joins, firstJoinAt, lastLeftAt, minutes: Math.round(ms / 60_000) };
}
