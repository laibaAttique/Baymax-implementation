const express = require('express');
const router = express.Router();
const requireAuth = require('../middleware/firebaseAuth');
const dialogflow = require('../services/dialogflow');

const MAX_TEXT = 256; // Dialogflow's limit for a text query

// One line per request: path, status and (on success) the intent name.
// The user's words are not logged.
router.use((req, res, next) => {
  res.on('finish', () => {
    console.log(`[voice] ${new Date().toISOString()} ${req.method} ${req.path} -> ${res.statusCode}${res.locals.intent ? ` ${res.locals.intent}` : ''}`);
  });
  next();
});

// GET /api/voice/status -> { success, dialogflow: true|false }
// Also used by the app to warm up the connection when the assistant opens.
router.get('/status', requireAuth, async (req, res) => {
  res.json({ success: true, dialogflow: await dialogflow.warmUp() });
});

// Intent recognition for the voice coach (report Module 6, FR-2).
// POST /api/voice/intent { text, session } -> { success, intent, isFallback, confidence, parameters }
// Only the recognised text is sent; no audio or camera data reaches the server.
router.post('/intent', requireAuth, async (req, res) => {
  const text = typeof req.body.text === 'string' ? req.body.text.trim() : '';
  if (!text || text.length > MAX_TEXT) {
    return res.status(400).json({ success: false, error: `text must be 1-${MAX_TEXT} characters` });
  }
  const session = typeof req.body.session === 'string' ? req.body.session.slice(0, 64) : '';
  try {
    const result = await dialogflow.detectIntent(req.uid, text, session);
    res.locals.intent = result.intent;
    res.json({ success: true, ...result });
  } catch (error) {
    const status = error.status || (error.response && error.response.status) || 502;
    console.error('Dialogflow error:', status, error.message);
    res.status(status === 503 ? 503 : 502).json({
      success: false,
      error: status === 503 ? error.message : 'Dialogflow request failed.',
    });
  }
});

module.exports = router;
