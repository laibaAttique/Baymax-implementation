// Seeds the LOCAL emulator for the browser walkthrough of payments, the video room and messages. Everything here is fake and local:
//   admin@example.com, doctor@example.com, member@example.com, all with the password "password123".
import { serverTimestamp } from 'firebase/database';
import { adminDb, makeUser, reset, signIn } from './harness.mjs';

await reset();
const admin = await makeUser('admin@example.com');
const doc = await makeUser('doctor@example.com');
const member = await makeUser('member@example.com');
await adminDb.ref().update({
  [`roles/${admin.uid}`]: 'admin',
  [`roles/${doc.uid}`]: 'doctor',
  'config/payments/platformFee': 150, // the booking rules require every payment to carry exactly this platform fee
  [`specialists/${doc.uid}`]: {
    name: 'Hina Malik', type: 'doctor', specialty: 'General medicine', fees: { video: 2500, chat: 1500 }, available: true, verified: true, rating: 0, reviewCount: 0,
    availability: { days: [1, 2, 3, 4, 5, 6, 7], start: '00:00', end: '23:30', slotMinutes: 30 }, tzOffsetMinutes: 300,
  },
});
const m = await signIn(member);
await m.set(`users/${m.uid}/profile`, { fullName: 'Hamza Ali', dob: '1994-03-14', gender: 'Male', height: { value: 175, unit: 'cm' }, weight: { value: 82, unit: 'kg' }, primaryGoal: 'Lose Weight', activityLevel: 'Lightly Active', workoutFrequency: 3, calculatedBMI: 26.8, healthClassification: 'Overweight', medicalConditions: [], foodAllergies: [], medications: '', updatedAt: Date.now() });

const minute = 60_000;
const slot = (offsetMin) => Math.floor((Date.now() + offsetMin * minute) / minute) * minute;
async function book(id, startAt, { fee = 2500, platform = 150, method = 'card' } = {}) {
  const hold = Date.now() + 9 * minute;
  await m.update({
    [`appointments/${id}`]: { patientId: m.uid, patientName: 'Hamza Ali', specialistId: doc.uid, specialistName: 'Dr. Hina Malik', role: 'doctor', specialty: 'General medicine', startAt, slotKey: String(startAt), durationMinutes: 30, type: 'video', status: 'pending_payment', fee, notesForSpecialist: `Booking ${id}: a persistent cough.`, shares: { healthSummary: true, foodLog7d: false, activity30d: false }, createdAt: Date.now(), holdUntil: hold },
    [`slots/${doc.uid}/${startAt}`]: { appt: id, holdUntil: hold },
    [`users/${m.uid}/appointmentIds/${id}`]: startAt,
  });
  const clinic = method === 'clinic';
  await m.update({
    [`appointments/${id}/payment`]: { transactionId: `TXN-${id.toUpperCase()}`, method, status: clinic ? 'pay_at_clinic' : 'paid', consultationFee: fee, platformFee: platform, total: fee + platform, ...(clinic ? {} : { brand: 'Visa', last4: '4242' }), reference: `sbx_${id}`, mode: 'sandbox', paidAt: Date.now() },
    [`appointments/${id}/status`]: 'requested',
    [`appointments/${id}/holdUntil`]: null,
    [`slots/${doc.uid}/${startAt}/holdUntil`]: null,
  });
}
const accept = (id) => adminDb.ref(`appointments/${id}`).update({ status: 'confirmed', meetingLink: `https://meet.jit.si/baymax-${id.replace(/[^a-z0-9]/g, '').padEnd(12, 'x')}abcdefgh`, respondedAt: Date.now() });

/** The phone cannot book a time that close, so book later and move the time forward (as if the clock had run on). */
async function retime(id, from, to) {
  await adminDb.ref().update({
    [`appointments/${id}/startAt`]: to, [`appointments/${id}/slotKey`]: String(to), [`slots/${doc.uid}/${from}`]: null, [`slots/${doc.uid}/${to}`]: { appt: id }, [`users/${m.uid}/appointmentIds/${id}`]: to,
  });
}
const liveFrom = slot(30);
await book('live', liveFrom);                   // a video call the doctor can join now
await retime('live', liveFrom, slot(3));
await accept('live');
await book('request', slot(26 * 60));           // waiting for the doctor's answer
await book('clinic', slot(30 * 60), { method: 'clinic' });
await accept('clinic');
await book('later', slot(50 * 60));             // accepted, tomorrow: the room is not open yet
await accept('later');
// finished sessions (made directly: the phone cannot book in the past)
const done = slot(-3 * 24 * 60);
for (const [id, status, offset] of [['done', 'completed', -3 * 24 * 60], ['patcancel', 'cancelled', 5 * 24 * 60]]) {
  const startAt = slot(offset);
  await adminDb.ref().update({
    [`appointments/${id}`]: { patientId: m.uid, patientName: 'Hamza Ali', specialistId: doc.uid, specialistName: 'Dr. Hina Malik', role: 'doctor', specialty: 'General medicine', startAt, slotKey: String(startAt), durationMinutes: 30, type: 'video', status, fee: 2500, createdAt: Date.now() - 86_400_000 * 6, notesForSpecialist: 'Follow-up.', shares: { healthSummary: false, foodLog7d: false, activity30d: false }, meetingLink: status === 'completed' ? 'https://meet.jit.si/baymax-doneabcdefghjkmnp' : null,
      payment: { transactionId: `TXN-${id.toUpperCase()}`, method: 'card', status: 'paid', consultationFee: 2500, platformFee: 150, total: 2650, brand: 'Visa', last4: '4242', reference: `sbx_${id}`, mode: 'sandbox', paidAt: startAt - 86_400_000 } },
    [`users/${m.uid}/appointmentIds/${id}`]: startAt,
  });
}
// the patient writes to the doctor through the real rules, exactly as the app does
await m.set(`chats/live/${Math.random().toString(36).slice(2)}`, { from: m.uid, side: 'patient', text: 'Hello doctor, I will join in a few minutes.', at: serverTimestamp() });
// an old conversation: the rules close writing 24 hours after the slot (which is the point), so this one is written by the server
await adminDb.ref(`chats/done/old1`).set({ from: m.uid, side: 'patient', text: 'Thank you for the advice last week.', at: Date.now() - 2 * 86_400_000 });
console.log('seeded: admin, doctor, member + appointments live, request, clinic, later, done, patcancel');
process.exit(0);
