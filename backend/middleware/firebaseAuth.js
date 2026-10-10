const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

// Verifying ID tokens only needs the project ID (public signing keys are
// fetched from Google); no service-account credentials are required.
if (!getApps().length) {
  initializeApp({ projectId: process.env.FIREBASE_PROJECT_ID || 'baymax-148da' });
}

// Requires `Authorization: Bearer <Firebase ID token>` and sets req.uid.
module.exports = async function requireAuth(req, res, next) {
  const match = (req.headers.authorization || '').match(/^Bearer (.+)$/i);
  if (!match) {
    return res.status(401).json({ success: false, error: 'Missing auth token' });
  }
  try {
    const decoded = await getAuth().verifyIdToken(match[1]);
    req.uid = decoded.uid;
    next();
  } catch (error) {
    res.status(401).json({ success: false, error: 'Invalid or expired token' });
  }
};
