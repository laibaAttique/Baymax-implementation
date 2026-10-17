'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { createUserWithEmailAndPassword } from 'firebase/auth';
import { firebaseAuth, firebaseConfigured } from '@/lib/firebase';
import { useAuth } from '@/lib/auth';
import { ApplicationForm } from '@/components/ApplicationForm';
import { Card, Notice } from '@/components/ui';

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
    if (password.length < 8) throw new Error('Choose a password of at least 8 characters.');
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
            <label>Email<input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required /></label>
            <div className="grid2">
              <label>Password<input type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={8} /></label>
              <label>Repeat password<input type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} required minLength={8} /></label>
            </div>
            <p className="muted small">Your password goes straight to Firebase. Baymax never sees it.</p>
          </Card>
        }
      />
      <p className="muted">Already registered? <Link className="link" href="/login">Sign in</Link></p>
    </main>
  );
}
