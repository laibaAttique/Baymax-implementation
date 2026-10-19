// Module 6 — Voice assistant (workout voice coach), on the real phone (Appium + UiAutomator2).
// Module 6 is the voice assistant screen, not the Module 13 AI chatbot: the chatbot is only used as the entry point (its mic button).
// These cases check the screen and its states. They do NOT validate speech-recognition accuracy; nothing is spoken to the phone.
import { atc, byDesc, byDescContains, launchApp, requireSignedIn, tap, visible } from '../helpers/atc.js';

async function openVoiceAssistant() {
  await requireSignedIn();
  await tap(byDesc('Open the AI chatbot'), 'chatbot button');
  await tap(byDesc('Voice assistant'), 'Voice assistant (mic) button');
}

describe('Module 6: voice assistant (real device)', () => {
  beforeEach(async () => {
    await launchApp();
  });

  it('ATC-M6-A01 the voice assistant opens in a listening or explained-unavailable state', async function () {
    await atc(this, {
      id: 'ATC-M6-A01',
      req: 'M6-FR19.1',
      objective: 'The Module 6 voice assistant opens (not the chatbot) and shows its state',
      input: 'Chatbot → mic "Voice assistant"',
      expected: '"Listening..." (microphone granted) or "Voice input unavailable" with a reason; mic button labelled',
    }, async () => {
      await openVoiceAssistant();
      const listening = await visible(byDesc('Listening...'), 6000);
      const unavailable = !listening && (await visible(byDesc('Voice input unavailable'), 2000));
      const mic = (await visible(byDesc('Stop listening'), 2000)) || (await visible(byDesc('Start listening'), 1000));
      return { ok: (listening || unavailable) && mic, actual: `Listening ${listening}; unavailable ${unavailable}; mic button ${mic}` };
    });
  });

  it('ATC-M6-A02 closing the voice assistant returns to the previous screen', async function () {
    await atc(this, {
      id: 'ATC-M6-A02',
      req: 'M6-FR19.4',
      objective: 'The close button leaves the voice assistant',
      input: 'Voice assistant open → "Close voice assistant"',
      expected: 'Voice assistant gone; chatbot screen shown again',
    }, async () => {
      await openVoiceAssistant();
      await tap(byDesc('Close voice assistant'), 'close button');
      const gone = !(await visible(byDesc('Close voice assistant'), 2000));
      const back = await visible(byDesc('Voice assistant'), 4000);
      return { ok: gone && back, actual: `Assistant closed ${gone}; chatbot shown ${back}` };
    });
  });

  it('ATC-M6-A03 the chatbot screen is a different module from the voice assistant', async function () {
    await atc(this, {
      id: 'ATC-M6-A03',
      req: 'M6-FR19.1',
      objective: 'Module 13 chatbot and Module 6 voice assistant are separate screens',
      input: 'Open the AI chatbot only',
      expected: 'Chatbot shown with a "Voice assistant" entry; no voice-assistant listening UI',
    }, async () => {
      await requireSignedIn();
      await tap(byDesc('Open the AI chatbot'), 'chatbot button');
      const entry = await visible(byDesc('Voice assistant'));
      const listening = await visible(byDesc('Listening...'), 1500);
      return { ok: entry && !listening, actual: `Voice assistant entry ${entry}; listening UI on chatbot ${listening}` };
    });
  });
});
