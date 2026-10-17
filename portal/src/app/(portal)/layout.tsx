'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import { api } from '@/lib/api';
import { SUMMARY_EVENT } from '@/lib/events';
import { Card, Notice, Spinner } from '@/components/ui';
import { ApplicationForm } from '@/components/ApplicationForm';
import { fmtDateTime } from '@/lib/format';

const SPECIALIST_NAV = [
  { href: '/dashboard', label: 'Overview', badge: true },
  { href: '/appointments', label: 'Appointments' },
  { href: '/patients', label: 'My patients' },
  { href: '/prescriptions', label: 'Prescriptions', only: 'doctor' },
  { href: '/settings', label: 'My profile' },
];

/** New requests waiting for an answer, checked every 30 seconds. A desktop alert fires when a new one arrives (if allowed). */
function useRequestCount(enabled: boolean) {
  const [count, setCount] = useState(0);
  const last = useRef(0);
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    const check = async () => {
      try {
        const r = await api<{ pendingRequests: number }>('/summary');
        if (!alive) return;
        if (r.pendingRequests > last.current && last.current >= 0 && typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          new Notification('Baymax: new appointment request', { body: `${r.pendingRequests} request${r.pendingRequests === 1 ? '' : 's'} waiting for your answer.` });
        }
        last.current = r.pendingRequests;
        setCount(r.pendingRequests);
      } catch {
        // the menu badge is a convenience; a failed check is simply skipped
      }
    };
    void check();
    const t = setInterval(() => void check(), 30_000);
    const now = () => void check();
    window.addEventListener(SUMMARY_EVENT, now);
    return () => {
      alive = false;
      clearInterval(t);
      window.removeEventListener(SUMMARY_EVENT, now);
    };
  }, [enabled]);
  useEffect(() => {
    document.title = `${count > 0 ? `(${count}) ` : ''}Baymax Specialist Portal`;
  }, [count]);
  return count;
}

export default function PortalLayout({ children }: { children: ReactNode }) {
  const { state, signOut } = useAuth();
  const router = useRouter();
  const path = usePathname();
  const isSpecialist = state.status === 'ready' && ['doctor', 'nutritionist', 'trainer'].includes(state.me.role);
  const requestCount = useRequestCount(isSpecialist);
  const [alertsAllowed, setAlertsAllowed] = useState(typeof Notification !== 'undefined' && Notification.permission === 'granted');

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
  // Signed in but not a specialist yet: registration, or the state of the registration.
  if (me.role === 'user') return <ApplicantScreen />;
  // Administrators use their own panel, a separate app; nothing in this portal is for them.
  if (me.role === 'admin') return <AdminElsewhere />;
  const nav = SPECIALIST_NAV;
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden>B</span>
          <div>
            <strong>Baymax</strong>
            <div className="panel-label" data-testid="panel-label">{`${me.roleLabel} Panel`}</div>
          </div>
        </div>
        <nav aria-label="Main">
          {nav.filter((n) => !n.only || n.only === me.role).map((n) => (
            <Link key={n.href} href={n.href} className={path.startsWith(n.href) ? 'nav-link active' : 'nav-link'} aria-current={path.startsWith(n.href) ? 'page' : undefined}>
              {n.label}
              {n.badge && requestCount > 0 && <span className="count" aria-label={`${requestCount} new requests`}>{requestCount}</span>}
            </Link>
          ))}
        </nav>
        <div className="sidebar-foot">
          {isSpecialist && typeof Notification !== 'undefined' && !alertsAllowed && Notification.permission !== 'denied' && (
            <button className="btn btn-small" onClick={() => void Notification.requestPermission().then((p) => setAlertsAllowed(p === 'granted'))}>Turn on desktop alerts</button>
          )}
          <div className="muted small">{me.profile?.name ?? me.roleLabel}</div>
          <div className="muted small">{me.email}</div>
          <button className="btn btn-small" onClick={() => void signOut()}>Sign out</button>
        </div>
      </aside>
      <main className="content">{children}</main>
    </div>
  );
}


/** An administrator who signed in here is pointed to the admin panel. */
function AdminElsewhere() {
  const { signOut } = useAuth();
  const url = process.env.NEXT_PUBLIC_ADMIN_URL ?? 'http://localhost:3001';
  return (
    <main className="waiting">
      <div className="brand brand-lg">
        <span className="brand-mark" aria-hidden>B</span>
        <div><strong>Baymax</strong><span className="muted"> Specialist Portal</span></div>
      </div>
      <Card title="You are an administrator">
        <p>Administrators work in the Baymax admin panel, which is a separate web app: approve registrations and manage specialists there.</p>
        <div className="actions">
          <a className="btn btn-primary" href={url}>Open the admin panel</a>
          <button className="btn" onClick={() => void signOut()}>Sign out</button>
        </div>
      </Card>
    </main>
  );
}

/** What a signed-in person who is not a specialist sees: the registration form, or where their registration stands. */
function ApplicantScreen() {
  const { state, signOut, refreshMe } = useAuth();
  const [editing, setEditing] = useState(false);
  const me = state.status === 'ready' ? state.me : null;
  const app = me?.application ?? null;

  // While waiting, check again every 30 seconds so approval shows up without a refresh.
  useEffect(() => {
    if (app?.status !== 'pending') return;
    const t = setInterval(() => void refreshMe(), 30_000);
    return () => clearInterval(t);
  }, [app?.status, refreshMe]);

  if (!me) return null;
  const showForm = !app || (app.status === 'rejected' && editing) || editing;

  return (
    <main className="waiting">
      <div className="brand brand-lg">
        <span className="brand-mark" aria-hidden>B</span>
        <div><strong>Baymax</strong><span className="muted"> Specialist Portal</span></div>
      </div>
      <p className="muted small">Signed in as {me.email}</p>

      {!app && !showForm && null}
      {!app && <h1>Register as a specialist</h1>}
      {!app && <p className="muted">This account is not a specialist account yet. Send your professional details; an administrator checks your licence number before you can use the portal or appear in the app.</p>}

      {app?.status === 'pending' && !editing && (
        <Card title="Registration received">
          <p>Thank you, {app.name}. Your registration as a {app.type} ({app.specialty}) was sent {fmtDateTime(app.submittedAt)} and is waiting for an administrator to check it.</p>
          <p className="muted small">This page checks again by itself. You can close it and sign in later.</p>
          <div className="actions">
            <button className="btn btn-small" onClick={() => void refreshMe()}>Check now</button>
            <button className="btn btn-small" onClick={() => setEditing(true)}>Change my details</button>
          </div>
        </Card>
      )}
      {app?.status === 'rejected' && !editing && (
        <Card title="Registration not approved">
          <p>{app.rejectReason ? `Reason: ${app.rejectReason}` : 'An administrator could not approve this registration.'}</p>
          <div><button className="btn btn-primary" onClick={() => setEditing(true)}>Correct my details and send again</button></div>
        </Card>
      )}
      {showForm && (
        <ApplicationForm
          initialName={app?.name ?? ''}
          onSubmitted={async () => {
            setEditing(false);
            await refreshMe();
          }}
        />
      )}
      <div className="actions">
        <button className="btn btn-small" onClick={() => void signOut()}>Sign out</button>
        {app && (
          <button className="btn btn-small btn-danger" onClick={async () => {
            if (!window.confirm('Withdraw your registration? Your sign-in account stays, only the registration is removed.')) return;
            await api('/applications', { method: 'DELETE' }).catch(() => undefined);
            setEditing(false);
            await refreshMe();
          }}>Withdraw my registration</button>
        )}
      </div>
    </main>
  );
}
