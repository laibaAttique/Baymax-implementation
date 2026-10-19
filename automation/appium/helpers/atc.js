// Shared helpers for the Baymax Appium cases.
//
// Every case is identified by its report Test Case ID. Its outcome is written as one JSON line to reports/appium_results.jsonl
// together with what was actually observed and a screenshot, so the report's tables come from real runs:
//   Passed  — the expected UI state was observed on the phone.
//   Failed  — the app was reachable but showed something else.
//   Blocked — the case could not be executed for a reason outside the app (for example the phone refused input injection);
//             the reason is the device's own error text. A blocked case is reported as skipped in the JUnit XML, never as passed.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const resultsFile = path.join(root, 'reports', 'appium_results.jsonl');
const shotsDir = path.join(root, 'screenshots');
fs.mkdirSync(path.dirname(resultsFile), { recursive: true });
fs.mkdirSync(shotsDir, { recursive: true });

export const PACKAGE = process.env.BAYMAX_PACKAGE || 'com.example.app';

/** A precondition outside the app is not met; the case is reported as Blocked with this reason. */
export class Blocked extends Error {}

const injectionBlocked = /INJECT_EVENTS|Injecting input events/i;

function record(entry) {
  fs.appendFileSync(resultsFile, `${JSON.stringify(entry)}\n`);
}

async function screenshot(id) {
  try {
    const file = path.join(shotsDir, `${id}.png`);
    await browser.saveScreenshot(file);
    return path.relative(root, file).replaceAll('\\', '/');
  } catch {
    return null;
  }
}

/**
 * Runs one documented case. [body] returns {ok, actual}. Use inside a Mocha `function () {}` so `ctx.skip()` is available.
 */
export async function atc(ctx, meta, body) {
  const started = new Date().toISOString();
  let status, actual;
  try {
    const r = await body();
    status = r.ok ? 'Passed' : 'Failed';
    actual = r.actual;
  } catch (e) {
    const msg = String(e?.message || e);
    if (e instanceof Blocked || injectionBlocked.test(msg)) {
      status = 'Blocked';
      actual = injectionBlocked.test(msg)
        ? 'Blocked: the phone refused the tap (MIUI "USB debugging (Security settings)" is off): ' +
          (msg.match(/[^\n]*(INJECT_EVENTS|Injecting input events)[^\n]*/i)?.[0] || msg).trim().slice(0, 300)
        : `Blocked: ${msg}`;
    } else {
      status = 'Failed';
      actual = `Error: ${msg.split('\n')[0].slice(0, 300)}`;
    }
  }
  const shot = await screenshot(meta.id);
  record({ ...meta, actual, status, screenshot: shot, started, tool: 'Appium 3 + UiAutomator2 (WebdriverIO), real device' });
  if (status === 'Blocked') ctx.skip();
  if (status === 'Failed') throw new Error(`${meta.id}: ${actual}`);
}

// ---------------------------------------------------------------- selectors (accessibility labels, never coordinates)
// Flutter exposes widget text and semantic labels as the Android content-description.
export const byDesc = (text) => $(`android=new UiSelector().description(${JSON.stringify(text)})`);
export const byDescContains = (text) => $(`android=new UiSelector().descriptionContains(${JSON.stringify(text)})`);
export const byDescStarts = (text) => $(`android=new UiSelector().descriptionStartsWith(${JSON.stringify(text)})`);

export async function visible(el, timeout = 10000) {
  try {
    await el.waitForExist({ timeout });
    return true;
  } catch {
    return false;
  }
}

/** Taps an element found by its label; throws the device's error (e.g. input injection refused) unchanged. */
export async function tap(el, what) {
  if (!(await visible(el))) throw new Error(`"${what}" not found on screen`);
  await el.click();
}

/** (Re)starts the app at its launcher activity without clearing data, and waits for Flutter's first frame. */
export async function launchApp() {
  await driver.execute('mobile: activateApp', { appId: PACKAGE });
  await driver.pause(1500);
}

export async function currentPackage() {
  return driver.getCurrentPackage();
}

/** The user must be signed in for plan-dependent cases; the suite never types credentials. */
export async function requireSignedIn() {
  if (await visible(byDesc('Open menu'), 15000)) return;
  if (await visible(byDescContains('Sign in'), 2000) || (await visible(byDescContains('Log in'), 1000))) {
    throw new Blocked('the app shows the sign-in screen; sign in on the phone first (the suite does not enter credentials)');
  }
  throw new Error('the Baymax dashboard did not appear');
}
