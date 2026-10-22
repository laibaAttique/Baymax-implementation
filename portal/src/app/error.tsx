'use client';

import { useEffect } from 'react';
import Link from 'next/link';

/** Shown instead of a blank page if a screen fails while it is drawing. The person can try again or go back to the start. */
export default function ErrorPage({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);
  return (
    <main className="login-wrap">
      <div className="login card" role="alert">
        <h1>Something went wrong</h1>
        <p className="muted">This screen could not be shown. Your work on the server is safe. Try again, and if it keeps happening tell a Baymax administrator{error.digest ? ` (reference ${error.digest})` : ''}.</p>
        <div className="actions">
          <button className="btn btn-primary" onClick={() => retry()}>Try again</button>
          <Link className="btn" href="/dashboard">Back to the start</Link>
        </div>
      </div>
    </main>
  );
}
