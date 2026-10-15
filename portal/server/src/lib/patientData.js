// What a specialist may see about a patient: only the parts the patient ticked when booking (FR36.5), and only inside the
// appointment's window. Everything is read here, on the server; the browser never talks to the database.

const DAY = 86_400_000;

const dateKey = (ms) => new Date(ms).toISOString().slice(0, 10);

function ageFrom(dob, now) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob ?? '');
  if (!m) return null;
  const born = Date.UTC(+m[1], +m[2] - 1, +m[3]);
  return Math.floor((now - born) / (365.2425 * DAY));
}

export async function loadSharedData(db, appointment, now) {
  const { patientId, shares } = appointment;
  const out = {};
  if (shares.healthSummary) {
    const p = (await db.get(`users/${patientId}/profile`)) ?? null;
    out.healthSummary = p && {
      fullName: p.fullName ?? appointment.patientName,
      age: ageFrom(p.dob, now),
      gender: p.gender ?? null,
      height: p.height ?? null,
      weight: p.weight ?? null,
      targetWeight: p.targetWeight ?? null,
      primaryGoal: p.primaryGoal ?? null,
      activityLevel: p.activityLevel ?? null,
      workoutFrequency: p.workoutFrequency ?? null,
      bmi: p.calculatedBMI ?? null,
      healthClassification: p.healthClassification ?? null,
      medicalConditions: p.medicalConditions ?? [],
      foodAllergies: p.foodAllergies ?? [],
      medications: p.medications ?? '',
    };
  }
  if (shares.foodLog7d) {
    const log = (await db.get(`users/${patientId}/foodLog`)) ?? {};
    const days = [];
    for (let i = 0; i < 7; i++) {
      const key = dateKey(now - i * DAY);
      const entries = Object.values(log[key] ?? {}).map((e) => ({
        meal: e.meal, name: e.name, kcal: e.kcal ?? 0, protein: e.protein ?? 0, carbs: e.carbs ?? 0, fat: e.fat ?? 0,
      }));
      days.push({
        date: key,
        entries,
        totalKcal: Math.round(entries.reduce((s, e) => s + e.kcal, 0)),
      });
    }
    out.foodLog7d = days;
  }
  if (shares.activity30d) {
    const act = (await db.get(`users/${patientId}/activity`)) ?? {};
    const days = [];
    for (let i = 0; i < 30; i++) {
      const key = dateKey(now - i * DAY);
      if (act[key]) days.push({ date: key, minutes: act[key].minutes ?? null, kcal: act[key].kcal ?? null });
    }
    out.activity30d = days;
  }
  return out;
}
