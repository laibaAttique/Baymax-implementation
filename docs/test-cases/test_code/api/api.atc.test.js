// Automated FUNCTIONAL and BUSINESS-RULE test cases for the Baymax API (report sections 5.2 and 5.3).
// IDs: ATC-M<module>-F<nn> (functional) and ATC-M<module>-B<nn> (decision-table rules). Run: npm test  (set ATC_LOG to record results)
import { MIN, NOW, appointment, baseData, profile, start } from '../helpers.js';
import { atc, check, same } from './atc.js';

const DAY = 86_400_000;
const accounts = { 'adm1@example.com': 'adm1', 'doc1@example.com': 'doc1' };

// ---- fixtures --------------------------------------------------------------------------------------------------------------------
const requests = () =>
  baseData({
    appointments: {
      r1: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 120 * MIN, patientId: 'pat1', payment: { status: 'paid', method: 'card', total: 2500, mode: 'sandbox', transactionId: 'T1' } }),
      r2: appointment({ status: 'requested', meetingLink: '', startAt: NOW + 180 * MIN, patientName: 'Bilal Ahmed', patientId: 'pat2', type: 'chat' }),
      late: appointment({ status: 'requested', meetingLink: '', startAt: NOW - 30 * MIN, patientName: 'Too Late', patientId: 'pat3' }),
      ok: appointment({ status: 'confirmed', startAt: NOW + 60 * MIN, patientName: 'Confirmed One', patientId: 'pat4' }),
      other: appointment({ status: 'requested', meetingLink: '', specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', startAt: NOW + 120 * MIN }),
    },
    slots: { doc1: { [NOW + 120 * MIN]: { appt: 'r1' }, [NOW + 180 * MIN]: { appt: 'r2' } } },
    users: { pat1: { profile: { fullName: 'Ayesha Khan', dob: '1996-04-02', medicalConditions: ['Asthma'] } } },
  });

const sessions = (extra = {}) =>
  baseData({
    appointments: {
      a1: appointment({ startAt: NOW + 60 * MIN }),
      a2: appointment({ patientName: 'Bilal Ahmed', patientId: 'pat2', startAt: NOW - 10 * MIN }),
      n1: appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', startAt: NOW - 5 * MIN }),
      other: appointment({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', patientName: 'Not Yours', startAt: NOW + 30 * MIN }),
    },
    slots: { doc1: { [NOW + 60 * MIN]: { appt: 'a1' } } },
    users: {
      pat1: {
        profile: { fullName: 'Ayesha Khan', dob: '1996-04-02', gender: 'Female', medicalConditions: ['Asthma'] },
        foodLog: { '2026-10-19': { e1: { meal: 'Breakfast', name: 'Paratha', kcal: 300, protein: 6, carbs: 40, fat: 12 } } },
      },
    },
    ...extra,
  });

const patients = () => {
  const ok = (o = {}) => ({ status: 'completed', startAt: NOW - 3 * DAY, ...o });
  const d = baseData({
    appointments: {
      p1a: appointment(ok({ patientId: 'pat1', patientName: 'Ayesha Khan' })),
      p1b: appointment({ patientId: 'pat1', patientName: 'Ayesha Khan', status: 'confirmed', startAt: NOW + 2 * DAY }),
      p2: appointment(ok({ patientId: 'pat2', patientName: 'Bilal Ahmed', startAt: NOW - 40 * DAY })),
      req: appointment({ patientId: 'pat3', patientName: 'Only Requested', status: 'requested', meetingLink: '', startAt: NOW + 3 * DAY }),
      gone: appointment({ patientId: 'pat4', patientName: 'Cancelled One', status: 'cancelled', startAt: NOW + DAY }),
      n1: appointment(ok({ specialistId: 'nut1', specialistName: 'Sara Khan', role: 'nutritionist', patientId: 'pat1', patientName: 'Ayesha Khan', startAt: NOW - 20 * MIN, status: 'confirmed' })),
      t1: appointment(ok({ specialistId: 'tr1', specialistName: 'Ali Raza', role: 'trainer', patientId: 'pat1', patientName: 'Ayesha Khan', startAt: NOW - DAY })),
    },
    slots: { doc1: { [NOW + 2 * DAY]: { appt: 'p1b' } } },
    users: { pat1: { profile: { fullName: 'Ayesha Khan', dob: '1996-04-02', medicalConditions: ['Asthma'] } } },
  });
  d.roles.tr1 = 'trainer';
  d.specialists.tr1 = profile('trainer', 'Ali Raza');
  return d;
};
const dietBody = (o = {}) => ({ status: 'modified', targetKcal: 1900, proteinG: 120, carbsG: 210, fatG: 60, avoid: ['Fried foods'], tips: ['Drink water before meals'], note: 'Follow for 4 weeks', ...o });
const day = (n, items) => ({ day: n, rest: !items, items: items ?? [] });
const workoutBody = (o = {}) => ({
  status: 'modified', note: 'Build up slowly',
  schedule: [day(1, [{ exerciseId: 'brisk_walk', sets: 1, seconds: 600 }]), day(2), day(3, [{ exerciseId: 'chair_squat', sets: 3, reps: 10 }]), day(4), day(5, [{ exerciseId: 'brisk_walk', sets: 1, seconds: 900 }]), day(6), day(7)],
  ...o,
});
const form = (o = {}) => ({ name: 'Dr Ayesha Noor', type: 'doctor', specialty: 'Cardiology', licenseNumber: 'PMDC-12345', yearsOfExperience: 9, fees: { video: 3000, chat: 1800 }, ...o });

// =================================================================================================================================
// FUNCTIONAL
// =================================================================================================================================
atc('ATC-M16-F04', { req: 'M16-FR2', objective: 'A request without a valid sign-in is turned away', input: 'GET /api/me with no token, a garbage token and a Basic scheme', expected: '401 three times; /health stays open (200)' }, async () => {
  const s = await start(sessions());
  try {
    const none = (await s.call('GET', '/api/me')).status;
    const garbage = (await fetch(`${s.base}/api/me`, { headers: { Authorization: 'Bearer not-a-real-token' } })).status;
    const basic = (await fetch(`${s.base}/api/me`, { headers: { Authorization: 'Basic token-doc1' } })).status;
    const health = (await fetch(`${s.base}/health`)).status;
    return check(none === 401 && garbage === 401 && basic === 401 && health === 200, `No token ${none}; garbage token ${garbage}; Basic scheme ${basic}; /health ${health}`);
  } finally { s.close(); }
});

atc('ATC-M16-F05', { req: 'M16-FR2', objective: 'A member or administrator cannot open the specialist screens even by typing the address', input: 'GET /api/dashboard, /api/appointments, /api/appointments/a1 as a member, an administrator and an unknown user', expected: '403 for every one of the 9 requests' }, async () => {
  const s = await start(sessions());
  try {
    const codes = [];
    for (const who of ['pat1', 'adm1', 'nobody']) for (const path of ['/api/dashboard', '/api/appointments', '/api/appointments/a1']) codes.push((await s.call('GET', path, { as: who })).status);
    return check(codes.every((c) => c === 403), `Status codes: ${codes.join(', ')}`);
  } finally { s.close(); }
});

atc('ATC-M16-F06', { req: 'M16-FR2', objective: 'Another specialist\'s appointment looks like it does not exist', input: 'Doctor opens appointment "other" that belongs to the nutritionist', expected: '404' }, async () => {
  const s = await start(sessions());
  try {
    const r = await s.call('GET', '/api/appointments/other', { as: 'doc1' });
    return same(r.status, 404, `Status ${r.status}`);
  } finally { s.close(); }
});

atc('ATC-M14-F21', { req: 'M14-FR12', objective: 'The dashboard lists open requests soonest first, hides expired ones and counts them', input: 'Doctor opens the dashboard with 2 live requests, 1 expired request and 1 confirmed session', expected: 'Requests r1 then r2; today shows the confirmed session; 2 pending; no video link on a request' }, async () => {
  const s = await start(requests());
  try {
    const d = (await s.call('GET', '/api/dashboard', { as: 'doc1' })).body;
    const ids = d.requests.map((a) => a.id).join(',');
    return check(ids === 'r1,r2' && d.today.map((a) => a.id).join(',') === 'ok' && d.counts.pendingRequests === 2 && d.requests[0].meetingLink === '' && d.requests[0].canRespond === true,
      `Requests: ${ids}; today: ${d.today.map((a) => a.id).join(',')}; pending ${d.counts.pendingRequests}; link on request "${d.requests[0].meetingLink}"`);
  } finally { s.close(); }
});

atc('ATC-M14-F22', { req: 'M14-FR3, M14-FR12', objective: 'Accepting a request creates the video room on the server, confirms it and tells the patient', input: 'Doctor accepts r1, then accepts it again', expected: '200 and status confirmed; a meet.jit.si room; patient notified; slot kept; the second accept is 400' }, async () => {
  const s = await start(requests());
  try {
    const r = await s.call('POST', '/api/appointments/r1/accept', { as: 'doc1' });
    const link = s.db.root.appointments.r1.meetingLink;
    const note = s.db.root.users.pat1.inbox['accept-r1'];
    const again = await s.call('POST', '/api/appointments/r1/accept', { as: 'doc1' });
    return check(r.status === 200 && r.body.appointment.status === 'confirmed' && /^https:\/\/meet\.jit\.si\/baymax-[a-z0-9]{20}$/.test(link) && /accepted/.test(note.title) && !!s.db.root.slots.doc1[NOW + 120 * MIN] && again.status === 400,
      `Accept ${r.status} (${r.body.appointment?.status}); room ${link}; patient notice "${note?.title}"; slot kept ${!!s.db.root.slots.doc1[NOW + 120 * MIN]}; second accept ${again.status}`);
  } finally { s.close(); }
});

atc('ATC-M14-F23', { req: 'M14-FR12', objective: 'Declining frees the time, keeps the reason and tells the patient', input: 'Doctor declines r2 with reason "  On leave that day  "', expected: 'Status declined, reason trimmed, slot freed, other slot kept, patient notified, no room made, accepting afterwards is 400' }, async () => {
  const s = await start(requests());
  try {
    const r = await s.call('POST', '/api/appointments/r2/decline', { as: 'doc1', body: { reason: '  On leave that day  ' } });
    const a = s.db.root.appointments.r2;
    const freed = s.db.root.slots.doc1[NOW + 180 * MIN] === undefined, kept = !!s.db.root.slots.doc1[NOW + 120 * MIN];
    const accept = await s.call('POST', '/api/appointments/r2/accept', { as: 'doc1' });
    return check(r.status === 200 && a.status === 'declined' && a.declineReason === 'On leave that day' && freed && kept && s.db.root.users.pat2.inbox['decline-r2'].title === 'Your request was not accepted' && a.meetingLink === '' && accept.status === 400,
      `Decline ${r.status}; status ${a.status}; reason "${a.declineReason}"; slot freed ${freed}; other slot kept ${kept}; accept afterwards ${accept.status}`);
  } finally { s.close(); }
});

atc('ATC-M14-F24', { req: 'M14-FR12', objective: 'A request whose time has passed is shown as expired and cannot be answered', input: 'Doctor lists appointments and tries to accept "late" (start was 30 minutes ago)', expected: 'phase expired, canRespond false, accept answers 400 "expired"' }, async () => {
  const s = await start(requests());
  try {
    const late = (await s.call('GET', '/api/appointments', { as: 'doc1' })).body.appointments.find((a) => a.id === 'late');
    const r = await s.call('POST', '/api/appointments/late/accept', { as: 'doc1' });
    return check(late.phase === 'expired' && late.canRespond === false && r.status === 400 && /expired/.test(r.body.error), `Phase ${late.phase}; canRespond ${late.canRespond}; accept ${r.status} "${r.body.error}"`);
  } finally { s.close(); }
});

atc('ATC-M14-F25', { req: 'M14-FR12', objective: 'Only the specialist the request was sent to can answer it', input: 'Doctor answers the nutritionist\'s request; a member and an anonymous caller answer r1', expected: '404, 403 and 401; r1 stays requested' }, async () => {
  const s = await start(requests());
  try {
    const a = (await s.call('POST', '/api/appointments/other/accept', { as: 'doc1' })).status;
    const b = (await s.call('POST', '/api/appointments/r1/accept', { as: 'pat1' })).status;
    const c = (await s.call('POST', '/api/appointments/r1/accept')).status;
    return check(a === 404 && b === 403 && c === 401 && s.db.root.appointments.r1.status === 'requested', `Other specialist's request ${a}; member ${b}; anonymous ${c}; r1 is ${s.db.root.appointments.r1.status}`);
  } finally { s.close(); }
});

atc('ATC-M14-F26', { req: 'M14-FR8', objective: 'Notes are saved after the start, the patient is told, and a note before the start is refused', input: 'Doctor writes notes for a1 (starts in 60 min) and for a2 (started 10 min ago)', expected: 'a1: 400 "started"; a2: 200, note and prescription stored, patient notified' }, async () => {
  const s = await start(sessions());
  try {
    const early = await s.call('PUT', '/api/appointments/a1/consultation', { as: 'doc1', body: { notes: 'x' } });
    const ok = await s.call('PUT', '/api/appointments/a2/consultation', { as: 'doc1', body: { notes: 'Rest and fluids', prescription: 'Paracetamol 500mg' } });
    const inbox = s.db.root.users.pat2.inbox['note-a2'];
    return check(early.status === 400 && /started/.test(early.body.error) && ok.status === 200 && ok.body.appointment.consultation.prescription === 'Paracetamol 500mg' && inbox?.route === 'appointments',
      `Before start ${early.status}; after start ${ok.status}; prescription "${ok.body.appointment?.consultation?.prescription}"; patient notified ${!!inbox}`);
  } finally { s.close(); }
});

atc('ATC-M14-F27', { req: 'M14-FR6', objective: 'Only a doctor can write a prescription', input: 'Nutritionist saves notes with a prescription', expected: '400 mentioning "doctor"' }, async () => {
  const s = await start(sessions());
  try {
    const r = await s.call('PUT', '/api/appointments/n1/consultation', { as: 'nut1', body: { notes: 'Eat more fibre', prescription: 'Drug' } });
    return check(r.status === 400 && /doctor/.test(r.body.error), `Status ${r.status}: "${r.body.error}"`);
  } finally { s.close(); }
});

atc('ATC-M14-F28', { req: 'M14-FR7', objective: 'Cancelling frees the slot and tells the patient; a finished appointment cannot be changed again', input: 'Doctor cancels a1, then tries to mark it completed', expected: '200, slot gone, notice "Appointment cancelled"; then 400 "already cancelled"' }, async () => {
  const s = await start(sessions());
  try {
    const r = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: 'cancelled' } });
    const freed = s.db.root.slots === undefined;
    const again = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: 'completed' } });
    return check(r.status === 200 && freed && s.db.root.users.pat1.inbox['cancel-a1'].title === 'Appointment cancelled' && again.status === 400 && /already cancelled/.test(again.body.error),
      `Cancel ${r.status}; slot freed ${freed}; second change ${again.status} "${again.body.error}"`);
  } finally { s.close(); }
});

atc('ATC-M14-F29', { req: 'M14-FR13', objective: 'My patients lists only people with an accepted appointment and supports search', input: 'Doctor opens /api/patients, then searches "bil"; a member tries the same', expected: 'Ayesha Khan and Bilal Ahmed only; search gives Bilal; member gets 403' }, async () => {
  const s = await start(patients());
  try {
    const r = await s.call('GET', '/api/patients', { as: 'doc1' });
    const names = r.body.patients.map((p) => p.name).sort().join(', ');
    const q = (await s.call('GET', '/api/patients?q=bil', { as: 'doc1' })).body.patients.map((p) => p.name).join(', ');
    const member = (await s.call('GET', '/api/patients', { as: 'pat1' })).status;
    return check(names === 'Ayesha Khan, Bilal Ahmed' && q === 'Bilal Ahmed' && member === 403, `Patients: ${names}; search "bil": ${q}; member ${member}`);
  } finally { s.close(); }
});

atc('ATC-M14-F30', { req: 'M14-FR5', objective: 'A nutritionist saves a diet plan that is stored with its author and announced to the patient', input: 'PUT /api/patients/pat1/plans/diet with 1900 kcal, 120/210/60 g', expected: '200; stored target 1900 with author Sara Khan (nutritionist); patient notified; visible on the record' }, async () => {
  const s = await start(patients());
  try {
    const r = await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: dietBody() });
    const p = s.db.root.specialistPlans?.pat1?.diet;
    const note = Object.values(s.db.root.users.pat1.inbox ?? {}).find((n) => n.route === 'diet');
    const rec = (await s.call('GET', '/api/patients/pat1', { as: 'nut1' })).body.plans?.diet?.targetKcal;
    return check(r.status === 200 && p.targetKcal === 1900 && p.by.name === 'Sara Khan' && p.by.role === 'nutritionist' && /diet plan was updated/.test(note?.title) && rec === 1900,
      `Status ${r.status}; stored target ${p?.targetKcal}; author ${p?.by?.name} (${p?.by?.role}); notice "${note?.title}"; record shows ${rec}`);
  } finally { s.close(); }
});

atc('ATC-M14-F31', { req: 'M14-FR5', objective: 'Diet plan numbers are checked and each problem is explained', input: 'Targets 300 and 6000 kcal; macros that do not add up to 1900; only some macros; an unknown status; an empty change', expected: 'Each refused with 400 and a clear message' }, async () => {
  const s = await start(patients());
  try {
    const bad = async (o) => (await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: dietBody(o) }));
    const r = [await bad({ targetKcal: 300 }), await bad({ targetKcal: 6000 }), await bad({ proteinG: 400, carbsG: 400, fatG: 100 }), await bad({ carbsG: undefined, fatG: undefined }), await bad({ status: 'maybe' }),
      await bad({ targetKcal: undefined, proteinG: undefined, carbsG: undefined, fatG: undefined, avoid: [], tips: [] })];
    const res = [/calorie target/, /calorie target/, /differs from the 1900 kcal target/, /together/, /Approve as is/, /Change at least one thing/];
    const all = r.every((x, i) => x.status === 400 && res[i].test(x.body.error));
    return check(all, r.map((x) => `${x.status} "${x.body.error}"`).join(' | '));
  } finally { s.close(); }
});

atc('ATC-M14-F32', { req: 'M14-FR10', objective: 'A trainer builds a workout plan from the exercise library only and the schedule is validated', input: 'Valid 7-day plan; then a plan with an invented exercise, 6 days, no sets, and a workout on a rest day', expected: 'Valid plan 200 and stored; each bad plan 400' }, async () => {
  const s = await start(patients());
  try {
    const ok = await s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'tr1', body: workoutBody() });
    const sched = workoutBody().schedule;
    const put = (schedule) => s.call('PUT', '/api/patients/pat1/plans/workout', { as: 'tr1', body: workoutBody({ schedule }) });
    const bad = [await put(sched.slice(0, 6)), await put(sched.map((d) => (d.day === 1 ? day(1, [{ exerciseId: 'made_up_move', sets: 1, reps: 5 }]) : d))),
      await put(sched.map((d) => (d.day === 3 ? day(3, [{ exerciseId: 'chair_squat', sets: 0, reps: 10 }]) : d))), await put(sched.map((d) => (d.day === 2 ? { day: 2, rest: true, items: [{ exerciseId: 'brisk_walk', sets: 1, seconds: 60 }] } : d)))];
    const stored = s.db.root.specialistPlans.pat1.workout.schedule.length;
    return check(ok.status === 200 && stored === 7 && bad.every((b) => b.status === 400), `Valid plan ${ok.status}, ${stored} days stored; bad plans: ${bad.map((b) => `${b.status} "${b.body.error}"`).join(' | ')}`);
  } finally { s.close(); }
});

atc('ATC-M14-F33', { req: 'M14-FR5', objective: 'A specialist can remove their plan and the patient is told Baymax\'s plan applies again', input: 'Nutritionist sets and then deletes the diet plan; a trainer tries to delete; delete again', expected: 'Trainer 403; nutritionist 200 and plan gone; patient notified "back to Baymax"; second delete 404' }, async () => {
  const s = await start(patients());
  try {
    await s.call('PUT', '/api/patients/pat1/plans/diet', { as: 'nut1', body: dietBody() });
    const t = (await s.call('DELETE', '/api/patients/pat1/plans/diet', { as: 'tr1' })).status;
    const n = (await s.call('DELETE', '/api/patients/pat1/plans/diet', { as: 'nut1' })).status;
    const gone = s.db.root.specialistPlans === undefined;
    const told = Object.values(s.db.root.users.pat1.inbox).some((x) => /back to Baymax/.test(x.title));
    const again = (await s.call('DELETE', '/api/patients/pat1/plans/diet', { as: 'nut1' })).status;
    return check(t === 403 && n === 200 && gone && told && again === 404, `Trainer ${t}; nutritionist ${n}; plan gone ${gone}; patient told ${told}; second delete ${again}`);
  } finally { s.close(); }
});

atc('ATC-M14-F34', { req: 'M14-FR9', objective: 'A nutritionist approves or flags a day of the shared food log, and a flag needs a reason', input: 'PUT diet-reviews: approve 2026-10-19; flag 2026-10-18 with a note; flag without a note', expected: '200, 200 with the patient told "flagged", then 400 "why you are flagging"' }, async () => {
  const d = patients();
  d.appointments.n1.shares = { healthSummary: true, foodLog7d: true, activity30d: false };
  const s = await start(d);
  try {
    const put = (date, body) => s.call('PUT', `/api/patients/pat1/diet-reviews/${date}`, { as: 'nut1', body });
    const a = await put('2026-10-19', { status: 'approved' });
    const f = await put('2026-10-18', { status: 'flagged', note: 'Too many fried items' });
    const none = await put('2026-10-17', { status: 'flagged' });
    const told = /flagged/.test(s.db.root.users.pat1.inbox['review-2026-10-18']?.title ?? '');
    return check(a.status === 200 && f.status === 200 && told && none.status === 400 && /why you are flagging/.test(none.body.error), `Approve ${a.status}; flag ${f.status}, patient told ${told}; flag without reason ${none.status} "${none.body.error}"`);
  } finally { s.close(); }
});

atc('ATC-M14-F35', { req: 'M14-FR11', objective: 'Registering as a specialist stores a pending application and grants nothing', input: 'Signed-in member "newbie" posts the form (and tries to set role=admin and another email)', expected: '201 pending; email taken from the account; no role; not listed; licence number not echoed back' }, async () => {
  const s = await start(baseData());
  try {
    const r = await s.call('POST', '/api/applications', { as: 'newbie', body: form({ email: 'attacker@evil.test', role: 'admin' }) });
    const me = (await s.call('GET', '/api/me', { as: 'newbie' })).body;
    return check(r.status === 201 && r.body.application.status === 'pending' && s.db.root.applications.newbie.email === 'newbie@example.com' && s.db.root.roles.newbie === undefined && s.db.root.specialists.newbie === undefined && me.role === 'user' && !JSON.stringify(me).includes('PMDC'),
      `Status ${r.status} (${r.body.application?.status}); stored email ${s.db.root.applications.newbie?.email}; role ${s.db.root.roles.newbie}; listed ${!!s.db.root.specialists.newbie}; role seen by the app ${me.role}`);
  } finally { s.close(); }
});

atc('ATC-M14-F36', { req: 'M14-FR11', objective: 'The licence number is required and the form is checked', input: 'Registration without a licence number; with a bad type; with a negative fee', expected: 'Each 400' }, async () => {
  const s = await start(baseData());
  try {
    const post = (o) => s.call('POST', '/api/applications', { as: 'newbie', body: form(o) });
    const r = [await post({ licenseNumber: '' }), await post({ type: 'wizard' }), await post({ fees: { video: -5, chat: 100 } })];
    return check(r.every((x) => x.status === 400) && s.db.root.applications === undefined, r.map((x) => `${x.status} "${x.body.error}"`).join(' | '));
  } finally { s.close(); }
});

atc('ATC-M14-F37', { req: 'M14-FR11', objective: 'An administrator approves an application: role, verified public profile, and the specialist can sign in', input: 'Admin approves "newbie"; the licence number is checked; the new specialist opens the dashboard; approve again', expected: 'Role doctor; profile verified, no licence published; dashboard 200; second approval 409' }, async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: form() });
    const seen = (await s.call('GET', '/api/admin/applications', { as: 'adm1' })).body.applications[0].licenseNumber;
    const r = await s.call('POST', '/api/admin/applications/newbie/approve', { as: 'adm1' });
    const p = s.db.root.specialists.newbie;
    const dash = (await s.call('GET', '/api/dashboard', { as: 'newbie' })).status;
    const again = (await s.call('POST', '/api/admin/applications/newbie/approve', { as: 'adm1' })).status;
    return check(seen === 'PMDC-12345' && r.status === 200 && s.db.root.roles.newbie === 'doctor' && p.verified === true && p.licenseNumber === undefined && dash === 200 && again === 409,
      `Admin sees licence "${seen}"; approve ${r.status}; role ${s.db.root.roles.newbie}; verified ${p?.verified}; licence published ${p?.licenseNumber !== undefined}; new specialist dashboard ${dash}; second approval ${again}`);
  } finally { s.close(); }
});

atc('ATC-M14-F38', { req: 'M14-FR11', objective: 'Rejecting an application records the reason and never creates a role', input: 'Admin rejects "newbie" with a 301-character reason, then without a reason', expected: '400, then 200; no role' }, async () => {
  const s = await start(baseData(), { accounts });
  try {
    await s.call('POST', '/api/applications', { as: 'newbie', body: form() });
    const long = (await s.call('POST', '/api/admin/applications/newbie/reject', { as: 'adm1', body: { reason: 'x'.repeat(301) } })).status;
    const ok = (await s.call('POST', '/api/admin/applications/newbie/reject', { as: 'adm1', body: {} })).status;
    return check(long === 400 && ok === 200 && s.db.root.roles.newbie === undefined && s.db.root.applications.newbie.status === 'rejected', `Long reason ${long}; reject ${ok}; status ${s.db.root.applications.newbie?.status}; role ${s.db.root.roles.newbie}`);
  } finally { s.close(); }
});

atc('ATC-M16-F07', { req: 'M16-FR2', objective: 'Only an administrator reaches the admin routes', input: 'GET /api/admin/specialists as doctor, nutritionist, member, unknown user and anonymous; and as admin', expected: '401 anonymous; 403 for the four others; 200 for the admin' }, async () => {
  const s = await start(baseData(), { accounts: { ...accounts, 'nut1@example.com': 'nut1', 'member@example.com': 'pat1' } });
  try {
    const anon = (await s.call('GET', '/api/admin/specialists')).status;
    const denied = [];
    for (const who of ['doc1', 'nut1', 'pat1', 'nobody']) denied.push((await s.call('GET', '/api/admin/specialists', { as: who })).status);
    const admin = (await s.call('GET', '/api/admin/specialists', { as: 'adm1' })).status;
    return check(anon === 401 && denied.every((c) => c === 403) && admin === 200, `Anonymous ${anon}; doctor/nutritionist/member/unknown ${denied.join('/')}; administrator ${admin}`);
  } finally { s.close(); }
});

atc('ATC-M14-F39', { req: 'M14-FR15', objective: 'An administrator adds a specialist without ever setting a password', input: 'POST /api/admin/specialists with a new email', expected: '201; account created without a password; role and profile set; a link to choose a password is returned' }, async () => {
  const s = await start(baseData(), { accounts });
  try {
    const r = await s.call('POST', '/api/admin/specialists', { as: 'adm1', body: { email: 'New.Doctor@Example.com', name: 'Hina Malik', type: 'doctor', specialty: 'General medicine', fees: { video: 2500, chat: 1500 } } });
    const uid = r.body.uid ?? r.body.specialist?.uid;
    return check(r.status === 201 && r.body.created === true && !!uid && s.db.root.roles[uid] === 'doctor' && !!s.db.root.specialists[uid] && /reset/.test(r.body.resetLink ?? ''), `Status ${r.status}; created ${r.body.created}; role ${s.db.root.roles[uid]}; link returned ${!!r.body.resetLink}`);
  } finally { s.close(); }
});

atc('ATC-M14-F40', { req: 'M14-FR14', objective: 'Closing an account needs the word DELETE and a recent sign-in', input: 'DELETE /api/me with an empty body; with DELETE but an hour-old sign-in', expected: '400; then 401 "reauth-required"; nothing deleted' }, async () => {
  const s = await start(patients());
  try {
    const none = await s.call('DELETE', '/api/me', { as: 'doc1', body: {} });
    const stale = await s.call('DELETE', '/api/me', { as: 'doc1', body: { confirm: 'DELETE' }, old: true });
    return check(none.status === 400 && stale.status === 401 && stale.body.code === 'reauth-required' && s.db.root.roles.doc1 === 'doctor' && s.auth.deleted.length === 0, `Empty ${none.status}; stale sign-in ${stale.status} (${stale.body.code}); role kept ${s.db.root.roles.doc1}`);
  } finally { s.close(); }
});

atc('ATC-M14-F41', { req: 'M14-FR14', objective: 'Closing a specialist account cancels future bookings, frees the times, tells patients and keeps past records', input: 'Doctor closes the account (DELETE, recent sign-in)', expected: '2 bookings cancelled; past record kept; slots gone; patient told; role, profile and sign-in removed; others untouched' }, async () => {
  const s = await start(patients());
  try {
    const r = await s.call('DELETE', '/api/me', { as: 'doc1', body: { confirm: 'DELETE' } });
    const a = s.db.root.appointments;
    return check(r.status === 200 && r.body.cancelled === 2 && a.p1b.status === 'cancelled' && a.req.status === 'cancelled' && a.p1a.status === 'completed' && s.db.root.slots === undefined && /cancelled/.test(s.db.root.users.pat1.inbox['closed-p1b'].title) &&
      s.db.root.roles.doc1 === undefined && s.db.root.specialists.doc1 === undefined && s.auth.deleted.join() === 'doc1' && s.db.root.roles.nut1 === 'nutritionist' && a.n1.status === 'confirmed',
      `Status ${r.status}; cancelled ${r.body.cancelled}; future ${a.p1b.status}/${a.req.status}; past ${a.p1a.status}; slots left ${s.db.root.slots !== undefined}; sign-in deleted ${s.auth.deleted.join()}; nutritionist kept ${s.db.root.roles.nut1}`);
  } finally { s.close(); }
});

// =================================================================================================================================
// BUSINESS RULES: decision tables
// =================================================================================================================================
{ // DT-M14-4: may this person change this patient's plan?
  const T = 'DT-M14-4 May this account set a plan?';
  const rule = (id, who, kind, rel, want) => atc(id, {
    req: 'M14-FR5', objective: `Plan change: ${who}, ${kind} plan, ${rel}`, input: `${who} sends a ${kind} plan for ${rel}`, expected: `Status ${want}`, table: T,
    conds: { 'Account': who, 'Plan type': kind, 'Patient': rel }, actions: `Status ${want}`,
  }, async () => {
    const s = await start(patients());
    try {
      const uid = { Doctor: 'doc1', Nutritionist: 'nut1', Trainer: 'tr1', Member: 'pat1' }[who];
      const patient = { "own patient, recent appointment": 'pat1', 'own patient, appointment 40 days ago': 'pat2', 'only a pending request': 'pat3' }[rel] ?? 'pat2';
      const body = kind === 'diet' ? dietBody() : workoutBody();
      const r = await s.call('PUT', `/api/patients/${rel === "another specialist's patient" ? 'pat2' : patient}/plans/${kind}`, { as: uid, body });
      return check(r.status === want, `Status ${r.status}${r.body?.error ? ` ("${r.body.error}")` : ''}`);
    } finally { s.close(); }
  });
  rule('ATC-M14-B21', 'Nutritionist', 'diet', 'own patient, recent appointment', 200);
  rule('ATC-M14-B22', 'Doctor', 'diet', 'own patient, recent appointment', 200);
  rule('ATC-M14-B23', 'Trainer', 'diet', 'own patient, recent appointment', 403);
  rule('ATC-M14-B24', 'Trainer', 'workout', 'own patient, recent appointment', 200);
  rule('ATC-M14-B25', 'Doctor', 'workout', 'own patient, recent appointment', 200);
  rule('ATC-M14-B26', 'Nutritionist', 'workout', 'own patient, recent appointment', 403);
  rule('ATC-M14-B27', 'Doctor', 'diet', 'own patient, appointment 40 days ago', 400);
  rule('ATC-M14-B28', 'Doctor', 'diet', 'only a pending request', 404);
  rule('ATC-M14-B29', 'Nutritionist', 'diet', "another specialist's patient", 404);
  rule('ATC-M14-B30', 'Member', 'diet', 'own patient, recent appointment', 403);
}

{ // DT-M14-5: shared patient data
  const T = 'DT-M14-5 Is the patient\'s shared data shown?';
  const rule = (id, ticked, status, when, shown, offsetMs, st) => atc(id, {
    req: 'M14-FR4', objective: `Shared data: patient ticked ${ticked}, ${status}, ${when}`, input: `Patient ticked sharing: ${ticked}; appointment ${status}; doctor opens it ${when}`, expected: shown ? 'Shared data shown and the access logged' : 'Shared data not shown',
    table: T, conds: { 'Patient ticked sharing': ticked, 'Appointment status': status, 'Doctor opens it': when }, actions: shown ? 'Show and log' : 'Hide',
  }, async () => {
    const d = sessions();
    const start0 = NOW;
    Object.assign(d.appointments.a1, { status: st, startAt: start0, slotKey: String(start0), shares: { healthSummary: ticked === 'Yes', foodLog7d: ticked === 'Yes', activity30d: false } });
    if (st === 'requested') d.appointments.a1.meetingLink = '';
    const s = await start(d, { now: start0 + offsetMs });
    try {
      const r = await s.call('GET', '/api/appointments/a1', { as: 'doc1' });
      const got = r.body.sharedData != null;
      const logged = Object.values(s.db.root.accessLog?.a1 ?? {}).length === 1;
      return check(got === shown && (!shown || logged), `Shared data ${got ? 'shown' : 'hidden'}${got ? `, access logged ${logged}` : ''}${r.body.sharedLocked ? ` ("${r.body.sharedLocked}")` : ''}`);
    } finally { s.close(); }
  });
  rule('ATC-M16-B10', 'Yes', 'confirmed', '20 minutes before the start', true, -20 * MIN, 'confirmed');
  rule('ATC-M16-B11', 'No', 'confirmed', '20 minutes before the start', false, -20 * MIN, 'confirmed');
  rule('ATC-M16-B12', 'Yes', 'confirmed', '40 minutes before the start', false, -40 * MIN, 'confirmed');
  rule('ATC-M16-B13', 'Yes', 'confirmed', '10 minutes after the start', true, 10 * MIN, 'confirmed');
  rule('ATC-M16-B14', 'Yes', 'confirmed', '95 minutes after the start (slot ended + 65 min)', false, 95 * MIN, 'confirmed');
  rule('ATC-M16-B15', 'Yes', 'requested', '20 minutes before the start', false, -20 * MIN, 'requested');
  rule('ATC-M16-B16', 'Yes', 'cancelled', '20 minutes before the start', false, -20 * MIN, 'cancelled');
}

{ // DT-M14-6: status change timing
  const T = 'DT-M14-6 Status change by time';
  const rule = (id, change, when, offsetMs, want) => atc(id, {
    req: 'M14-FR7', objective: `Mark ${change}, ${when}`, input: `Doctor marks a confirmed appointment as ${change} ${when}`, expected: `Status ${want}`, table: T, conds: { 'Change to': change, 'Time': when }, actions: `Status ${want}`,
  }, async () => {
    const d = sessions();
    Object.assign(d.appointments.a1, { startAt: NOW, slotKey: String(NOW) });
    const s = await start(d, { now: NOW + offsetMs });
    try {
      const r = await s.call('POST', '/api/appointments/a1/status', { as: 'doc1', body: { status: { completed: 'completed', missed: 'no_show', cancelled: 'cancelled' }[change] } });
      return check(r.status === want, `Status ${r.status}${r.body?.error ? ` ("${r.body.error}")` : ''}`);
    } finally { s.close(); }
  });
  rule('ATC-M14-B31', 'completed', '1 minute before the start', -MIN, 400);
  rule('ATC-M14-B32', 'completed', 'at the start', 0, 200);
  rule('ATC-M14-B33', 'missed', '9 minutes after the start', 9 * MIN, 400);
  rule('ATC-M14-B34', 'missed', '10 minutes after the start', 10 * MIN, 200);
  rule('ATC-M14-B35', 'cancelled', '10 minutes after the start', 10 * MIN, 200);
  rule('ATC-M14-B36', 'cancelled', '30 minutes after the start (slot ended)', 30 * MIN, 400);
}

{ // DT-M14-7: answering a request
  const T = 'DT-M14-7 Answering a request';
  const rule = (id, action, state, want, who = 'doc1') => atc(id, {
    req: 'M14-FR12', objective: `${action} a request that is ${state}`, input: `Doctor tries to ${action} a request that is ${state}`, expected: `Status ${want}`, table: T, conds: { 'Action': action, 'Request is': state }, actions: `Status ${want}`,
  }, async () => {
    const s = await start(requests());
    try {
      const id = { 'waiting and in the future': 'r1', 'past its start time': 'late', "sent to another specialist": 'other', 'already confirmed': 'ok' }[state];
      if (state === 'already declined') { await s.call('POST', '/api/appointments/r2/decline', { as: 'doc1', body: {} }); }
      const r = await s.call('POST', `/api/appointments/${state === 'already declined' ? 'r2' : id}/${action}`, { as: who, body: {} });
      return check(r.status === want, `Status ${r.status}${r.body?.error ? ` ("${r.body.error}")` : ''}`);
    } finally { s.close(); }
  });
  rule('ATC-M14-B37', 'accept', 'waiting and in the future', 200);
  rule('ATC-M14-B38', 'decline', 'waiting and in the future', 200);
  rule('ATC-M14-B39', 'accept', 'past its start time', 400);
  rule('ATC-M14-B40', 'decline', 'past its start time', 400);
  rule('ATC-M14-B41', 'accept', 'already declined', 400);
  rule('ATC-M14-B42', 'accept', 'already confirmed', 400);
  rule('ATC-M14-B43', 'accept', 'sent to another specialist', 404);
}

{ // DT-M14-8: registration decisions
  const T = 'DT-M14-8 Registration decisions';
  const rule = (id, state, action, who, want) => atc(id, {
    req: 'M14-FR11', objective: `Application ${state}: ${who} chooses ${action}`, input: `Application is ${state}; ${who} sends "${action}"`, expected: `Status ${want}`, table: T, conds: { 'Application': state, 'Who acts': who, 'Action': action }, actions: `Status ${want}`,
  }, async () => {
    const s = await start(baseData(), { accounts });
    try {
      await s.call('POST', '/api/applications', { as: 'newbie', body: form() });
      if (state === 'approved') await s.call('POST', '/api/admin/applications/newbie/approve', { as: 'adm1' });
      if (state === 'holds another role') s.db.root.roles.newbie = 'trainer';
      const r = await s.call('POST', `/api/admin/applications/newbie/${action}`, { as: who === 'an administrator' ? 'adm1' : who === 'a doctor' ? 'doc1' : 'newbie' });
      return check(r.status === want, `Status ${r.status}${r.body?.error ? ` ("${r.body.error}")` : ''}`);
    } finally { s.close(); }
  });
  rule('ATC-M14-B44', 'pending', 'approve', 'an administrator', 200);
  rule('ATC-M14-B45', 'pending', 'reject', 'an administrator', 200);
  rule('ATC-M14-B46', 'approved', 'approve', 'an administrator', 409);
  rule('ATC-M14-B47', 'approved', 'reject', 'an administrator', 409);
  rule('ATC-M14-B48', 'holds another role', 'approve', 'an administrator', 409);
  rule('ATC-M14-B49', 'pending', 'approve', 'a doctor', 403);
  rule('ATC-M14-B50', 'pending', 'approve', 'the applicant', 403);
}

{ // DT-M14-9: closing an account
  const T = 'DT-M14-9 Closing an account';
  const rule = (id, confirm, signin, want, body, old) => atc(id, {
    req: 'M14-FR14', objective: `Close account: confirmation ${confirm}, sign-in ${signin}`, input: `DELETE /api/me with ${confirm}; sign-in ${signin}`, expected: `Status ${want}`, table: T, conds: { 'Typed DELETE': confirm, 'Signed in': signin }, actions: `Status ${want}`,
  }, async () => {
    const s = await start(patients());
    try {
      const r = await s.call('DELETE', '/api/me', { as: 'doc1', body, old });
      return check(r.status === want, `Status ${r.status}; role kept ${s.db.root.roles.doc1 === 'doctor'}`);
    } finally { s.close(); }
  });
  rule('ATC-M14-B51', 'Yes', 'recently', 200, { confirm: 'DELETE' }, false);
  rule('ATC-M14-B52', 'No', 'recently', 400, {}, false);
  rule('ATC-M14-B53', 'Wrong word', 'recently', 400, { confirm: 'delete me' }, false);
  rule('ATC-M14-B54', 'Yes', 'an hour ago', 401, { confirm: 'DELETE' }, true);
}
