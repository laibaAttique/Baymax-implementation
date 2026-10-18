// Module 5 — Posture detection screens, on the real phone (Appium + UiAutomator2).
// UI automation checks navigation and what the screens show. It does NOT prove that pose detection, rep counting or corrections
// are accurate on real people: that evidence comes from the posture engine tests, the real-photo replay and the manual device checklist.
import { atc, Blocked, byDesc, byDescContains, launchApp, requireSignedIn, tap, visible } from '../helpers/atc.js';

async function openPostureHome() {
  await requireSignedIn();
  await tap(byDesc('Open menu'), 'menu');
  await tap(byDesc('Posture check'), 'Posture check in the menu');
}

async function openSquatModeSelection() {
  await openPostureHome();
  await tap(byDesc('Exercise library'), 'Exercise library tab');
  await tap(byDescContains('Bodyweight Squat'), 'Bodyweight Squat');
}

describe('Module 5: posture detection (real device)', () => {
  beforeEach(async () => {
    await launchApp();
  });

  it('ATC-M5-A01 Posture check offers Today\'s workout, My plan and the Exercise library', async function () {
    await atc(this, {
      id: 'ATC-M5-A01',
      req: 'M5-SFR3',
      objective: 'Posture Detection home shows the plan-linked tabs and the library',
      input: 'Menu → "Posture check"',
      expected: 'Tabs "Today\'s workout", "My plan", "Exercise library"',
    }, async () => {
      await openPostureHome();
      const tabs = [];
      for (const t of ["Today's workout", 'My plan', 'Exercise library']) if (await visible(byDescContains(t), 4000)) tabs.push(t);
      return { ok: tabs.length === 3, actual: `Tabs found: ${tabs.join(', ') || 'none'}` };
    });
  });

  it('ATC-M5-A02 mode selection shows both modes and the camera consent', async function () {
    await atc(this, {
      id: 'ATC-M5-A02',
      req: 'M5-FR15.1',
      objective: 'Mode selection for a camera-supported exercise shows Camera Detection, Manual Guidance and the consent toggle',
      input: 'Exercise library → "Bodyweight Squat"',
      expected: '"Select Mode", "Camera Detection", "Manual Guidance", consent switch, "Continue", "Skip for now"',
    }, async () => {
      await openSquatModeSelection();
      const want = ['Select Mode', 'Camera Detection', 'Manual Guidance', 'Continue', 'Skip for now'];
      const seen = [];
      for (const t of want) if (await visible(byDescContains(t), 4000)) seen.push(t);
      const consent = await visible($('android=new UiSelector().className("android.widget.Switch")'), 3000);
      return { ok: seen.length === want.length && consent, actual: `Shown: ${seen.join(', ')}; consent switch ${consent}` };
    });
  });

  it('ATC-M5-A03 camera mode shows the on-device processing notice and live status chips', async function () {
    await atc(this, {
      id: 'ATC-M5-A03',
      req: 'M5-FR16.6',
      objective: 'Camera Detection with consent opens the camera screen with the privacy notice',
      input: 'Bodyweight Squat → consent on → Continue (camera permission already granted by the tester)',
      expected: '"Processing is done locally. No video is stored." and "Stop Session"',
    }, async () => {
      await openSquatModeSelection();
      await tap($('android=new UiSelector().className("android.widget.Switch")'), 'camera consent switch');
      await tap(byDesc('Continue'), 'Continue');
      if (await visible($('android=new UiSelector().packageName("com.android.permissioncontroller")'), 4000)) {
        throw new Blocked('the Android camera permission dialog is open; the tester must answer it on the phone');
      }
      const notice = await visible(byDesc('Processing is done locally. No video is stored.'));
      const stop = await visible(byDescContains('Stop Session'), 3000);
      return { ok: notice && stop, actual: `Notice shown ${notice}; Stop Session shown ${stop}` };
    });
  });

  it('ATC-M5-A04 manual guidance shows the timer, rep target and form checklist', async function () {
    await atc(this, {
      id: 'ATC-M5-A04',
      req: 'M5-FR17.2',
      objective: 'Manual Guidance opens with the set counter, checklist and response buttons',
      input: 'Bodyweight Squat → Manual Guidance → Continue',
      expected: '"Manual Guidance" title, "Proper Form", "Completed ✓", "Too Difficult"',
    }, async () => {
      await openSquatModeSelection();
      await tap(byDescContains('Manual Guidance'), 'Manual Guidance option');
      await tap(byDesc('Continue'), 'Continue');
      const want = ['Proper Form', 'Completed', 'Too Difficult'];
      const seen = [];
      for (const t of want) if (await visible(byDescContains(t), 5000)) seen.push(t);
      return { ok: seen.length === want.length, actual: `Shown: ${seen.join(', ') || 'none'}` };
    });
  });
});
