import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { HttpError } from './http.js';
import { authenticate } from './middleware/auth.js';
import { meRoutes, specialistRoutes } from './routes/specialist.js';
import { adminRoutes } from './routes/admin.js';
import { applicationRoutes } from './routes/applications.js';
import { requireJsonContentType, requireObjectBody } from './lib/validate.js';
import { makeLimiter } from './lib/limiter.js';

/**
 * Builds the API. [auth] verifies Firebase ID tokens, [db] is the database interface in lib/db.js, [now] is the clock.
 * They are injected so tests can run the whole API without Firebase.
 */
export function createApp({ auth, db, now = Date.now, origin = 'http://localhost:3000', meetingBase = 'https://meet.jit.si', randomBytes }) {
  const app = express();
  app.disable('x-powered-by');
  // The web apps (another origin) read this API with fetch, so its responses must be allowed across origins; CORS below decides who.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors({ origin: origin.split(',').map((o) => o.trim()), methods: ['GET', 'POST', 'PUT', 'DELETE'], allowedHeaders: ['Authorization', 'Content-Type'] }));
  app.use(express.json({ limit: '20kb' }));
  app.use('/api', rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true, legacyHeaders: false }));

  app.get('/health', (_req, res) => res.json({ ok: true }));
  // A write must be a JSON object, and one signed-in person cannot make more than 120 writes a minute.
  app.use('/api', requireJsonContentType, requireObjectBody);
  app.use('/api', authenticate({ auth, db }));
  const writeLimit = makeLimiter({ limit: 120, windowMs: 60_000, now });
  app.use('/api', (req, _res, next) => {
    if (req.method !== 'GET') writeLimit.hit(req.user.uid);
    next();
  });
  app.use('/api', meRoutes({ db }));
  app.use('/api/applications', applicationRoutes({ db, now }));
  app.use('/api/admin', adminRoutes({ auth, db, now }));
  app.use('/api', specialistRoutes({ auth, db, now, meetingBase, randomBytes }));

  app.use('/api', (_req, _res, next) => next(new HttpError(404, 'Not found.')));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message, ...(err.code ? { code: err.code } : {}) });
    if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'The request was not valid JSON.' });
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'The request is too large.' });
    console.error('Unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong on our side. Please try again.' });
  });
  return app;
}
