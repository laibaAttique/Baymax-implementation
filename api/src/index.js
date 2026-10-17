import 'dotenv/config';
import { createApp } from './app.js';
import { connectFirebase } from './firebase.js';

const { auth, db } = connectFirebase({ databaseURL: process.env.FIREBASE_DATABASE_URL });
const app = createApp({ auth, db, origin: process.env.PORTAL_ORIGIN ?? 'http://localhost:3000',
  meetingBase: process.env.MEETING_BASE_URL ?? 'https://meet.jit.si' });
const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => console.log(`Baymax portal API listening on http://localhost:${port}`));
