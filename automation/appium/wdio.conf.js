// WebdriverIO + Appium (UiAutomator2) configuration for the Baymax real-device suite.
//
// The device, package and activity can be overridden with environment variables:
//   BAYMAX_UDID (default f3fd6781, the Redmi Note 11 used for the report), BAYMAX_PACKAGE (com.example.app).
// The suite never resets app data (noReset) so the tester's signed-in account and plan stay as they are, and it never grants
// permissions automatically: permission prompts are part of what Modules 5 and 6 are tested for.
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const udid = process.env.BAYMAX_UDID || 'f3fd6781';
const appPackage = process.env.BAYMAX_PACKAGE || 'com.example.app';

export const config = {
  runner: 'local',
  specs: ['./tests/**/*.e2e.js'],
  // Order matters only for readability of the report; every spec relaunches the app itself.
  suites: {
    m4: ['./tests/module4_workout.e2e.js'],
    m5: ['./tests/module5_posture.e2e.js'],
    m6: ['./tests/module6_voice.e2e.js'],
    cross: ['./tests/cross_module.e2e.js'],
  },
  maxInstances: 1,
  hostname: '127.0.0.1',
  port: 4723,
  path: '/',
  capabilities: [
    {
      platformName: 'Android',
      'appium:automationName': 'UiAutomator2',
      'appium:udid': udid,
      'appium:appPackage': appPackage,
      'appium:appActivity': '.MainActivity',
      'appium:noReset': true,
      'appium:autoGrantPermissions': false,
      // Do not install the io.appium.settings helper or change device settings (animations, locale, …).
      'appium:skipDeviceInitialization': true,
      'appium:disableWindowAnimation': false,
      'appium:newCommandTimeout': 180,
      'appium:uiautomator2ServerInstallTimeout': 180000,
      'appium:uiautomator2ServerLaunchTimeout': 120000,
      'appium:adbExecTimeout': 60000,
    },
  ],
  logLevel: 'warn',
  bail: 0,
  waitforTimeout: 15000,
  connectionRetryTimeout: 240000,
  connectionRetryCount: 1,
  services: [
    [
      'appium',
      {
        // The locally installed Appium 3 (node_modules) with the UiAutomator2 driver from package.json.
        args: { address: '127.0.0.1', port: 4723, logLevel: 'info' },
        logPath: path.join(here, 'reports'),
      },
    ],
  ],
  framework: 'mocha',
  mochaOpts: { ui: 'bdd', timeout: 180000 },
  reporters: [
    'spec',
    [
      'junit',
      {
        outputDir: path.join(here, 'reports', 'junit'),
        outputFileFormat: (o) => `appium-${o.cid}.xml`,
        // Skipped (blocked) tests keep their reason in the XML.
        addFileAttribute: true,
      },
    ],
  ],
};
