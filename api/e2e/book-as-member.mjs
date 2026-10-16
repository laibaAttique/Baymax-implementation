// Plays the mobile app for the browser walkthrough: a member with a profile, a food log and workouts books the approved doctor and pays
// (test card). Uses the real database rules on the emulator, exactly as the app's own writes do.
import { adminDb, makeUser, signIn } from './harness.mjs';
const specialists = (await adminDb.ref('specialists').get()).val() ?? {};
const [specId, spec] = Object.entries(specialists)[0] ?? [];
if (!specId) throw new Error('No specialist yet: approve the registration first.');
let member;
try { member = await makeUser('member@example.com'); } catch { member = { uid: (await (await import('./harness.mjs')).auth.getUserByEmail('member@example.com')).uid, email: 'member@example.com', password: 'password123' }; }
const m = await signIn(member);
const today = new Date().toISOString().slice(0, 10);
const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
await m.update({
  [`users/${m.uid}/profile`]: { fullName: 'Hamza Ali', dob: '1994-03-14', gender: 'Male', height: { value: 175, unit: 'cm' }, weight: { value: 82, unit: 'kg' }, primaryGoal: 'Lose Weight', activityLevel: 'Lightly Active', workoutFrequency: 3, calculatedBMI: 26.8, healthClassification: 'Overweight', medicalConditions: ['Hypertension'], foodAllergies: ['Peanuts'], medications: 'Amlodipine 5mg', updatedAt: Date.now() },
  [`users/${m.uid}/foodLog/${today}/a1`]: { meal: 'Breakfast', name: 'Paratha with egg', kcal: 520, protein: 18, carbs: 45, fat: 30 },
  [`users/${m.uid}/foodLog/${today}/a2`]: { meal: 'Lunch', name: 'Chicken biryani', kcal: 710, protein: 32, carbs: 85, fat: 24 },
  [`users/${m.uid}/foodLog/${yesterday}/b1`]: { meal: 'Dinner', name: 'Haleem', kcal: 640, protein: 35, carbs: 50, fat: 28 },
  [`users/${m.uid}/activity/${yesterday}`]: { workoutDone: true, minutes: 40, kcal: 280 },
});
const startAt = Math.floor((Date.now() + 12 * 60_000) / 60_000) * 60_000;
const id = process.env.APPT_ID ?? 'walkthrough-1';
const hold = Date.now() + 9 * 60_000;
await m.update({
  [`appointments/${id}`]: { patientId: m.uid, patientName: 'Hamza Ali', specialistId: specId, specialistName: `Dr. ${spec.name.replace(/^Dr\.? /, '')}`, role: spec.type, specialty: spec.specialty, startAt, slotKey: String(startAt), durationMinutes: spec.availability.slotMinutes, type: 'video', status: 'pending_payment', fee: spec.fees.video, notesForSpecialist: 'Headaches and high blood pressure readings; want a safe exercise plan.', shares: { healthSummary: true, foodLog7d: true, activity30d: true }, createdAt: Date.now(), holdUntil: hold },
  [`slots/${specId}/${startAt}`]: { appt: id, holdUntil: hold },
  [`users/${m.uid}/appointmentIds/${id}`]: startAt,
});
await m.update({
  [`appointments/${id}/payment`]: { transactionId: 'TXN-WALK-0001', method: 'card', status: 'paid', consultationFee: spec.fees.video, platformFee: 0, total: spec.fees.video, brand: 'Visa', last4: '4242', reference: 'sbx_c_walk', mode: 'sandbox', paidAt: Date.now() },
  [`appointments/${id}/status`]: 'requested',
  [`appointments/${id}/holdUntil`]: null,
  [`slots/${specId}/${startAt}/holdUntil`]: null,
});
console.log(`member ${member.email} requested ${id} with ${spec.name} (${specId}); status:`, (await m.get(`appointments/${id}`)).status);
process.exit(0);
