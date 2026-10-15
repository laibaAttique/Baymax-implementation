import { getApp, getApps, initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';

// Same Firebase project as the mobile app. The browser uses it ONLY to sign in; every other request goes to the portal API.
const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

export const firebaseConfigured = Boolean(config.apiKey && config.appId && config.projectId);

export function firebaseAuth() {
  const app = getApps().length ? getApp() : initializeApp(config);
  return getAuth(app);
}
