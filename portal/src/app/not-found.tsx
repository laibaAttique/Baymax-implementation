import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="login-wrap">
      <div className="login card">
        <h1>Page not found</h1>
        <p className="muted">There is nothing at this address in the Baymax Specialist Portal. Check the address, or go back to the start.</p>
        <div><Link className="btn btn-primary" href="/dashboard">Back to the start</Link></div>
      </div>
    </main>
  );
}
