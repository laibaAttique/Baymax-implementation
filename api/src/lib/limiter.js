import { HttpError } from '../http.js';

/**
 * A small in-memory limiter: at most [limit] hits per [windowMs] for each key. It uses the injected clock so tests are exact.
 * (express-rate-limit already caps requests per address; this one caps what a signed-in person can do, such as sending chat messages.)
 */
export function makeLimiter({ limit, windowMs, now = Date.now }) {
  const hits = new Map();
  return {
    /** Counts one hit for [key]; throws 429 when the person is over the limit. */
    hit(key, message = 'You are doing that too often. Please wait a moment.') {
      const t = now();
      const recent = (hits.get(key) ?? []).filter((x) => t - x < windowMs);
      if (recent.length >= limit) {
        hits.set(key, recent);
        throw new HttpError(429, message);
      }
      recent.push(t);
      hits.set(key, recent);
      if (hits.size > 5000) for (const [k, v] of hits) if (!v.some((x) => t - x < windowMs)) hits.delete(k);
    },
  };
}
