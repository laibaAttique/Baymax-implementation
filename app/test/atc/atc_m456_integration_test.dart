// Automated INTEGRATION test cases for Modules 4, 5 and 6 (report section 5.4): real services wired together, no mocks between the
// modules under test (only device I/O — camera frames, microphone, speaker, cloud store — is replaced by fakes).
// IDs: ATC-INT-34..   Run: flutter test test/atc/atc_m456_integration_test.dart
import 'dart:io';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/voice/intent_service.dart';
import 'package:app/services/voice/posture_cue_announcer.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_session/plan_progress.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter_test/flutter_test.dart' hide same;

import '../support/pose_fixtures.dart';
import '../support/session_fakes.dart';
import '../support/voice_fakes.dart';
import 'atc_helper.dart';

HealthProfile _p({List<String> conditions = const [], double weight = 64}) => HealthProfile(
    fullName: 'Test User', dob: '1996-04-04', gender: 'Female', heightValue: 168, weightValue: weight, medicalConditions: conditions,
    primaryGoal: 'Maintain & Stay Fit', activityLevel: 'Moderately Active', workoutFrequency: 6);

const _rules = RuleBasedClassifier();

// 2026-10-19 is a Monday (weekday index 0).
final _monday = DateTime(2026, 10, 19, 18);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FoodDatabase foods;
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });
  tearDown(() => AppPermissions.instance = const AppPermissions());

  PersonalizedPlan plan(HealthProfile p) => PlanGenerator(foods).generate(p, _rules.classify(p), readiness: const WorkoutReadiness(clearance: true));
  Iterable<PlannedExercise> all(PersonalizedPlan p) => p.week.whereType<WorkoutDay>().expand((d) => d.exercises);

  (PlanProgress, List<String>, FakeStore) progressFor(PersonalizedPlan p) {
    final marked = <String>[];
    final store = FakeStore();
    final progress = PlanProgress(
      store: store,
      currentPlan: () => p,
      currentPlanId: () => 'plan-a',
      weightKg: () => 64,
      markDay: (date, day, kg) async => marked.add('${PlanProgress.dateKey(date)} ${day.name}'),
      now: () => _monday,
    );
    return (progress, marked, store);
  }

  group('Integration Testing: Module 2 → Module 4 (health classification drives the plan)', () {
    atc('ATC-INT-34', req: 'M4-FR2', objective: 'The Module 2 health category sets the intensity ceiling of the generated plan',
        input: 'Profile with "Heart Disease" (classified Cardiac), clearance given', expected: 'Every scheduled exercise with a MET value is light or moderate',
        run: () {
          final p = _p(conditions: ['Heart Disease']);
          final cat = _rules.classify(p).category;
          final bands = all(plan(p)).map((e) => e.exercise.intensityBand).whereType<IntensityBand>().toList();
          final vig = bands.where((b) => b == IntensityBand.vigorous).length;
          return check(cat == 'Cardiac' && bands.isNotEmpty && vig == 0, 'Category $cat; ${bands.length} exercises checked; vigorous $vig');
        });
    atc('ATC-INT-35', req: 'M4-FR1', objective: 'A condition recorded in Module 2 removes restricted exercises from the Module 4 plan',
        input: 'Profile with "Hypertension"', expected: 'No HIIT- or plyometric-tagged exercise in the week', run: () {
          final ex = all(plan(_p(conditions: ['Hypertension']))).toList();
          final bad = ex.where((e) => e.exercise.tags.any(const {'hiit', 'plyo'}.contains)).map((e) => e.exercise.id).toList();
          return check(ex.isNotEmpty && bad.isEmpty, '${ex.length} planned entries; restricted entries: ${bad.isEmpty ? 'none' : bad.join(', ')}');
        });
  });

  group('Integration Testing: Module 4 → Module 5 (plan entries open posture sessions)', () {
    atc('ATC-INT-36', req: 'M5-SFR3', objective: 'A planned exercise starts a posture session with the planned dose and a camera configuration',
        input: 'Generated plan, Monday; every entry converted to a session', expected: 'Sets, reps and seconds carried over; every entry resolves a camera capability',
        run: () {
          final day = plan(_p()).week[0]!;
          var mismatched = 0, camera = 0;
          for (final pe in day.exercises) {
            final s = SessionExercise.fromPlanned(pe);
            if (s.id != pe.exercise.id || s.sets != pe.sets || s.reps != pe.reps || s.seconds != pe.seconds) mismatched++;
            if (MovementPatterns.forSession(s).supportsCameraTracking) camera++;
          }
          return check(mismatched == 0, '${day.exercises.length} entries; dose mismatches $mismatched; $camera with camera tracking, '
              '${day.exercises.length - camera} Manual Guidance only');
        });
  });

  group('Integration Testing: Module 5 → Module 4 (sessions complete planned exercises)', () {
    atc('ATC-INT-37', req: 'M4-SFR4', objective: 'Completing every main exercise of the day marks the plan day done once',
        input: 'Monday plan; each main entry finished in Manual Guidance with all sets', expected: 'Day marked once in the Module 4 activity record',
        run: () async {
          final p = plan(_p());
          final (progress, marked, _) = progressFor(p);
          final c = WorkoutSessionController()..store = FakeStore();
          final day = p.week[0]!;
          for (final i in PlanProgress.mainEntries(day)) {
            final ex = SessionExercise.fromPlanned(day.exercises[i]);
            c.start(WorkoutSessionRequest(exercise: ex, plan: progress.linkFor(0, i)), SessionMode.manual);
            for (var s = 0; s < ex.sets; s++) {
              c.recordManualSet(ex.reps);
            }
            await progress.record(c.finish());
          }
          return check(marked.length == 1 && progress.dayMarkedToday(0), 'Marked ${marked.length}× (${marked.join(', ')}); done today ${progress.completedToday(0).length} entries');
        });
    atc('ATC-INT-38', req: 'M4-SFR4', objective: 'A skipped or incomplete session does not complete the planned exercise',
        input: 'Monday entry 1: one set of several, then skipped', expected: 'Entry not done; day not marked', run: () async {
          final p = plan(_p());
          final (progress, marked, _) = progressFor(p);
          final c = WorkoutSessionController()..store = FakeStore();
          final ex = SessionExercise.fromPlanned(p.week[0]!.exercises[1]);
          c.start(WorkoutSessionRequest(exercise: ex, plan: progress.linkFor(0, 1)), SessionMode.manual);
          c.recordManualSet(ex.reps);
          await progress.record(c.finish());
          c.start(WorkoutSessionRequest(exercise: ex, plan: progress.linkFor(0, 1)), SessionMode.manual);
          await progress.record(c.finish(skipped: true));
          return check(!progress.isDoneToday(0, 1) && marked.isEmpty, 'Entry done ${progress.isDoneToday(0, 1)}; day marks ${marked.length}');
        });
  });

  group('Integration Testing: Module 5 → Module 6 (posture results reach the voice assistant)', () {
    atc('ATC-INT-39', req: 'M6-SFR2', objective: 'A posture correction from the camera engine is spoken once by the cue announcer',
        input: 'Camera squat session; about 3 s at the bottom with 75° forward lean (limit 60°)', expected: '"Keep your back straight" spoken exactly once (rate-limited)', run: () async {
          final s = WorkoutSessionController()..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final out = FakeSpeechOutput();
          final cues = PostureCueAnnouncer(session: s, output: out, now: () => _monday)..attach();
          final e = PostureEngine(ExerciseFormRules.forExercise('squat')!);
          for (final f in (Motion().hold(400).moveTo(95, 900).hold(3000, torsoLean: 75)).frames) {
            s.updatePosture(e.process(f), angleLabel: 'Knee');
          }
          await _settle();
          cues.detach();
          final hits = out.spoken.where((t) => t.startsWith('Keep your back straight')).length;
          return check(out.spoken.length == 1 && hits == 1, 'Spoken ${out.spoken.length}: ${out.spoken.join(' | ')}');
        });
    atc('ATC-INT-40', req: 'M6-SFR2', objective: 'Asking "how\'s my form" answers from the live posture analysis',
        input: 'Same faulty descent; then "How\'s my form?"', expected: 'Reply "Here is what to fix: Keep your back straight…"', run: () async {
          AppPermissions.instance = FakePermissions();
          final s = WorkoutSessionController()..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final e = PostureEngine(ExerciseFormRules.forExercise('squat')!);
          for (final f in (Motion().hold(400).moveTo(95, 900, torsoLean: 75)).frames) {
            s.updatePosture(e.process(f), angleLabel: 'Knee');
          }
          final a = VoiceAssistantController(recognizer: FakeSpeechRecognizer(), output: FakeSpeechOutput(), intents: RuleBasedIntentService(), session: s, schedule: const FakeSchedule());
          await a.submitText("How's my form?");
          final text = a.response?.text ?? '';
          await a.close();
          return check(text.startsWith('Here is what to fix: Keep your back straight'), 'Reply "$text"');
        });
    atc('ATC-INT-41', req: 'M6-FR19.3', objective: 'The rep count spoken by the assistant equals the camera counter', input: '3 squats counted by the camera engine; "how many reps"',
        expected: 'Reply states 3 reps', run: () async {
          AppPermissions.instance = FakePermissions();
          final s = WorkoutSessionController()..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final e = PostureEngine(ExerciseFormRules.forExercise('squat')!);
          for (final f in (Motion().hold(400).squat().squat().squat()).frames) {
            s.updatePosture(e.process(f), angleLabel: 'Knee');
          }
          final a = VoiceAssistantController(recognizer: FakeSpeechRecognizer(), output: FakeSpeechOutput(), intents: RuleBasedIntentService(), session: s, schedule: const FakeSchedule());
          await a.submitText('how many reps');
          final text = a.response?.text ?? '';
          await a.close();
          return check(s.reps == 3 && text.contains("You've completed 3 reps"), 'Camera counter ${s.reps}; reply "$text"');
        });
  });

  group('Integration Testing: Module 6 → Module 5 (voice commands control the posture session)', () {
    atc('ATC-INT-42', req: 'M6-SFR3', objective: 'A spoken "pause" stops rep counting until "resume"',
        input: 'Camera session; "pause workout"; 2 squats while paused; "resume workout"; 1 squat', expected: 'Paused then active; frames while paused ignored', run: () async {
          AppPermissions.instance = FakePermissions();
          final s = WorkoutSessionController()..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final a = VoiceAssistantController(recognizer: FakeSpeechRecognizer(), output: FakeSpeechOutput(), intents: RuleBasedIntentService(), session: s, schedule: const FakeSchedule());
          final e = PostureEngine(ExerciseFormRules.forExercise('squat')!);
          await a.submitText('pause workout');
          final paused = s.status;
          final m = Motion().hold(400).squat().squat();
          for (final f in m.frames) {
            s.updatePosture(e.process(f), angleLabel: 'Knee');
          }
          final whilePaused = s.reps;
          await a.submitText('resume workout');
          final resumed = s.status;
          await a.close();
          return check(paused == SessionStatus.paused && whilePaused == 0 && resumed == SessionStatus.active,
              'After pause: ${paused.name}; reps shown while paused $whilePaused; after resume: ${resumed.name}');
        });
    atc('ATC-INT-43', req: 'M6-SFR3', objective: 'Ending a session by voice needs confirmation before the session is asked to finish', input: '"stop workout", then "yes"',
        expected: 'Confirmation asked first, session still running; after "yes" a finish is requested from the session screen', run: () async {
          AppPermissions.instance = FakePermissions();
          final store = FakeStore();
          final s = WorkoutSessionController()
            ..store = store
            ..start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
          final a = VoiceAssistantController(recognizer: FakeSpeechRecognizer(), output: FakeSpeechOutput(), intents: RuleBasedIntentService(), session: s, schedule: const FakeSchedule());
          await a.submitText('stop workout');
          final afterStop = s.hasActiveSession;
          final ask = a.response?.text ?? '';
          await a.submitText('yes');
          await _settle();
          final ended = s.finishRequested;
          await a.close();
          return check(afterStop && ask.contains('Do you want to end') && ended,
              'After "stop": still active $afterStop, asked "${ask.split('?').first}?"; after "yes": finish requested ${s.finishRequested}, active ${s.hasActiveSession}');
        });
  });

  group('Integration Testing: end-to-end Modules 2 → 4 → 5 → 6', () {
    atc('ATC-INT-44', req: 'M4-SFR4', objective: 'Profile → plan → posture sessions with voice queries → plan day completed',
        input: 'Healthy profile; Monday plan; each main entry done in Manual Guidance; "how many reps" asked in each', expected: 'Voice replies match the logged reps; Monday marked done once; every session saved',
        run: () async {
          AppPermissions.instance = FakePermissions();
          final p = plan(_p());
          final (progress, marked, _) = progressFor(p);
          final store = FakeStore();
          final c = WorkoutSessionController()..store = store;
          final a = VoiceAssistantController(recognizer: FakeSpeechRecognizer(), output: FakeSpeechOutput(), intents: RuleBasedIntentService(), session: c, schedule: const FakeSchedule());
          final day = p.week[0]!;
          var replyMismatch = 0, sessions = 0;
          for (final i in PlanProgress.mainEntries(day)) {
            final ex = SessionExercise.fromPlanned(day.exercises[i]);
            c.start(WorkoutSessionRequest(exercise: ex, plan: progress.linkFor(0, i)), SessionMode.manual);
            for (var s = 0; s < ex.sets; s++) {
              c.recordManualSet(ex.reps);
            }
            await a.submitText('how many reps');
            if (ex.reps > 0 && !(a.response?.text ?? '').contains('${c.reps}')) replyMismatch++;
            await progress.record(c.finish());
            sessions++;
          }
          await _settle();
          await a.close();
          return check(replyMismatch == 0 && marked.length == 1 && store.saved.length == sessions,
              '$sessions sessions; voice reply mismatches $replyMismatch; saved ${store.saved.length}; day marked ${marked.length}×');
        });
  });
}
