'use client';

import { FormEvent, use, useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { refreshSummary } from '@/lib/events';
import { fmtDateTime, fmtTime } from '@/lib/format';
import type { ChatMessage, ChatThread } from '@/lib/types';
import { messageProblem } from '@/lib/validate';
import { Card, Counter, Notice, Spinner } from '@/components/ui';

const POLL_MS = 4_000;

/** One conversation. New messages are fetched every few seconds while the page is open (and visible). */
export default function ConversationPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [thread, setThread] = useState<ChatThread | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [text, setText] = useState('');
  const [sendError, setSendError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const newest = useRef(0);
  const bottom = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    if (typeof document !== 'undefined' && document.hidden) return; // nobody is looking: do not mark anything read
    try {
      const since = newest.current;
      const r = await api<ChatThread>(`/chats/${id}${since ? `?since=${since}` : ''}`);
      setThread(r);
      setError(null);
      if (r.messages.length) {
        newest.current = Math.max(newest.current, ...r.messages.map((m) => m.at));
        setMessages((cur) => {
          const seen = new Set(cur.map((m) => m.id));
          return [...cur, ...r.messages.filter((m) => !seen.has(m.id))].sort((a, b) => a.at - b.at);
        });
      }
      refreshSummary();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load this conversation.');
    }
  }, [id]);

  useEffect(() => {
    void load();
    const t = setInterval(() => void load(), POLL_MS);
    const onVisible = () => void load();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(t);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [load]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: 'end' });
  }, [messages.length]);

  async function send(e: FormEvent) {
    e.preventDefault();
    if (sending) return;
    const problem = messageProblem(text);
    if (problem) {
      setSendError(problem);
      return;
    }
    setSending(true);
    setSendError(null);
    try {
      const r = await api<{ message: ChatMessage }>(`/chats/${id}`, { method: 'POST', body: { text: text.trim() } });
      newest.current = Math.max(newest.current, r.message.at);
      setMessages((cur) => (cur.some((m) => m.id === r.message.id) ? cur : [...cur, r.message].sort((a, b) => a.at - b.at)));
      setText('');
    } catch (err) {
      setSendError(err instanceof Error ? err.message : 'Could not send the message.');
    } finally {
      setSending(false);
    }
  }

  if (error && !thread) {
    return (
      <>
        <Link className="link" href="/messages">‹ Messages</Link>
        <Notice tone="error">{error}</Notice>
      </>
    );
  }
  if (!thread) return <Spinner label="Opening the conversation" />;

  const lastMine = [...messages].reverse().find((m) => m.side === 'specialist');
  return (
    <>
      <Link className="link" href="/messages">‹ Messages</Link>
      <header className="page-head">
        <div>
          <h1>{thread.appointment.patientName}</h1>
          <p className="muted">Appointment {fmtDateTime(thread.appointment.startAt)} · <Link className="link" href={`/appointments/${id}`}>Open appointment ›</Link></p>
        </div>
      </header>
      {error && <Notice tone="error">{error} Showing the messages we already had.</Notice>}
      <Card>
        <div className="thread" role="log" aria-live="polite" aria-label="Messages">
          {messages.length === 0 && <p className="muted">No messages yet. Say hello below.</p>}
          {messages.map((m) => (
            <div key={m.id} className={m.side === 'specialist' ? 'bubble mine' : 'bubble'}>
              {m.text}
              <span className="bubble-time">
                {fmtTime(m.at)}{lastMine && m.id === lastMine.id && thread.patientReadAt >= m.at ? ' · Seen' : ''}
              </span>
            </div>
          ))}
          <div ref={bottom} />
        </div>
      </Card>
      {thread.state.canSend ? (
        <form className="stack" onSubmit={send} noValidate>
          {sendError && <Notice tone="error">{sendError}</Notice>}
          <div className="composer">
            <label style={{ flex: 1 }}>
              <span className="sr-only">Message</span>
              <textarea
                value={text}
                rows={2}
                placeholder="Write a message (Enter to send, Shift+Enter for a new line)"
                aria-invalid={sendError ? true : undefined}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                    e.preventDefault();
                    e.currentTarget.form?.requestSubmit();
                  }
                }}
              />
              <Counter value={text} max={1000} />
            </label>
            <button className="btn btn-primary" disabled={sending || !text.trim()}>{sending ? 'Sending…' : 'Send'}</button>
          </div>
          <p className="muted small">Do not send passwords or payment details. For an emergency, tell the patient to call their local emergency number.</p>
        </form>
      ) : (
        <Notice>{thread.state.reason}</Notice>
      )}
    </>
  );
}
