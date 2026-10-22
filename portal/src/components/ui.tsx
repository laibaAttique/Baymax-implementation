import type { ReactNode } from 'react';
import { statusLabel } from '@/lib/format';
import type { Appointment } from '@/lib/types';

export function Badge({ tone = 'neutral', children }: { tone?: 'neutral' | 'good' | 'warn' | 'bad' | 'live' | 'info'; children: ReactNode }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

export function StatusBadge({ a }: { a: Appointment }) {
  if (a.phase === 'live') return <Badge tone="live">Live now</Badge>;
  if (a.phase === 'requested') return <Badge tone="warn">Awaiting your answer</Badge>;
  if (a.phase === 'expired') return <Badge tone="neutral">Expired</Badge>;
  if (a.phase === 'declined') return <Badge tone="bad">Declined</Badge>;
  const tone = a.status === 'confirmed' ? 'info' : a.status === 'completed' ? 'good' : a.status === 'cancelled' ? 'bad' : 'warn';
  return <Badge tone={tone}>{statusLabel(a.status)}</Badge>;
}

export function PaymentBadge({ a }: { a: Appointment }) {
  if (a.refund) return <Badge tone="neutral">{a.refund.status === 'manual' ? 'Refund due' : 'Refunded'}</Badge>;
  if (!a.payment && a.status === 'requested') return <Badge tone="warn">Payment unknown</Badge>;
  if (!a.payment) return <Badge tone="warn">Payment unknown</Badge>;
  if (a.payment.status === 'pay_at_clinic') return <Badge tone="warn">Pay at clinic</Badge>;
  return <Badge tone="good">{a.payment.test ? 'Paid (test)' : 'Paid'}</Badge>;
}

export function Card({ title, action, children }: { title?: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="card">
      {(title || action) && (
        <header className="card-head">
          {title && <h2>{title}</h2>}
          {action}
        </header>
      )}
      {children}
    </section>
  );
}

export function Notice({ tone = 'info', children }: { tone?: 'info' | 'error' | 'ok'; children: ReactNode }) {
  return (
    <div className={`notice notice-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>
      {children}
    </div>
  );
}

export function Spinner({ label = 'Loading' }: { label?: string }) {
  return (
    <div className="center" role="status" aria-live="polite">
      <div className="spinner" aria-hidden />
      <span className="muted">{label}…</span>
    </div>
  );
}

/** A form field with its label, a hint, and the problem with it (if any) shown right under it. */
export function Field({ label, error, hint, children }: { label: string; error?: string | null; hint?: string; children: ReactNode }) {
  return (
    <label className={error ? 'field field-bad' : 'field'}>
      {label}
      {children}
      {hint && !error && <span className="field-hint">{hint}</span>}
      {error && <span className="field-error" role="alert">{error}</span>}
    </label>
  );
}

/** "412 / 600" under a text box, turning red when it is over. */
export function Counter({ value, max }: { value: string; max: number }) {
  return <span className={value.length > max ? 'field-error' : 'field-hint'} aria-live="polite">{value.length} / {max}</span>;
}
