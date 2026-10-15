const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { GoogleAuth } = require('google-auth-library');

// Dialogflow ES intent detection for the voice assistant (report Module 6, FR-2).
//
// Configuration (.env):
//   DIALOGFLOW_KEY_FILE   path to the service-account JSON key (role: "Dialogflow API Client")
//   DIALOGFLOW_PROJECT_ID optional; defaults to the key file's project_id
//   DIALOGFLOW_LANGUAGE   optional; defaults to "en"
// The key stays on the server; the app only ever sees the detected intent.

const SCOPE = 'https://www.googleapis.com/auth/dialogflow';
let cached = null;

function config() {
  const setting = process.env.DIALOGFLOW_KEY_FILE || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!setting) return null;
  // Relative paths are relative to the backend folder.
  const keyFile = path.resolve(__dirname, '..', setting);
  if (!fs.existsSync(keyFile)) return null;
  if (!cached || cached.keyFile !== keyFile) {
    const auth = new GoogleAuth({ keyFile, scopes: [SCOPE] });
    cached = { keyFile, auth, projectId: process.env.DIALOGFLOW_PROJECT_ID || null };
  }
  return cached;
}

function isConfigured() {
  return config() !== null;
}

// A stable, non-reversible Dialogflow session id per user and app session, so
// Dialogflow never receives the Firebase uid itself.
function sessionId(uid, clientSession) {
  return crypto.createHash('sha256').update(`${uid}:${clientSession || ''}`).digest('hex').slice(0, 36);
}

async function detectIntent(uid, text, clientSession) {
  const cfg = config();
  if (!cfg) {
    const err = new Error('Dialogflow is not configured on the server (DIALOGFLOW_KEY_FILE missing or the key file does not exist).');
    err.status = 503;
    throw err;
  }
  const projectId = cfg.projectId || (cfg.projectId = await cfg.auth.getProjectId());
  const client = await cfg.auth.getClient();
  const url = `https://dialogflow.googleapis.com/v2/projects/${encodeURIComponent(projectId)}/agent/sessions/${sessionId(uid, clientSession)}:detectIntent`;
  const res = await client.request({
    url,
    method: 'POST',
    timeout: 4000,
    data: { queryInput: { text: { text, languageCode: process.env.DIALOGFLOW_LANGUAGE || 'en' } } },
  });
  const result = res.data.queryResult || {};
  const intent = result.intent || {};
  return {
    intent: intent.displayName || null,
    isFallback: Boolean(intent.isFallback) || !intent.displayName,
    confidence: typeof result.intentDetectionConfidence === 'number' ? result.intentDetectionConfidence : null,
    parameters: result.parameters || {},
  };
}

// Fetches an access token ahead of the first question, so it does not add
// to the user's wait. Safe to call repeatedly; failures are ignored here and
// reported by detectIntent.
async function warmUp() {
  const cfg = config();
  if (!cfg) return false;
  try {
    const client = await cfg.auth.getClient();
    await client.getAccessToken();
    if (!cfg.projectId) cfg.projectId = await cfg.auth.getProjectId();
    return true;
  } catch (error) {
    console.error('Dialogflow warm-up failed:', error.message);
    return false;
  }
}

module.exports = { isConfigured, detectIntent, warmUp };
