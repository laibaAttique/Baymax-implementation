'use client';

import type { ReactNode } from 'react';
import type { SharedData } from '@/lib/types';
import { Card } from '@/components/ui';
import { Bars } from '@/components/Bars';

/**
 * The patient's dashboard, built only from what the patient agreed to share: health summary tiles, calories per day with a chart and
 * every meal, workout minutes with a chart. [dayActions] adds buttons under a day of the food log (the nutritionist's review).
 */
export function PatientDashboard({ data, dayActions }: { data: SharedData; dayActions?: (date: string) => ReactNode }) {
  const h = data.healthSummary;
  const food = data.foodLog7d;
  const activity = data.activity30d;
  // oldest first, so the charts read left to right
  const foodBars = food ? [...food].reverse().map((d) => ({ label: d.date.slice(5), value: d.totalKcal })) : [];
  const activityBars = activity ? [...activity].reverse().map((d) => ({ label: d.date.slice(5), value: d.minutes ?? 0 })) : [];
  const loggedDays = food ? food.filter((d) => d.entries.length > 0) : [];
  const avgKcal = loggedDays.length ? Math.round(loggedDays.reduce((s, d) => s + d.totalKcal, 0) / loggedDays.length) : null;
  return (
    <>
      {h && (
        <Card title="Patient dashboard: health summary">
          <div className="tiles">
            <div className="tile"><span className="tile-value">{h.bmi ?? 'n/a'}</span><span className="tile-label">BMI</span></div>
            <div className="tile"><span className="tile-value">{h.healthClassification ?? 'n/a'}</span><span className="tile-label">Baymax health class</span></div>
            <div className="tile"><span className="tile-value">{h.weight ? `${h.weight.value} ${h.weight.unit}` : 'n/a'}</span><span className="tile-label">Weight{h.targetWeight ? ` (target ${h.targetWeight.value} ${h.targetWeight.unit})` : ''}</span></div>
            <div className="tile"><span className="tile-value">{h.age ?? 'n/a'}</span><span className="tile-label">Age</span></div>
          </div>
          <dl className="facts">
            <dt>Gender</dt><dd>{h.gender || 'Not given'}</dd>
            <dt>Height</dt><dd>{h.height ? `${h.height.value} ${h.height.unit}` : 'Not given'}</dd>
            <dt>Goal</dt><dd>{h.primaryGoal ?? 'Not given'}</dd>
            <dt>Activity</dt><dd>{h.activityLevel ?? 'Not given'}{h.workoutFrequency != null ? `, ${h.workoutFrequency} workouts a week` : ''}</dd>
            <dt>Medical conditions</dt><dd>{h.medicalConditions.length ? h.medicalConditions.join(', ') : 'None reported'}</dd>
            <dt>Food allergies</dt><dd>{h.foodAllergies.length ? h.foodAllergies.join(', ') : 'None reported'}</dd>
            <dt>Medicines</dt><dd>{h.medications || 'None reported'}</dd>
          </dl>
          <p className="muted small">Reported by the patient. The Baymax health class is decision support, not a diagnosis.</p>
        </Card>
      )}
      {food && (
        <Card title="Patient dashboard: calories, last 7 days">
          {loggedDays.length === 0 && !dayActions ? (
            <p className="muted">Nothing was logged in the last seven days.</p>
          ) : (
            <>
              {loggedDays.length > 0 && (
                <>
                  <div className="tiles">
                    <div className="tile"><span className="tile-value">{avgKcal} kcal</span><span className="tile-label">Average on the {loggedDays.length} day{loggedDays.length === 1 ? '' : 's'} logged</span></div>
                  </div>
                  <Bars title="Calories logged per day" data={foodBars} unit="kcal" />
                </>
              )}
              <details open={!!dayActions}>
                <summary>Every meal logged</summary>
                {food.map((d) => (
                  <div key={d.date} className="day">
                    <h3>{d.date} <span className="muted small">{d.totalKcal} kcal</span></h3>
                    {d.entries.length === 0 ? (
                      <p className="muted small">Nothing logged.</p>
                    ) : (
                      <ul className="plain">
                        {d.entries.map((e, i) => (
                          <li key={i}>{e.meal}: {e.name} <span className="muted small">{Math.round(e.kcal)} kcal · P {Math.round(e.protein)} · C {Math.round(e.carbs)} · F {Math.round(e.fat)}</span></li>
                        ))}
                      </ul>
                    )}
                    {dayActions && d.entries.length > 0 && dayActions(d.date)}
                  </div>
                ))}
              </details>
            </>
          )}
          <p className="muted small">Calories and macros are estimates from the patient&apos;s own entries.</p>
        </Card>
      )}
      {activity && (
        <Card title="Patient dashboard: workouts, last 30 days">
          {activity.length === 0 ? (
            <p className="muted">No completed workouts in the last 30 days.</p>
          ) : (
            <>
              <div className="tiles">
                <div className="tile"><span className="tile-value">{activity.length}</span><span className="tile-label">Workout days</span></div>
                <div className="tile"><span className="tile-value">{activity.reduce((s, d) => s + (d.minutes ?? 0), 0)} min</span><span className="tile-label">Total time</span></div>
              </div>
              <Bars title="Workout minutes per day" data={activityBars} unit="min" />
            </>
          )}
        </Card>
      )}
    </>
  );
}
