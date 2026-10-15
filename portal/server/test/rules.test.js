import test from 'node:test';
import assert from 'node:assert/strict';
import {
  appointmentState, isListed, dashboardCounts, dayBounds, filterAppointments, greeting, normalizeAppointment, parseConsultationNote,
  parseProfileUpdate, sortToday, statusChangeProblem,
} from '../src/lib/rules.js';
import { MIN, NOW, appointment } from './helpers.js';

const a = (id, o) => normalizeAppointment(id, appointment(o));

test('the slot key wins over a separately stored start time', () => {
  const n = normalizeAppointment('x', { ...appointment(), startAt: 1, slotKey: String(NOW + 5 * MIN) });
  assert.equal(n.startAt, NOW + 5 * MIN);
  assert.equal(normalizeAppointment('x', { startAt: 'nope' }), null);
});

test('a booking waiting for payment, or with an unknown status, is never read as confirmed', () => {
  assert.equal(normalizeAppointment('x', appointment({ status: 'pending_payment' })).status, 'pending_payment');
  assert.equal(normalizeAppointment('x', appointment({ status: 'weird' })).status, 'pending_payment');
  assert.equal(isListed(normalizeAppointment('x', appointment({ status: 'pending_payment' }))), false);
  assert.equal(isListed(normalizeAppointment('x', appointment({ status: 'confirmed' }))), true);
});

test('payment shows status, method and total, never anything else', () => {
  const paid = normalizeAppointment('x', appointment({ payment: { status: 'paid', method: 'card', total: 2150, mode: 'sandbox', transactionId: 'TXN-1', brand: 'Visa', last4: '4242', reference: 'r' } }));
  assert.deepEqual(paid.payment, { status: 'paid', method: 'card', total: 2150, test: true, transactionId: 'TXN-1' });
  assert.equal(normalizeAppointment('x', appointment({ payment: { status: 'paid', method: 'card', total: 1, mode: 'live' } })).payment.test, false);
  assert.equal(normalizeAppointment('x', appointment({ payment: { status: 'weird' } })).payment, null);
  assert.equal(normalizeAppointment('x', appointment()).payment, null);
});

test('only an https meeting link is passed on', () => {
  assert.equal(normalizeAppointment('x', appointment({ meetingLink: 'https://meet.example/room#a=b' })).meetingLink, 'https://meet.example/room#a=b');
  for (const bad of ['javascript:alert(1)', 'http://meet.example/x', 'https://a b', 'data:text/html,hi', '', null, 5]) {
    assert.equal(normalizeAppointment('x', appointment({ meetingLink: bad })).meetingLink, '', String(bad));
  }
});

test('greeting follows the specialist\'s own clock', () => {
  const at = (h, m = 0) => Date.UTC(2026, 9, 19, h, m) - 300 * MIN; // h:m in Pakistan
  assert.equal(greeting(at(9), 300), 'Good Morning');
  assert.equal(greeting(at(11, 59), 300), 'Good Morning');
  assert.equal(greeting(at(12), 300), 'Good Afternoon');
  assert.equal(greeting(at(17), 300), 'Good Afternoon');
  assert.equal(greeting(at(17, 1), 300), 'Good Evening');
});

test('a day runs from local midnight to local midnight', () => {
  const { start, end } = dayBounds(NOW, 300);
  assert.equal(start, Date.UTC(2026, 9, 18, 19, 0)); // 00:00 on the 19th in Pakistan
  assert.equal(end - start, 86_400_000);
  assert.ok(NOW >= start && NOW < end);
});

test('join, prepare and shared-data windows', () => {
  const x = a('1', { startAt: NOW });
  const st = (offsetMin) => appointmentState(x, NOW + offsetMin * MIN);
  assert.equal(st(-6).canJoin, false);
  assert.equal(st(-5).canJoin, true);
  assert.equal(st(29).canJoin, true);
  assert.equal(st(30).canJoin, false);
  assert.equal(st(-31).canPrepare, false);
  assert.equal(st(-30).canPrepare, true);
  assert.equal(st(30).canPrepare, false);
  assert.equal(st(-31).canViewShared, false);
  assert.equal(st(-30).canViewShared, true);
  assert.equal(st(89).canViewShared, true); // 30 minutes of session + 60 minutes grace
  assert.equal(st(90).canViewShared, false);
  assert.equal(st(10).phase, 'live');
  assert.equal(st(-10).phase, 'upcoming');
  assert.equal(st(40).phase, 'past');
  const cancelled = a('2', { startAt: NOW, status: 'cancelled' });
  assert.equal(appointmentState(cancelled, NOW).canJoin, false);
  assert.equal(appointmentState(cancelled, NOW).canViewShared, false);
});

test('today\'s list puts live sessions first, then upcoming in time order, then finished ones', () => {
  const list = [
    a('past', { startAt: NOW - 120 * MIN }),
    a('later', { startAt: NOW + 180 * MIN }),
    a('live', { startAt: NOW - 10 * MIN }),
    a('soon', { startAt: NOW + 30 * MIN }),
  ];
  assert.deepEqual(sortToday(list, NOW).map((x) => x.id), ['live', 'soon', 'later', 'past']);
});

test('filters combine: status, date range and part of the patient name', () => {
  const list = [
    a('1', { patientName: 'Ayesha Khan', startAt: NOW }),
    a('2', { patientName: 'Bilal Ahmed', startAt: NOW + 86_400_000, status: 'completed' }),
    a('3', { patientName: 'Ayesha Noor', startAt: NOW + 2 * 86_400_000 }),
  ];
  assert.deepEqual(filterAppointments(list, { q: 'AYESHA' }).map((x) => x.id), ['1', '3']);
  assert.deepEqual(filterAppointments(list, { status: 'completed' }).map((x) => x.id), ['2']);
  assert.deepEqual(filterAppointments(list, { from: NOW + 1, to: NOW + 2 * 86_400_000 }).map((x) => x.id), ['2']);
  assert.deepEqual(filterAppointments(list, { status: 'confirmed', q: 'noor' }).map((x) => x.id), ['3']);
  assert.equal(filterAppointments(list, { status: 'bogus' }).length, 3); // unknown filter values are ignored
});

test('dashboard counts only what the data can say', () => {
  const list = [
    a('today1', { startAt: NOW + 60 * MIN, patientId: 'p1' }),
    a('today2', { startAt: NOW + 120 * MIN, patientId: 'p2' }),
    a('cancelled', { startAt: NOW + 90 * MIN, patientId: 'p3', status: 'cancelled' }),
    a('needsNotes', { startAt: NOW - 3 * 86_400_000, status: 'completed', patientId: 'p1' }),
    a('hasNotes', { startAt: NOW - 4 * 86_400_000, status: 'completed', patientId: 'p4', consultation: { notes: 'done', updatedAt: 1 } }),
    a('nextWeek', { startAt: NOW + 10 * 86_400_000, patientId: 'p5' }),
  ];
  const c = dashboardCounts(list, NOW, 300);
  assert.equal(c.consultationsToday, 2);
  assert.equal(c.upcoming7Days, 2);
  assert.equal(c.patients, 4); // p1 (twice), p2, p4, p5; the cancelled booking's patient p3 is not counted
});

test('status changes obey the clock', () => {
  const x = a('1', { startAt: NOW });
  assert.match(statusChangeProblem(x, 'completed', NOW - MIN), /not started/);
  assert.equal(statusChangeProblem(x, 'completed', NOW), null);
  assert.match(statusChangeProblem(x, 'no_show', NOW + 9 * MIN), /10 minutes/);
  assert.equal(statusChangeProblem(x, 'no_show', NOW + 10 * MIN), null);
  assert.equal(statusChangeProblem(x, 'cancelled', NOW + 10 * MIN), null);
  assert.match(statusChangeProblem(x, 'cancelled', NOW + 30 * MIN), /ended/);
  assert.match(statusChangeProblem(a('2', { status: 'completed' }), 'cancelled', NOW), /already completed/);
  assert.match(statusChangeProblem(x, 'banana', NOW + 5 * MIN), /Unknown/);
});

test('notes: prescriptions are for doctors only, and something must be written', () => {
  assert.deepEqual(parseConsultationNote({ notes: ' Rest. ' }, 'trainer').value, { notes: 'Rest.', prescription: '' });
  assert.match(parseConsultationNote({ notes: 'x', prescription: 'Drug A' }, 'nutritionist').error, /doctor/);
  assert.equal(parseConsultationNote({ notes: 'x', prescription: 'Drug A' }, 'doctor').value.prescription, 'Drug A');
  assert.match(parseConsultationNote({}, 'doctor').error, /Write some/);
  assert.match(parseConsultationNote({ notes: 'x'.repeat(5001) }, 'doctor').error, /5000/);
  assert.match(parseConsultationNote({ notes: 5 }, 'doctor').error, /text/);
});

test('profile edits are validated field by field', () => {
  assert.match(parseProfileUpdate({}).error, /Nothing/);
  assert.match(parseProfileUpdate({ fees: { video: -1, chat: 5 } }).error, /Fees/);
  assert.match(parseProfileUpdate({ fees: { video: 10.5, chat: 5 } }).error, /Fees/);
  assert.match(parseProfileUpdate({ availability: { days: [], start: '09:00', end: '17:00', slotMinutes: 30 } }).error, /working day/);
  assert.match(parseProfileUpdate({ availability: { days: [1], start: '17:00', end: '09:00', slotMinutes: 30 } }).error, /after/);
  assert.match(parseProfileUpdate({ availability: { days: [1], start: '9:00', end: '17:00', slotMinutes: 30 } }).error, /09:00/);
  assert.match(parseProfileUpdate({ availability: { days: [1], start: '09:00', end: '17:00', slotMinutes: 5 } }).error, /slot/);
  assert.match(parseProfileUpdate({ bio: 'x'.repeat(601) }).error, /600/);
  const ok = parseProfileUpdate({ bio: ' Hi ', fees: { video: 2000, chat: 1000 }, availability: { days: [3, 1, 1], start: '09:00', end: '12:00', slotMinutes: 30 }, available: false });
  assert.deepEqual(ok.value.availability.days, [1, 3]);
  assert.equal(ok.value.bio, 'Hi');
  assert.equal(ok.value.available, false);
  // fields outside the allowed list are ignored, never written
  assert.deepEqual(Object.keys(parseProfileUpdate({ bio: 'x', rating: 5, type: 'doctor' }).value), ['bio']);
});
