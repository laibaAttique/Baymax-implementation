import { firebaseAuth } from './firebase';

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';
const TIMEOUT_MS = 20_000;

/** Fired when the API says the sign-in is no longer valid, so the app can send the person back to the sign-in page. */
export const UNAUTHORIZED_EVENT = 'baymax:unauthorized';

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/**
 * Calls the portal API with the signed-in person's Firebase ID token. The token is refreshed by Firebase when it is about to expire.
 * A request that takes longer than 20 seconds is given up on, so a stuck connection never leaves a button spinning for ever.
 */
export async function api<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const user = firebaseAuth().currentUser;
  if (!user) throw new ApiError(401, 'Please sign in.');
  const token = await user.getIdToken();
  let res: Response;
  try {
    res = await fetch(`${API_URL}/api${path}`, {
      method: init.method ?? 'GET',
      headers: { Authorization: `Bearer ${token}`, ...(init.body ? { 'Content-Type': 'application/json' } : {}) },
      body: init.body ? JSON.stringify(init.body) : undefined,
      cache: 'no-store',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    if (e instanceof DOMException && (e.name === 'TimeoutError' || e.name === 'AbortError')) throw new ApiError(0, 'The server took too long to answer. Please try again.');
    throw new ApiError(0, 'Could not reach the Baymax server. Check that it is running and that you are online.');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401 && typeof window !== 'undefined' && data.code !== 'reauth-required') window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
    if (res.status === 429) throw new ApiError(429, data.error ?? 'You are doing that too often. Please wait a moment.');
    throw new ApiError(res.status, data.error ?? 'Something went wrong. Please try again.');
  }
  return data as T;
}
