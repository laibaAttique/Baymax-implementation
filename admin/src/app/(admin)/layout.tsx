'use client';

import { useCallback, useEffect, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import { api } from '@/lib/api';
import { SUMMARY_EVENT } from '@/lib/events';
import { Notice, Spinner } from '@/components/ui';
import type { Overview } from '@/lib/types';

const NAV = [
  { href: '/overview', label: 'Overview' },
  { href: '/registrations', label: 'Registrations', badge: true },
  { href: '/specialists', label: 'Specialists' },
];

export default function AdminLayout({ children }: { children: ReactNode }) {
  const { state, signOut } = useAuth();
  const router = useRouter();
  const path = usePathname();
  const [pending, setPending] = useState(0);
  const isAdmin = state.status === 'ready' && state.me.role === 'admin';

  const refreshPending = useCallback(async () => {
    try {
      setPending((await api<Overview>('/admin/overview')).applications.pending);
    } catch {
      // the badge is a convenience
    }
  }, []);

  useEffect(() => {
    if (state.status === 'signedOut') router.replace('/login');
  }, [state.status, router]);

  useEffect(() => {
    if (!isAdmin) return;
    void refreshPending();
    const t = setInterval(() => void refreshPending(), 30_000);
    const now = () => void refreshPending();
    window.addEventListener(SUMMARY_EVENT, now);
    return () => {
      clearInterval(t);
      window.removeEventListener(SUMMARY_EVENT, now);
    };
  }, [isAdmin, refreshPending]);

  useEffect(() => {
    document.title = `${pending > 0 ? `(${pending}) ` : ''}Baymax Admin Panel`;
  }, [pending]);

  if (state.status === 'loading' || state.status === 'signedOut') return <Spinner label="Checking your sign-in" />;
  if (state.status === 'error') {
    return (
      <main className="login-wrap"><div className="login card"><h1>Something went wrong</h1><Notice tone="error">{state.message}</Notice><button className="btn" onClick={() => void signOut()}>Sign out</button></div></main>
    );
  }
  if (state.status !== 'ready' || state.me.role !== 'admin') {
    return (
      <main className="login-wrap">
        <div className="login card">
          <h1>No access</h1>
          <Notice tone="error">This panel is only for Baymax administrators. Specialists sign in to the specialist portal.</Notice>
          <button className="btn" onClick={() => void signOut()}>Sign out</button>
        </div>
      </main>
    );
  }

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden>B</span>
          <div><strong>Baymax</strong><div className="panel-label" data-testid="panel-label">Admin Panel</div></div>
        </div>
        <nav aria-label="Main">
          {NAV.map((n) => (
            <Link key={n.href} href={n.href} className={path.startsWith(n.href) ? 'nav-link active' : 'nav-link'} aria-current={path.startsWith(n.href) ? 'page' : undefined}>
              {n.label}
              {n.badge && pending > 0 && <span className="count" aria-label={`${pending} waiting`}>{pending}</span>}
            </Link>
          ))}
        </nav>
        <div className="sidebar-foot">
          <div className="muted small">{state.me.email}</div>
          <button className="btn btn-small" onClick={() => void signOut()}>Sign out</button>
        </div>
      </aside>
      <main className="content">{children}</main>
    </div>
  );
}
