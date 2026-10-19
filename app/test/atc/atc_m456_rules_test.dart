// Automated BUSINESS-RULE test cases for Modules 4, 5 and 6 (report section 5.3). Every table is a decision table: the conditions are
// the columns of the report's table, one case per rule (column). IDs: ATC-M4-B01.., ATC-M5-B01.., ATC-M6-B01..
// Run: flutter test test/atc/atc_m456_rules_test.dart
import 'dart:io';

import 'package:app/models/health_profile.dart';
import 'package:app/models/plan.dart';
import 'package:app/models/workout_readiness.dart';
import 'package:app/models/workout_session.dart';
import 'package:app/services/app_permissions.dart';
import 'package:app/services/exercise_catalog.dart';
import 'package:app/services/exercise_library.dart';
import 'package:app/services/exercise_repository.dart';
import 'package:app/services/food_database.dart';
import 'package:app/services/health_classifier.dart';
import 'package:app/services/plan_generator.dart';
import 'package:app/services/posture/exercise_form_rules.dart';
import 'package:app/services/posture/movement_patterns.dart';
import 'package:app/services/posture/posture_engine.dart';
import 'package:app/services/voice/intent_service.dart';
import 'package:app/services/voice/speech_recognizer.dart';
import 'package:app/services/voice/voice_assistant_controller.dart';
import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:app/services/workout_session/workout_session_controller.dart';
import 'package:flutter_test/flutter_test.dart' hide same;

import '../support/pose_fixtures.dart';
import '../support/voice_fakes.dart';
import 'atc_helper.dart';

HealthProfile _p({List<String> conditions = const [], double weight = 70, double height = 170, String dob = '1996-01-01'}) => HealthProfile(
    fullName: 'Test User', dob: dob, gender: 'Female', heightValue: height, weightValue: weight, medicalConditions: conditions,
    primaryGoal: 'Maintain & Stay Fit', activityLevel: 'Moderately Active', workoutFrequency: 4);

const _rules = RuleBasedClassifier();

Exercise _ex(String id, {String impact = 'low', List<String> tags = const [], double met = 4, List<String> joints = const []}) => Exercise(
    id: id, name: id, icon: '', group: 'legs', muscles: const ['Quadriceps'], impact: impact, level: 1, met: met, compendium: '02022',
    steps: const ['x'], tags: tags, joints: joints);

void main() {
  late FoodDatabase foods;
  setUpAll(() {
    ExerciseLibrary.loadFromJsonString(File('assets/data/exercises.json').readAsStringSync());
    ExerciseCatalog.loadFromJsonString(File('assets/data/exercise_catalog.json').readAsStringSync());
    foods = FoodDatabase.fromJsonString(File('assets/data/foods.json').readAsStringSync());
  });

  PersonalizedPlan plan(HealthProfile p, WorkoutReadiness r) => PlanGenerator(foods).generate(p, _rules.classify(p), readiness: r);
  SafetyAssessment assess(HealthProfile p, {WorkoutReadiness readiness = const WorkoutReadiness(clearance: true)}) {
    final cls = _rules.classify(p);
    return SafetyRuleRepository.engine.assess(HealthFacts.from(p, cls, 'Moderate', readiness: readiness),
        profile: ClassificationProfiles.forCategory(cls.category));
  }

  // ================================================================ Module 4
  group('Business Rule Testing: Module 4 workout plan generation', () {
    // DT-M4-1: may a plan be generated at all? (screening gate)
    void gate(String id, String symptoms, String heart, String clearance, String data, HealthProfile p, WorkoutReadiness r, String want, String wantRule) => atc(id,
        req: 'M4-SFR3', objective: 'Screening gate: symptoms $symptoms, heart condition $heart, clearance $clearance, profile data $data',
        input: 'Conditions ${p.medicalConditions.isEmpty ? 'none' : p.medicalConditions.join(', ')}; symptoms ${r.symptoms.isEmpty ? 'none' : r.symptoms.join(', ')}; '
            'clearance ${r.clearance}; weight ${p.weightValue.round()} kg',
        expected: want == 'eligible' ? 'Plan generated' : 'No plan; gate $want ($wantRule)',
        table: 'DT-M4-1 Screening gate (may a plan be generated?)',
        conds: {'Warning symptoms': symptoms, 'Heart condition': heart, "Doctor's clearance": clearance, 'Weight recorded': data},
        actions: want == 'eligible' ? 'Generate plan' : 'Block plan: $want ($wantRule)',
        run: () {
          final pl = plan(p, r);
          final status = pl.gate?.status.name ?? 'eligible';
          final rules = pl.gate?.ruleIds ?? const <String>[];
          final ok = want == 'eligible' ? pl.workoutAvailable && pl.workoutDays > 0 : !pl.workoutAvailable && status == want && rules.contains(wantRule);
          return check(ok, 'Gate $status${rules.isEmpty ? '' : ' (${rules.join(', ')})'}; workout days ${pl.workoutDays}');
        });
    gate('ATC-M4-B01', 'No', 'No', 'Not needed', 'Yes', _p(), const WorkoutReadiness(), 'eligible', '');
    gate('ATC-M4-B02', 'Yes', 'No', 'Not needed', 'Yes', _p(), const WorkoutReadiness(symptoms: {'chest_pain'}), 'needsClearance', 'SCR-SYMPTOMS');
    gate('ATC-M4-B03', 'No', 'Yes', 'No', 'Yes', _p(conditions: ['Heart Disease']), const WorkoutReadiness(clearance: false), 'needsClearance', 'SCR-CARDIAC-CLEARANCE');
    gate('ATC-M4-B04', 'No', 'Yes', 'Yes', 'Yes', _p(conditions: ['Heart Disease']), const WorkoutReadiness(clearance: true), 'eligible', '');
    gate('ATC-M4-B05', 'No', 'No', 'Not needed', 'No', _p(weight: 0), const WorkoutReadiness(), 'needsInfo', 'SCR-MISSING-WEIGHT');

    // DT-M4-2: is a single exercise scheduled for this user? (exercise eligibility)
    void elig(String id, String profile, String impact, String tag, String injury, String met, HealthProfile p, WorkoutReadiness r, Exercise e, ExerciseOutcome want) => atc(id,
        req: 'M4-FR1', objective: 'Exercise eligibility: $profile, impact $impact, tag $tag, injury $injury, MET $met',
        input: 'Profile ${_rules.classify(p).category}; exercise impact ${e.impact}, tags ${e.tags.isEmpty ? 'none' : e.tags.join(', ')}, MET ${e.met}; injuries ${r.injuries.isEmpty ? 'none' : r.injuries.join(', ')}',
        expected: 'Outcome ${want.name}',
        table: 'DT-M4-2 Exercise eligibility (rules checked in order: impact, tags, intensity, injured joint)',
        conds: {'Health profile': profile, 'Exercise impact': impact, 'Restricted tag': tag, 'Injured joint loaded': injury, 'MET recorded': met},
        actions: want.name,
        run: () {
          final d = assess(p, readiness: r).decide(e);
          return same(d.outcome, want, say: 'Outcome ${d.outcome.name}${d.ruleIds.isEmpty ? '' : '; rules ${d.ruleIds.join(', ')}'}');
        });
    elig('ATC-M4-B06', 'Healthy', 'Low', 'None', 'No', 'Yes', _p(), const WorkoutReadiness(clearance: true), _ex('a'), ExerciseOutcome.eligible);
    elig('ATC-M4-B07', 'Hypertension', 'Low', 'HIIT', 'No', 'Yes', _p(conditions: ['Hypertension']), const WorkoutReadiness(clearance: true), _ex('b', tags: ['hiit']),
        ExerciseOutcome.excluded);
    elig('ATC-M4-B08', 'Obese', 'High', 'None', 'No', 'Yes', _p(weight: 100), const WorkoutReadiness(clearance: true), _ex('c', impact: 'high'), ExerciseOutcome.excluded);
    elig('ATC-M4-B09', 'Healthy', 'High', 'None', 'Knee', 'Yes', _p(), const WorkoutReadiness(clearance: true, injuries: {'knee'}), _ex('d', impact: 'high', joints: ['knee']),
        ExerciseOutcome.excluded);
    elig('ATC-M4-B10', 'Healthy', 'Low', 'None', 'Knee', 'Yes', _p(), const WorkoutReadiness(clearance: true, injuries: {'knee'}), _ex('e', joints: ['knee']),
        ExerciseOutcome.eligibleWithModifications);
    elig('ATC-M4-B11', 'Hypertension', 'Low', 'None', 'No', 'No', _p(conditions: ['Hypertension']), const WorkoutReadiness(clearance: true), _ex('f', met: 0),
        ExerciseOutcome.requiresInformation);

    // DT-M4-3: equipment availability for dataset exercises.
    void equip(String id, String owned, String needs, Set<String> have, String exerciseId, bool want) => atc(id,
        req: 'M4-SFR3', objective: 'Equipment rule: owns $owned, exercise needs $needs', input: 'Owned equipment ${have.isEmpty ? 'none' : have.join(', ')}; exercise $exerciseId',
        expected: want ? 'Offered for planning' : 'Not offered', table: 'DT-M4-3 Equipment availability (dataset exercises)',
        conds: {'Equipment owned': owned, 'Exercise needs': needs}, actions: want ? 'Offer' : 'Do not offer',
        run: () {
          final offered = ExerciseCatalog.plannableWith(have).any((e) => e.id == exerciseId);
          return same(offered, want, say: 'Offered: $offered');
        });
    equip('ATC-M4-B12', 'Dumbbell', 'Dumbbell', {'dumbbell'}, 'Dumbbell_Bicep_Curl', true);
    equip('ATC-M4-B13', 'None', 'Dumbbell', {}, 'Dumbbell_Bicep_Curl', false);
    equip('ATC-M4-B14', 'Dumbbell', 'Barbell', {'dumbbell'}, 'Barbell_Squat', false);
  });

  // ================================================================ Module 5
  group('Business Rule Testing: Module 5 posture detection', () {
    final squat = ExerciseFormRules.forExercise('squat')!;

    // DT-M5-1: which camera features an exercise gets (capability level).
    void cap(String id, String exerciseId, Exercise Function() e, String level, bool tracks, bool form, bool validatedScore) => atc(id,
        req: 'M5-FR15.1', objective: 'Camera capability of $exerciseId: $level', input: 'Exercise $exerciseId',
        expected: 'Camera ${tracks ? 'available' : 'not available'}; form checks ${form ? 'yes' : 'no'}; score labelled validated ${validatedScore ? 'yes' : 'no'}',
        table: 'DT-M5-1 Camera capability level → features offered', conds: {'Capability level': level},
        actions: !tracks ? 'Manual Guidance only, reason shown' : (validatedScore ? 'Camera; validated posture score and corrections' : 'Camera; corrections, score not labelled validated'),
        run: () {
          final c = ExerciseRepository.postureFor(e());
          final ok = c.level.name == level && c.supportsCameraTracking == tracks && c.supportsFormEvaluation == form && c.scoreValidated == validatedScore;
          return check(ok, 'Level ${c.level.name}; camera ${c.supportsCameraTracking}; form ${c.supportsFormEvaluation}; validated score ${c.scoreValidated}'
              '${c.unsupportedReason == null ? '' : '; reason "${c.unsupportedReason}"'}');
        });
    cap('ATC-M5-B01', 'squat', () => ExerciseLibrary.byId('squat')!, 'validatedForm', true, true, true);
    cap('ATC-M5-B02', 'Barbell_Squat', () => ExerciseCatalog.byId('Barbell_Squat')!, 'experimentalForm', true, true, false);
    cap('ATC-M5-B03', 'Standing_Calf_Raises', () => ExerciseCatalog.byId('Standing_Calf_Raises')!, 'notSupported', false, false, false);

    // DT-M5-2: is a repetition counted?
    void rep(String id, String depth, String speed, Motion m, int reps, int partial) => atc(id,
        req: 'M5-FR16.3', objective: 'Rep acceptance: depth reached $depth, duration ≥ minimum $speed', input: 'One squat (${depth == 'Yes' ? 'to 88°' : 'turning at 125°'}, ${speed == 'Yes' ? '1.8 s' : '0.3 s'})',
        expected: '$reps rep, $partial partial', table: 'DT-M5-2 Repetition acceptance', conds: {'Turn-around depth reached': depth, 'Duration ≥ 600 ms': speed},
        actions: reps == 1 ? 'Count rep' : (partial == 1 ? 'Partial attempt (lowers score)' : 'Ignore as noise'),
        run: () {
          final e = PostureEngine(squat);
          for (final f in m.frames) {
            e.process(f);
          }
          return check(e.reps == reps && e.partialReps == partial, 'Reps ${e.reps}; partial ${e.partialReps}');
        });
    rep('ATC-M5-B04', 'Yes', 'Yes', Motion().hold(400).squat(), 1, 0);
    rep('ATC-M5-B05', 'No', 'Yes', Motion().hold(400).squat(depth: 125), 0, 1);
    rep('ATC-M5-B06', 'Yes', 'No', Motion().hold(400).squat(downMs: 150, upMs: 150), 0, 0);

    // DT-M5-3: landmark visibility.
    void vis(String id, String visible, double v, bool measured) => atc(id,
        req: 'M5-FR16.4', objective: 'Landmark visibility ${v.toStringAsFixed(1)} (threshold 0.5)', input: 'Squat frame at 120°, landmark visibility $v',
        expected: measured ? 'Angle measured' : 'No measurement; nothing counted', table: 'DT-M5-3 Landmark visibility', conds: {'Required landmarks visible (≥ 0.5)': visible},
        actions: measured ? 'Measure joint angles' : 'Skip frame, ask user to move into view',
        run: () {
          final m = PoseAnalyzer.measure(squatFrame(120, 0, visibility: v), squat);
          return check((m != null) == measured, m == null ? 'Measurement: none' : 'Measured ${m.primaryAngle.toStringAsFixed(0)}°');
        });
    vis('ATC-M5-B07', 'Yes', 0.9, true);
    vis('ATC-M5-B08', 'No', 0.3, false);

    // DT-M5-4: is a correction shown?
    void fb(String id, String fault, String persists, double lean, int ms, bool shown) => atc(id,
        req: 'M5-FR16.2', objective: 'Correction trigger: fault $fault, persists ≥ 3 frames $persists', input: 'Descent with ${lean.round()}° forward lean for ${ms} ms (limit 60°)',
        expected: shown ? '"Keep your back straight" shown' : 'No correction', table: 'DT-M5-4 Correction feedback trigger',
        conds: {'Form fault present': fault, 'Persists ≥ 3 frames': persists}, actions: shown ? 'Show and speak correction' : 'No correction',
        run: () {
          final e = PostureEngine(squat);
          final m = Motion().hold(400).moveTo(130, 400).moveTo(125, ms, torsoLean: lean).moveTo(120, 100);
          final msgs = [for (final f in m.frames) e.process(f).feedback.message];
          final hit = msgs.where((s) => s.startsWith('Keep your back straight')).length;
          return check((hit > 0) == shown, 'Frames with the correction: $hit of ${msgs.length}');
        });
    fb('ATC-M5-B09', 'No', 'n/a', 10, 600, false);
    fb('ATC-M5-B10', 'Yes', 'No', 75, 66, false);
    fb('ATC-M5-B11', 'Yes', 'Yes', 75, 600, true);

    // DT-M5-5: does a session count as completing the planned exercise?
    void done(String id, String sets, String skipped, int recorded, bool skip, bool want) => atc(id,
        req: 'M5-SFR3', objective: 'Plan completion: all sets $sets, skipped $skipped', input: 'Manual squat session, 2 sets planned; $recorded set(s) recorded; ${skip ? 'Skip' : 'Finish'}',
        expected: 'completedTarget $want', table: 'DT-M5-5 Planned exercise completion', conds: {'All planned sets done': sets, 'Skipped': skipped},
        actions: want ? 'Mark done today' : 'Not marked done',
        run: () {
          final c = WorkoutSessionController();
          final ex = SessionExercise.fromExercise(ExerciseLibrary.byId('squat')!, sets: 2);
          c.start(WorkoutSessionRequest(exercise: ex), SessionMode.manual);
          for (var i = 0; i < recorded; i++) {
            c.recordManualSet(ex.reps);
          }
          final got = c.finish(skipped: skip).completedTarget;
          return same(got, want, say: 'completedTarget $got');
        });
    done('ATC-M5-B12', 'Yes', 'No', 2, false, true);
    done('ATC-M5-B13', 'No', 'No', 1, false, false);
    done('ATC-M5-B14', 'Yes', 'Yes', 2, true, false);
  });

  // ================================================================ Module 6
  group('Business Rule Testing: Module 6 voice assistant', () {
    Future<(VoiceAssistantController, FakeSpeechRecognizer, FakeSpeechOutput, FakePermissions, WorkoutSessionController)> make({bool active = false}) async {
      final rec = FakeSpeechRecognizer(), out = FakeSpeechOutput(), perm = FakePermissions();
      AppPermissions.instance = perm;
      final s = WorkoutSessionController();
      if (active) s.start(const WorkoutSessionRequest(exercise: squatExercise), SessionMode.camera);
      final a = VoiceAssistantController(recognizer: rec, output: out, intents: RuleBasedIntentService(), session: s, schedule: const FakeSchedule());
      return (a, rec, out, perm, s);
    }

    // DT-M6-1: spoken session commands act only on a real session.
    void cmd(String id, String said, String state, bool active, bool pausedFirst, String wantStatus, String wantText) => atc(id,
        req: 'M6-SFR3', objective: 'Voice command "$said" with session $state', input: 'Recognised text "$said"; session $state',
        expected: 'Session $wantStatus; reply contains "$wantText"', table: 'DT-M6-1 Voice session control',
        conds: {'Command': said, 'Session state': state}, actions: 'Session $wantStatus; reply "$wantText…"',
        run: () async {
          final (a, _, _, _, s) = await make(active: active);
          if (pausedFirst) s.pause();
          await a.submitText(said);
          final text = a.response?.text ?? '';
          final ok = s.status.name == wantStatus && text.contains(wantText);
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, 'Session ${s.status.name}; reply "$text"');
        });
    cmd('ATC-M6-B01', 'pause workout', 'active', true, false, 'paused', 'Paused');
    cmd('ATC-M6-B02', 'resume workout', 'paused', true, true, 'active', 'Resuming');
    cmd('ATC-M6-B03', 'pause workout', 'none', false, false, 'idle', 'no active workout session');
    cmd('ATC-M6-B04', 'my knee hurts', 'active', true, false, 'paused', 'Please stop the exercise now');

    // DT-M6-2: microphone permission.
    void mic(String id, String perm, PermissionOutcome o, String wantState, bool wantSettings) => atc(id,
        req: 'M6-FR19.2', objective: 'Microphone permission $perm', input: 'Assistant opened; microphone $perm', expected: 'State $wantState; settings link $wantSettings',
        table: 'DT-M6-2 Microphone permission', conds: {'Microphone permission': perm},
        actions: wantState == 'listening' ? 'Listen' : (wantSettings ? 'Explain, offer Open Settings' : 'Explain, offer Try again'),
        run: () async {
          final (a, rec, _, p, _) = await make();
          p.microphone = o;
          await a.startListening();
          final ok = a.state.name == wantState && a.settingsNeeded == wantSettings && (rec.listenCalls > 0) == (wantState == 'listening');
          final msg = 'State ${a.state.name}; settings link ${a.settingsNeeded}; listen calls ${rec.listenCalls}';
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, msg);
        });
    mic('ATC-M6-B05', 'granted', PermissionOutcome.granted, 'listening', false);
    mic('ATC-M6-B06', 'denied', PermissionOutcome.denied, 'unavailable', false);
    mic('ATC-M6-B07', 'permanently denied', PermissionOutcome.permanentlyDenied, 'unavailable', true);

    // DT-M6-3: recognition result (simulated recogniser; not microphone validation).
    void recog(String id, String result, void Function(FakeSpeechRecognizer) feed, bool reply, String wantText) => atc(id,
        req: 'M6-FR19.1', objective: 'Recognition result: $result', input: 'Simulated recogniser returns $result', expected: reply ? 'Reply shown and spoken' : 'Message "$wantText"; nothing spoken',
        table: 'DT-M6-3 Speech recognition result (simulated recogniser)', conds: {'Recognition result': result},
        actions: reply ? 'Answer and speak' : 'Show retry message',
        run: () async {
          final (a, rec, out, _, _) = await make();
          await a.startListening();
          feed(rec);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final shown = reply ? (a.response?.text ?? '') : (a.errorMessage ?? '');
          final ok = reply ? out.spoken.length == 1 && shown.contains(wantText) : out.spoken.isEmpty && shown.contains(wantText);
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, '${reply ? 'Reply' : 'Message'} "$shown"; spoken ${out.spoken.length}');
        });
    recog('ATC-M6-B08', 'final text "how many reps"', (r) => r.hear('how many reps', isFinal: true), true, 'no active workout session');
    recog('ATC-M6-B09', 'no match', (r) => r.fail(SpeechErrorKind.noMatch), false, "didn't catch that");
    recog('ATC-M6-B10', 'timeout (silence)', (r) => r.fail(SpeechErrorKind.timeout), false, "didn't hear anything");

    // DT-M6-4: spoken output.
    void tts(String id, String works, bool w) => atc(id,
        req: 'M6-FR19.3', objective: 'Text-to-speech ${w ? 'works' : 'fails'}', input: '"hello"; speech output ${w ? 'available' : 'fails'}',
        expected: w ? 'Reply shown and spoken' : 'Reply still shown; failure flagged', table: 'DT-M6-4 Spoken reply', conds: {'Speech output works': works},
        actions: w ? 'Show and speak' : 'Show reply, flag that it was not spoken',
        run: () async {
          final (a, _, out, _, _) = await make();
          out.works = w;
          await a.submitText('hello');
          final ok = a.response != null && a.speechOutputFailed == !w;
          final msg = 'Reply shown ${a.response != null}; output failed ${a.speechOutputFailed}';
          await a.close();
          AppPermissions.instance = const AppPermissions();
          return check(ok, msg);
        });
    tts('ATC-M6-B11', 'Yes', true);
    tts('ATC-M6-B12', 'No', false);
  });
}
