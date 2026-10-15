import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { HttpError } from './http.js';
import { authenticate } from './middleware/auth.js';
import { specialistRoutes } from './routes/specialist.js';

/**
 * Builds the API. [auth] verifies Firebase ID tokens, [db] is the database interface in lib/db.js, [now] is the clock.
 * They are injected so tests can run the whole API without Firebase.
 */
export function createApp({ auth, db, now = Date.now, origin = 'http://localhost:3000' }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(cors({ origin: origin.split(',').map((o) => o.trim()), methods: ['GET', 'POST', 'PUT'], allowedHeaders: ['Authorization', 'Content-Type'] }));
  app.use(express.json({ limit: '20kb' }));
  app.use('/api', rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true, legacyHeaders: false }));

  app.get('/health', (_req, res) => res.json({ ok: true }));
  app.use('/api', authenticate({ auth, db }), specialistRoutes({ db, now }));

  app.use('/api', (_req, _res, next) => next(new HttpError(404, 'Not found.')));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message });
    if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'The request was not valid JSON.' });
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'The request is too large.' });
    console.error('Unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong on our side. Please try again.' });
  });
  return app;
}
