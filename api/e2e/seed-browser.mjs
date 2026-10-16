// Seeds the emulator for the browser walkthrough: one administrator (admin@example.com / password123) and nothing else.
import { adminDb, makeUser, reset } from './harness.mjs';
await reset();
const admin = await makeUser('admin@example.com');
await adminDb.ref(`roles/${admin.uid}`).set('admin');
console.log('seeded administrator admin@example.com');
process.exit(0);
