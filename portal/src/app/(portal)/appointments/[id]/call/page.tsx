'use client';

import { FormEvent, use, useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { firebaseAuth } from '@/lib/firebase';
import { refreshSummary } from '@/lib/events';
import { fmtDateTime, fmtTime } from '@/lib/format';
import type { AppointmentDetail, CallInfo } from '@/lib/types';
import { Badge, Card, Counter, Notice, Spinner } from '@/components/ui';

// The video room is a Jitsi Meet room made by the Baymax server when the request was accepted. Its script is only ever loaded from a
// server listed here (NEXT_PUBLIC_JITSI_DOMAINS, comma separated; default the public meet.jit.si), never from an address in the data.
const ALLOWED = (process.env.NEXT_PUBLIC_JITSI_DOMAINS ?? 'meet.jit.si').split(',').map((d) => d.trim().toLowerCase()).filter(Boolean);
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';

interface JitsiApi {
  addListener(event: string, fn: (...args: unknown[]) => void): void;
  dispose(): void;
}
declare global {
  interface Window {
    JitsiMeetExternalAPI?: new (domain: string, options: Record<string, unknown>) => JitsiApi;
  }
}

function loadScript(domain: string): Promise<void> {
  if (window.JitsiMeetExternalAPI) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = `https://${domain}/external_api.js`;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(`Could not load the video service from ${domain}. Check your internet connection.`));
    document.head.appendChild(s);
  });
}

type Device = 'untested' | 'testing' | 'ok' | 'blocked' | 'missing';

export default function CallPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [info, setInfo] = useState<CallInfo | null>(null);
  const [detail, setDetail] = useState<AppointmentDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [offset, setOffset] = useState(0); // server clock minus this computer's clock
  const [tick, setTick] = useState(0);
  const [camera, setCamera] = useState<Device>('untested');
  const [mic, setMic] = useState<Device>('untested');
  const [phase, setPhase] = useState<'before' | 'joining' | 'in' | 'ended'>('before');
  const [callError, setCallError] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [noteMsg, setNoteMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const [savingNote, setSavingNote] = useState(false);
  const [completing, setCompleting] = useState(false);
  const frame = useRef<HTMLDivElement>(null);
  const jitsi = useRef<JitsiApi | null>(null);
  const joined = useRef(false);
  const token = useRef('');

  const load = useCallback(async () => {
    try {
      const r = await api<CallInfo>(`/appointments/${id}/call`);
      setInfo(r);
      setOffset(r.serverTime - Date.now());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load this call.');
    }
  }, [id]);

  useEffect(() => {
    void load();
    api<AppointmentDetail>(`/appointments/${id}`).then(setDetail).catch(() => undefined);
    const t = setInterval(() => { setTick((n) => n + 1); }, 1000);
    const refresh = setInterval(() => void load(), 30_000);
    return () => { clearInterval(t); clearInterval(refresh); };
  }, [id, load]);

  /** Tells the server the specialist joined or left. A failure to log never blocks the call. */
  const logEvent = useCallback((event: 'joined' | 'left', keepalive = false) => {
    if (keepalive && token.current) {
      void fetch(`${API_URL}/api/appointments/${id}/call/event`, {
        method: 'POST', keepalive: true, headers: { Authorization: `Bearer ${token.current}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ event }),
      }).catch(() => undefined);
      return;
    }
    void api(`/appointments/${id}/call/event`, { method: 'POST', body: { event } }).catch(() => undefined);
  }, [id]);

  const leave = useCallback((keepalive = false) => {
    if (joined.current) {
      joined.current = false;
      logEvent('left', keepalive);
    }
  }, [logEvent]);

  // Closing the tab in the middle of a call still records that the specialist left.
  useEffect(() => {
    const onHide = () => leave(true);
    window.addEventListener('pagehide', onHide);
    return () => {
      window.removeEventListener('pagehide', onHide);
      leave();
      jitsi.current?.dispose();
      jitsi.current = null;
    };
  }, [leave]);

  async function testDevices() {
    if (!info) return;
    setCamera('testing');
    setMic('testing');
    const probe = async (kind: 'video' | 'audio'): Promise<Device> => {
      if (!navigator.mediaDevices?.getUserMedia) return 'missing';
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ [kind]: true });
        stream.getTracks().forEach((t) => t.stop()); // only a check: nothing is recorded or sent
        return 'ok';
      } catch (e) {
        const name = (e as DOMException).name;
        return name === 'NotFoundError' || name === 'OverconstrainedError' ? 'missing' : 'blocked';
      }
    };
    if (info.type === 'video') setCamera(await probe('video')); else setCamera('untested');
    setMic(await probe('audio'));
  }

  async function join() {
    if (!info?.canJoin || !info.room || phase === 'joining' || phase === 'in') return;
    setCallError(null);
    const { domain, room, startMuted } = info.room;
    if (!ALLOWED.includes(domain.toLowerCase())) {
      setCallError(`The video server ${domain} is not one this portal trusts. Ask an administrator to check the meeting server setting.`);
      return;
    }
    setPhase('joining');
    try {
      token.current = (await firebaseAuth().currentUser?.getIdToken()) ?? '';
      await loadScript(domain);
      if (!window.JitsiMeetExternalAPI || !frame.current) throw new Error('The video service did not start.');
      frame.current.innerHTML = '';
      const api_ = new window.JitsiMeetExternalAPI(domain, {
        roomName: room,
        parentNode: frame.current,
        width: '100%',
        height: '100%',
        userInfo: { displayName: info.displayName },
        configOverwrite: { prejoinPageEnabled: false, disableDeepLinking: true, startWithVideoMuted: startMuted, startWithAudioMuted: startMuted, disableInviteFunctions: true },
        interfaceConfigOverwrite: { SHOW_JITSI_WATERMARK: false, MOBILE_APP_PROMO: false },
      });
      jitsi.current = api_;
      api_.addListener('videoConferenceJoined', () => {
        if (!joined.current) {
          joined.current = true;
          logEvent('joined');
        }
        setPhase('in');
      });
      const end = () => {
        leave();
        jitsi.current?.dispose();
        jitsi.current = null;
        setPhase('ended');
        void load();
        api<AppointmentDetail>(`/appointments/${id}`).then(setDetail).catch(() => undefined);
      };
      api_.addListener('videoConferenceLeft', end);
      api_.addListener('readyToClose', end);
    } catch (e) {
      setPhase('before');
      setCallError(e instanceof Error ? e.message : 'Could not start the call.');
    }
  }

  async function saveNotes(e: FormEvent) {
    e.preventDefault();
    if (savingNote || !notes.trim()) return;
    setSavingNote(true);
    setNoteMsg(null);
    try {
      const existing = detail?.appointment.consultation;
      // Keep any prescription already written; only the notes change here.
      await api(`/appointments/${id}/consultation`, { method: 'PUT', body: { notes: notes.trim(), prescription: existing?.prescription ?? '' } });
      setNoteMsg({ tone: 'ok', text: 'Notes saved and shared with the patient.' });
    } catch (err) {
      setNoteMsg({ tone: 'error', text: err instanceof Error ? err.message : 'Could not save the notes.' });
    } finally {
      setSavingNote(false);
    }
  }

  async function complete() {
    setCompleting(true);
    try {
      await api(`/appointments/${id}/status`, { method: 'POST', body: { status: 'completed' } });
      refreshSummary();
      setDetail(await api<AppointmentDetail>(`/appointments/${id}`));
    } catch (err) {
      setCallError(err instanceof Error ? err.message : 'Could not mark the session as completed.');
    } finally {
      setCompleting(false);
    }
  }

  if (error && !info) {
    return (
      <>
        <Link className="link" href={`/appointments/${id}`}>‹ Appointment</Link>
        <Notice tone="error">{error}</Notice>
      </>
    );
  }
  if (!info) return <Spinner label="Checking the video room" />;

  void tick; // re-renders once a second so the countdown moves
  const now = Date.now() + offset;
  const secondsToOpen = Math.max(0, Math.ceil((info.opensAt - now) / 1000));
  const started = now >= info.startAt;
  const alreadyCompleted = detail?.appointment.status === 'completed';
  const chatOnly = info.type === 'chat';
  const deviceLabel = (d: Device, what: string) => (d === 'ok' ? `${what} works` : d === 'blocked' ? `${what} is blocked: allow it in your browser's address bar` : d === 'missing' ? `No ${what.toLowerCase()} was found` : d === 'testing' ? `Checking the ${what.toLowerCase()}…` : `${what} not checked yet`);

  return (
    <>
      <Link className="link" href={`/appointments/${id}`}>‹ Appointment</Link>
      <header className="page-head">
        <div>
          <h1>{chatOnly ? 'Chat session' : 'Video call'} with {info.patientName || 'the patient'}</h1>
          <p className="muted">{fmtDateTime(info.startAt)} – {fmtTime(info.endAt)}</p>
        </div>
        {phase === 'in' && <Badge tone="live">In the call</Badge>}
      </header>

      {callError && <Notice tone="error">{callError}</Notice>}

      {phase === 'in' && !info.canJoin && <Notice>The booked time is over. You can stay in the room until you leave it.</Notice>}

      {!info.canJoin && phase === 'before' && (
        <Card title="The room is not open">
          <p>{info.reason}</p>
          {now < info.opensAt && info.reason.startsWith('The room opens') && (
            <p className="muted">Opens in {Math.floor(secondsToOpen / 60)}:{String(secondsToOpen % 60).padStart(2, '0')}. This page opens it by itself when it is time.</p>
          )}
          <div className="actions">
            <Link className="btn" href={`/appointments/${id}`}>Back to the appointment</Link>
            {chatOnly && <Link className="btn" href={`/messages/${id}`}>Open messages</Link>}
          </div>
        </Card>
      )}

      {info.canJoin && phase === 'before' && (
        <Card title="Before you join">
          <ul className="checklist">
            {!chatOnly && <li className={camera === 'ok' ? 'ok' : camera === 'blocked' || camera === 'missing' ? 'bad' : ''}>{deviceLabel(camera, 'Camera')}</li>}
            <li className={mic === 'ok' ? 'ok' : mic === 'blocked' || mic === 'missing' ? 'bad' : ''}>{deviceLabel(mic, 'Microphone')}</li>
            <li className="ok">The room opened at {fmtTime(info.opensAt)} and stays open until {fmtTime(info.endAt)}</li>
          </ul>
          {chatOnly && <p className="muted">This is a chat-only booking: the room opens with camera and microphone off, and you talk in the room&apos;s chat or in Messages.</p>}
          <div className="actions">
            <button type="button" className="btn" onClick={() => void testDevices()} disabled={camera === 'testing'}>Test camera and microphone</button>
            <button type="button" className="btn btn-primary" onClick={() => void join()}>Join now</button>
          </div>
          <p className="muted small">Joining is recorded (when you joined and left), so the administrator&apos;s figures match the bookings. The call itself is not recorded by Baymax. The public Jitsi server may ask the first person in a room to sign in; use your organisation&apos;s own server in production.</p>
        </Card>
      )}

      <div className="call-grid" hidden={phase !== 'joining' && phase !== 'in'}>
        <div className="call-frame" ref={frame} aria-label="Video call" />
        <div className="stack">
          <Card title="Patient's note">
            <p className="pre">{detail?.appointment.notesForSpecialist || 'The patient did not leave a note.'}</p>
          </Card>
          <Card title="Your notes">
            <form className="stack" onSubmit={saveNotes} noValidate>
              <textarea rows={6} value={notes} onChange={(e) => setNotes(e.target.value)} disabled={!started} placeholder={started ? 'Notes for the patient’s profile' : 'Notes can be saved once the session has started'} aria-label="Notes" />
              <Counter value={notes} max={5000} />
              {noteMsg && <Notice tone={noteMsg.tone}>{noteMsg.text}</Notice>}
              <div><button className="btn btn-primary btn-small" disabled={!started || savingNote || !notes.trim() || notes.length > 5000}>{savingNote ? 'Saving…' : 'Save and share'}</button></div>
            </form>
          </Card>
          {chatOnly && <Link className="btn" href={`/messages/${id}`} target="_blank">Open messages in a new tab</Link>}
        </div>
      </div>

      {phase === 'ended' && (
        <Card title="The call has ended">
          <p>
            {info.summary.joins > 0
              ? `You were in the room for about ${info.summary.minutes} minute${info.summary.minutes === 1 ? '' : 's'}${info.summary.joins > 1 ? ` (${info.summary.joins} joins)` : ''}.`
              : 'You left before the call was recorded.'}
          </p>
          {alreadyCompleted ? (
            <Notice tone="ok">This session is marked as completed.</Notice>
          ) : (
            <div className="actions">
              <button type="button" className="btn btn-primary" disabled={completing || !started} onClick={() => void complete()}>{completing ? 'Saving…' : 'Mark session completed'}</button>
              {info.canJoin && <button type="button" className="btn" onClick={() => setPhase('before')}>Rejoin the call</button>}
              <Link className="btn" href={`/appointments/${id}`}>Write notes and prescription</Link>
            </div>
          )}
        </Card>
      )}
    </>
  );
}
