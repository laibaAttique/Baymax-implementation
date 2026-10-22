'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { api } from '@/lib/api';
import { refreshSummary } from '@/lib/events';
import { fmtDateTime } from '@/lib/format';
import type { Conversation } from '@/lib/types';
import { Badge, Card, Notice, Spinner } from '@/components/ui';

/** Client messages: one conversation per accepted appointment, newest activity first. */
export default function MessagesPage() {
  const [list, setList] = useState<Conversation[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setList((await api<{ conversations: Conversation[] }>('/chats')).conversations);
      setError(null);
      refreshSummary();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not load your messages.');
    }
  }, []);

  useEffect(() => {
    void load();
    const t = setInterval(() => void load(), 15_000);
    return () => clearInterval(t);
  }, [load]);

  return (
    <>
      <header className="page-head">
        <div>
          <h1>Messages</h1>
          <p className="muted">Talk to patients whose appointment you accepted. A conversation stays open until 24 hours after the session.</p>
        </div>
      </header>
      {error && <Notice tone="error">{error}</Notice>}
      {!list && !error && <Spinner label="Loading messages" />}
      {list && (
        <Card title={`${list.length} conversation${list.length === 1 ? '' : 's'}`}>
          {list.length === 0 ? (
            <p className="muted">No conversations yet. One starts when you accept a patient&apos;s request.</p>
          ) : (
            <ul className="convo-list">
              {list.map((c) => (
                <li key={c.appointmentId}>
                  <Link href={`/messages/${c.appointmentId}`} className="convo">
                    <span className="convo-name">{c.patientName}</span>
                    {c.unread > 0 ? <span className="unread-dot" aria-label={`${c.unread} unread`}>{c.unread}</span> : <span className="muted small">{c.canSend ? '' : 'Closed'}</span>}
                    <span className="convo-last">{c.last ? `${c.last.side === 'specialist' ? 'You: ' : ''}${c.last.text}` : `No messages yet · appointment ${fmtDateTime(c.startAt)}`}</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
      <p className="muted small"><Badge>Plain text only</Badge> Messages are limited to 1000 characters and links are not clickable, so nobody can be sent to a fake page from a chat.</p>
    </>
  );
}
