'use client';

import { useEffect, type ReactNode } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import { Notice, Spinner } from '@/components/ui';

const NAV = [
  { href: '/dashboard', label: 'Overview' },
  { href: '/appointments', label: 'Appointments' },
  { href: '/settings', label: 'My profile' },
];

export default function PortalLayout({ children }: { children: ReactNode }) {
  const { state, signOut } = useAuth();
  const router = useRouter();
  const path = usePathname();

  useEffect(() => {
    if (state.status === 'signedOut') router.replace('/login');
  }, [state.status, router]);

  if (state.status === 'loading' || state.status === 'signedOut') return <Spinner label="Checking your sign-in" />;

  if (state.status === 'denied' || state.status === 'error') {
    return (
      <main className="login-wrap">
        <div className="login card">
          <h1>{state.status === 'denied' ? 'No access' : 'Something went wrong'}</h1>
          <Notice tone="error">{state.message}</Notice>
          <button className="btn" onClick={() => void signOut()}>Sign out</button>
        </div>
      </main>
    );
  }

  const { me } = state;
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden>B</span>
          <div>
            <strong>Baymax</strong>
            <div className="panel-label" data-testid="panel-label">{me.roleLabel} Panel</div>
          </div>
        </div>
        <nav aria-label="Main">
          {NAV.map((n) => (
            <Link key={n.href} href={n.href} className={path.startsWith(n.href) ? 'nav-link active' : 'nav-link'} aria-current={path.startsWith(n.href) ? 'page' : undefined}>
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="sidebar-foot">
          <div className="muted small">{me.profile.name}</div>
          <div className="muted small">{me.email}</div>
          <button className="btn btn-small" onClick={() => void signOut()}>Sign out</button>
        </div>
      </aside>
      <main className="content">{children}</main>
    </div>
  );
}

