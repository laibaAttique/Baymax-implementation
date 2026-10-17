'use client';

import { FormEvent, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { sendPasswordResetEmail, signInWithEmailAndPassword } from 'firebase/auth';
import { firebaseAuth, firebaseConfigured } from '@/lib/firebase';
import { useAuth } from '@/lib/auth';
import { Notice } from '@/components/ui';

function friendly(code: string): string {
  switch (code) {
    case 'auth/invalid-credential':
    case 'auth/wrong-password':
    case 'auth/user-not-found':
    case 'auth/invalid-email':
      return 'That email and password do not match.';
    case 'auth/too-many-requests':
      return 'Too many attempts. Please wait a few minutes and try again.';
    case 'auth/network-request-failed':
      return 'Could not reach Firebase. Check your internet connection.';
    case 'auth/user-disabled':
      return 'This account has been disabled. Please contact a Baymax administrator.';
    default:
      return 'Could not sign in. Please try again.';
  }
}

export default function LoginPage() {
  const router = useRouter();
  const { state } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  useEffect(() => {
    if (state.status === 'ready') router.replace('/dashboard');
  }, [state.status, router]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setInfo(null);
    try {
      await signInWithEmailAndPassword(firebaseAuth(), email.trim(), password);
      router.replace('/dashboard');
    } catch (err) {
      setError(friendly((err as { code?: string }).code ?? ''));
    } finally {
      setBusy(false);
    }
  }

  async function reset() {
    setError(null);
    setInfo(null);
    if (!email.trim()) {
      setError('Enter your email above first.');
      return;
    }
    try {
      await sendPasswordResetEmail(firebaseAuth(), email.trim());
    } catch {
      // The same message either way, so this form cannot be used to find out which emails have accounts.
    }
    setInfo('If that email has an account, a password reset link is on its way.');
  }

  return (
    <main className="login-wrap">
      <form className="card login" onSubmit={submit} noValidate>
        <div className="brand brand-lg">
          <span className="brand-mark" aria-hidden>B</span>
          <div>
            <strong>Baymax</strong>
            <span className="muted"> Specialist Portal</span>
          </div>
        </div>
        <p className="muted">Sign in with the account your Baymax administrator created for you.</p>

        {!firebaseConfigured && (
          <Notice tone="error">Firebase is not configured. Copy <code>.env.example</code> to <code>.env.local</code> and fill in the web app values.</Notice>
        )}
        {error && <Notice tone="error">{error}</Notice>}
        {info && <Notice tone="ok">{info}</Notice>}

        <label>
          Email
          <input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Password
          <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </label>
        <button className="btn btn-primary" disabled={busy || !firebaseConfigured || !email || !password}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
        <button type="button" className="btn btn-link" onClick={reset}>
          Forgot your password?
        </button>
        <p className="muted small">New here? <Link className="link" href="/register">Register as a specialist</Link></p>
      </form>
    </main>
  );
}
