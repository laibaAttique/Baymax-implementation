// Module 6 (voice assistant) on the real phone, with the real speech-recognition and text-to-speech plugins.
// The microphone permission is read from the phone and never requested by the test (no native dialog); the case
// records which state the phone was in and asserts the UI for that state. Tapping a quick-action chip sends a fixed
// phrase (deterministic input) through the real intent engine, reply builder and text-to-speech.
// This is not validation of live speech recognition accuracy: nothing is spoken to the phone.
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/module6_voice_test.dart -d <device-id>
import 'package:app/screens/chatbot/chatbot_screen.dart';
import 'package:app/screens/voice_assistant/voice_assistant_screen.dart';
import 'package:app/services/user_session.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'helpers/navigation_helpers.dart';
import 'helpers/test_app.dart';
import 'helpers/test_fixtures.dart';

/// Opens the voice assistant the way a user does: Home → AI chatbot (Module 13) → mic button → Module 6 screen.
Future<void> openVoiceFromChatbot(WidgetTester t) async {
  await launchApp(t);
  await waitFor(t, find.text("TODAY'S WORKOUT").hitTestable());
  await tapOn(t, bySemantics('Open the AI chatbot'), what: 'the chatbot button');
  await waitFor(t, find.byType(ChatbotScreen), what: 'the chatbot');
  await tapOn(t, find.byTooltip('Voice assistant'), what: 'the voice assistant button');
  await waitFor(t, find.byType(VoiceAssistantScreen), what: 'the voice assistant');
}

/// The state shown after the assistant asked for the microphone (granted → listening, otherwise unavailable).
Future<String> waitForMicState(WidgetTester t) async {
  final listening = find.text('Listening...');
  final unavailable = find.text('Voice input unavailable');
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (count(listening) > 0) return 'listening';
    if (count(unavailable) > 0) return 'unavailable';
  }
  return 'none';
}

void main() {
  binding;
  module6Tests();
}

void module6Tests() {
  group('Module 6 voice assistant (real device)', () {
    deviceCase('ATC-DEV-M6-01', req: 'M6-FR19.1', file: 'module6_voice_test.dart',
        objective: 'The chatbot\'s mic opens the Module 6 voice assistant, which shows the state matching the phone\'s microphone permission',
        input: 'Home → AI chatbot (Module 13) → "Voice assistant"; microphone permission as set on the phone',
        expected: 'Voice assistant screen (not the chatbot); granted → "Listening..."; not granted → "Voice input unavailable" with the reason and "Try again"',
        body: (t) async {
          await startControlledSession(t);
          final mic = await DevicePermissions.statusOf(Permission.microphone);
          await openVoiceFromChatbot(t);
          final state = await waitForMicState(t);
          final ok = mic == 'granted'
              ? state == 'listening'
              : state == 'unavailable' && count(find.textContaining('Microphone access')) == 1 && count(find.text('Try again')) == 1;
          return Outcome(ok, 'Phone microphone permission: $mic; assistant state: $state; reason shown ${count(find.textContaining('Microphone access'))}; '
              '"Try again" ${count(find.text('Try again'))}; chatbot still on top: ${count(find.byType(ChatbotScreen).hitTestable())}');
        });

    deviceCase('ATC-DEV-M6-02', req: 'M6-FR19.3', file: 'module6_voice_test.dart',
        objective: 'A quick-action chip is answered from the real session state and spoken with the phone\'s text-to-speech',
        input: 'No active workout; tap the chip "How many reps?"',
        expected: 'Reply card says there is no active workout session (no invented numbers); text-to-speech reports no failure; at most 3 chips',
        body: (t) async {
          await startControlledSession(t);
          final assistant = VoiceAssistantController();
          await t.pumpWidget(MaterialApp(home: VoiceAssistantScreen(controller: assistant, autoListen: false)));
          await pumpFor(t, const Duration(seconds: 1));
          await tapOn(t, find.text('How many reps?'), what: 'the chip');
          await waitFor(t, find.textContaining('no active workout session'), timeout: const Duration(seconds: 25), what: 'the reply');
          await pumpFor(t, const Duration(seconds: 4)); // let the phone finish speaking
          final chips = count(find.byType(ActionChip));
          return Outcome(chips <= 3 && !assistant.speechOutputFailed,
              'Reply: "${assistant.response?.text}"; engine ${assistant.engineName}; speech output failed ${assistant.speechOutputFailed}; chips $chips');
        });

    deviceCase('ATC-DEV-M6-03', req: 'M6-FR19.3', file: 'module6_voice_test.dart',
        objective: '"What\'s my workout today?" is answered from the personalised plan',
        input: 'Test user\'s plan; tap the chip "What\'s my workout today?"',
        expected: 'Reply names today\'s plan day, or says today is a rest day, matching the plan',
        body: (t) async {
          await startControlledSession(t);
          final today = UserSession.instance.plan!.workoutFor(DateTime.now());
          final assistant = VoiceAssistantController();
          await t.pumpWidget(MaterialApp(home: VoiceAssistantScreen(controller: assistant, autoListen: false)));
          await pumpFor(t, const Duration(seconds: 1));
          await tapOn(t, find.text("What's my workout today?"), what: 'the chip');
          final end = DateTime.now().add(const Duration(seconds: 25));
          while (DateTime.now().isBefore(end) && assistant.response == null) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final reply = assistant.response?.text ?? '';
          final ok = today == null ? reply.toLowerCase().contains('rest') : reply.contains(today.name);
          await pumpFor(t, const Duration(seconds: 3));
          return Outcome(ok, 'Plan today: ${today?.name ?? 'rest day'}; reply "$reply"');
        });

    deviceCase('ATC-DEV-M6-04', req: 'M6-FR19.4', file: 'module6_voice_test.dart',
        objective: 'The close button leaves the voice assistant and the app stays usable',
        input: 'Home → chatbot → voice assistant → "Close voice assistant" → Back',
        expected: 'Voice assistant closed; chatbot shown; Back returns to Home',
        body: (t) async {
          await startControlledSession(t);
          await openVoiceFromChatbot(t);
          await waitForMicState(t);
          await tapOn(t, bySemantics('Close voice assistant'), what: 'the close button');
          await waitGone(t, find.byType(VoiceAssistantScreen), what: 'the voice assistant');
          final chat = count(find.byType(ChatbotScreen));
          await t.pageBack();
          await waitFor(t, find.text("TODAY'S WORKOUT").hitTestable(), what: 'Home');
          return Outcome(chat == 1, 'Voice assistant closed; chatbot shown $chat; Home shown after Back');
        });
  });
}
