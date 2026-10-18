// Cross-module flows on the real phone: Module 4 → 5 (plan exercise opens a posture session) and Module 5 → 6 (session opens the voice coach).
import { atc, byDesc, byDescContains, launchApp, requireSignedIn, tap, visible } from '../helpers/atc.js';

describe('Cross-module flows (real device)', () => {
  beforeEach(async () => {
    await launchApp();
  });

  it('ATC-INT-A01 a planned exercise starts a posture session (Module 4 → 5)', async function () {
    await atc(this, {
      id: 'ATC-INT-A01',
      req: 'M5-SFR3',
      objective: 'Workout plan → exercise detail → Start exercise opens Module 5 mode selection',
      input: 'Workout tab → first exercise → "Start exercise"',
      expected: '"Select Mode" with Camera Detection / Manual Guidance',
    }, async () => {
      await requireSignedIn();
      await tap(byDesc('Workout'), 'Workout tab');
      await tap(byDescContains('Open details'), 'first exercise card');
      await tap(byDescContains('Start exercise'), 'Start exercise');
      const mode = await visible(byDesc('Select Mode'));
      const manual = await visible(byDescContains('Manual Guidance'), 3000);
      return { ok: mode && manual, actual: `Mode selection ${mode}; Manual Guidance option ${manual}` };
    });
  });

  it('ATC-INT-A02 a posture session opens the voice coach (Module 5 → 6)', async function () {
    await atc(this, {
      id: 'ATC-INT-A02',
      req: 'M6-SFR3',
      objective: 'Manual Guidance session → "Ask Baymax" opens the voice assistant bound to the session',
      input: 'Posture check → Exercise library → Bodyweight Squat → Manual Guidance → Continue → "Ask Baymax"',
      expected: 'Voice assistant shown ("Listening..." or "Voice input unavailable")',
    }, async () => {
      await requireSignedIn();
      await tap(byDesc('Open menu'), 'menu');
      await tap(byDesc('Posture check'), 'Posture check');
      await tap(byDesc('Exercise library'), 'Exercise library tab');
      await tap(byDescContains('Bodyweight Squat'), 'Bodyweight Squat');
      await tap(byDescContains('Manual Guidance'), 'Manual Guidance option');
      await tap(byDesc('Continue'), 'Continue');
      await tap(byDesc('Ask Baymax'), 'Ask Baymax');
      const ok = (await visible(byDesc('Listening...'), 6000)) || (await visible(byDesc('Voice input unavailable'), 2000));
      return { ok, actual: `Voice assistant state shown ${ok}` };
    });
  });
});
