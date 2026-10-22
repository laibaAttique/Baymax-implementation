'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { createUserWithEmailAndPassword } from 'firebase/auth';
import { firebaseAuth, firebaseConfigured } from '@/lib/firebase';
import { useAuth } from '@/lib/auth';
import { emailProblem, passwordProblem } from '@/lib/validate';
import { ApplicationForm } from '@/components/ApplicationForm';
import { Card, Field, Notice } from '@/components/ui';

function friendly(code: string): string {
  switch (code) {
    case 'auth/email-already-in-use':
      return 'An account with this email already exists. Sign in instead: you will be asked for your professional details there.';
    case 'auth/weak-password':
      return 'Choose a longer password (at least 8 characters).';
    case 'auth/invalid-email':
      return 'That email address does not look right.';
    case 'auth/network-request-failed':
      return 'Could not reach Firebase. Check your internet connection.';
    default:
      return 'Could not create your account. Please try again.';
  }
}

/** Specialists register here. This creates the sign-in account; an administrator must approve it before it becomes a specialist. */
export default function RegisterPage() {
  const router = useRouter();
  const { state, refreshMe } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');

  useEffect(() => {
    if (state.status === 'ready') router.replace('/dashboard');
  }, [state.status, router]);

  async function createAccount() {
    const bad = emailProblem(email) ?? passwordProblem(password);
    if (bad) throw new Error(bad);
    if (password !== confirm) throw new Error('The two passwords do not match.');
    try {
      await createUserWithEmailAndPassword(firebaseAuth(), email.trim(), password);
    } catch (err) {
      throw new Error(friendly((err as { code?: string }).code ?? ''));
    }
  }

  return (
    <main className="waiting">
      <div className="brand brand-lg">
        <span className="brand-mark" aria-hidden>B</span>
        <div><strong>Baymax</strong><span className="muted"> Specialist Portal</span></div>
      </div>
      <h1>Register as a specialist</h1>
      <p className="muted">Doctors, nutritionists and trainers can register here. After an administrator approves you, patients can find and book you in the Baymax app.</p>
      {!firebaseConfigured && <Notice tone="error">Firebase is not configured. Copy <code>.env.example</code> to <code>.env.local</code> first.</Notice>}
      <ApplicationForm
        beforeSubmit={createAccount}
        onSubmitted={async () => {
          await refreshMe();
          router.replace('/dashboard');
        }}
        extra={
          <Card title="Your account">
            <Field label="Email" error={email ? emailProblem(email) : null}>
              <input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} maxLength={120} />
            </Field>
            <div className="grid2">
              <Field label="Password" error={password ? passwordProblem(password) : null} hint="At least 8 characters with a letter and a number.">
                <input type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} maxLength={128} />
              </Field>
              <Field label="Repeat password" error={confirm && confirm !== password ? 'The two passwords do not match.' : null}>
                <input type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} maxLength={128} />
              </Field>
            </div>
            <p className="muted small">Your password goes straight to Firebase. Baymax never sees it.</p>
          </Card>
        }
      />
      <p className="muted">Already registered? <Link className="link" href="/login">Sign in</Link></p>
    </main>
  );
}
