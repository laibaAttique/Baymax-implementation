import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';
import { adminDb } from './lib/db.js';

/**
 * Connects to the same Firebase project as the mobile app. Credentials come from GOOGLE_APPLICATION_CREDENTIALS (a path to a
 * service-account key kept outside this folder) and the database from FIREBASE_DATABASE_URL. Nothing secret is stored here.
 */
export function connectFirebase({ databaseURL }) {
  if (!databaseURL) throw new Error('FIREBASE_DATABASE_URL is not set. Copy .env.example to .env and fill it in.');
  // With the local Firebase emulators (FIREBASE_AUTH_EMULATOR_HOST is set) there is no real project and no key: nothing is sent to Google.
  const emulated = !!process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const app = getApps()[0] ?? initializeApp(emulated ? { projectId: process.env.GCLOUD_PROJECT ?? 'demo-baymax', databaseURL } : { credential: applicationDefault(), databaseURL });
  return { auth: getAuth(app), db: adminDb(getDatabase(app)) };
}
