// Module 4 — Workout plan generation, on the real phone (Appium + UiAutomator2).
// These cases check what the signed-in user's own plan shows in the UI; they do not assess whether the plan is clinically safe.
import { atc, byDesc, byDescContains, byDescStarts, launchApp, requireSignedIn, tap, visible, currentPackage, PACKAGE } from '../helpers/atc.js';

describe('Module 4: workout plan (real device)', () => {
  before(async () => {
    await launchApp();
  });

  it('ATC-M4-A01 the app launches on the phone and the dashboard shows today\'s workout from the plan', async function () {
    await atc(this, {
      id: 'ATC-M4-A01',
      req: 'M4-FR5',
      objective: 'App launches on the real phone; the dashboard shows the Module 4 "Today\'s workout" card',
      input: 'Signed-in account on Redmi Note 11 (Android 13); app launched by Appium without clearing data',
      expected: `Foreground package ${PACKAGE}; "TODAY'S WORKOUT" card with a workout name or "Rest day"`,
    }, async () => {
      await requireSignedIn();
      const pkg = await currentPackage();
      const card = await visible(byDesc("TODAY'S WORKOUT"));
      let what = '';
      if (await visible(byDesc('Rest day'), 2000)) what = 'Rest day';
      else {
        const open = byDescStarts('Open the workout plan');
        if (await visible(open, 2000)) what = (await open.getAttribute('content-desc')).replaceAll('\n', ' / ');
      }
      return { ok: pkg === PACKAGE && card && what !== '', actual: `Foreground ${pkg}; card shown ${card}; card content "${what}"` };
    });
  });

  it('ATC-M4-A02 the Workout tab shows the weekly plan', async function () {
    await atc(this, {
      id: 'ATC-M4-A02',
      req: 'M4-FR5',
      objective: 'The Workout tab opens the generated weekly plan',
      input: 'Tap the "Workout" navigation tab',
      expected: '"Your workout plan" with intensity and days per week',
    }, async () => {
      await requireSignedIn();
      await tap(byDesc('Workout'), 'Workout tab');
      const title = await visible(byDesc('Your workout plan'));
      const summary = byDescContains('days a week');
      const line = (await visible(summary, 3000)) ? await summary.getAttribute('content-desc') : '';
      return { ok: title && line !== '', actual: `Title shown ${title}; summary "${line}"` };
    });
  });

  it('ATC-M4-A03 an exercise in the plan opens its detail with the dose and Start exercise', async function () {
    await atc(this, {
      id: 'ATC-M4-A03',
      req: 'M4-FR6',
      objective: 'A planned exercise opens its detail screen with the prescribed dose and a Start exercise button',
      input: 'Workout tab → first exercise card ("…. Open details")',
      expected: '"Sets" shown and "Start exercise" button present',
    }, async () => {
      await requireSignedIn();
      await tap(byDesc('Workout'), 'Workout tab');
      await tap(byDescContains('Open details'), 'first exercise card');
      const sets = await visible(byDesc('Sets'));
      const start = await visible(byDescContains('Start exercise'));
      return { ok: sets && start, actual: `Sets shown ${sets}; Start exercise shown ${start}` };
    });
  });
});
