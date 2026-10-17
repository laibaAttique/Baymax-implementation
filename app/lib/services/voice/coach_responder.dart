import '../../models/workout_session.dart';
import '../user_session.dart';
import '../workout_session/workout_session_controller.dart';
import 'intent_service.dart';

/// Today's planned workout, as far as the app knows it.
class TodaySchedule {
  final String name;
  final int durationMin;
  final List<SessionExercise> exercises;
  const TodaySchedule({required this.name, required this.durationMin, required this.exercises});
}

/// Where the voice coach gets schedule answers from.
///
/// INTEGRATION POINT (Workout Plan module): implement this if the plan is
/// later stored somewhere other than `UserSession.instance.plan`.
abstract class WorkoutScheduleProvider {
  /// False when no plan exists, so the coach says so instead of guessing.
  bool get hasPlan;

  /// Null on a rest day.
  TodaySchedule? today();
}

/// Reads the plan the app has already generated for the signed-in user.
class UserPlanScheduleProvider implements WorkoutScheduleProvider {
  const UserPlanScheduleProvider();

  @override
  bool get hasPlan => UserSession.instance.plan?.workoutAvailable ?? false;

  @override
  TodaySchedule? today() {
    final day = UserSession.instance.plan?.workoutFor(DateTime.now());
    if (day == null) return null;
    return TodaySchedule(
      name: day.name,
      durationMin: day.durationMin,
      exercises: [for (final p in day.exercises) SessionExercise.fromPlanned(p)],
    );
  }
}

/// Something the assistant should do alongside its reply.
enum CoachAction { none, pauseSession, resumeSession, askStopConfirmation, stopSession }

class CoachResponse {
  final String text;

  /// Follow-up phrases the user can tap (at most three, report FR19.5). Each
  /// one is a phrase the assistant itself understands.
  final List<String> chips;
  final CoachAction action;

  CoachResponse(this.text, {List<String> chips = const [], this.action = CoachAction.none})
      : chips = chips.take(3).toList();
}

/// Builds the coach's reply from the recognised intent and the *actual*
/// session state (Module 6, FR-3 / FR-5). It never invents reps, scores or
/// schedules: when the data is not there, the reply says so.
///
/// Scope: workout micro-coaching only. It gives no diagnosis; reports of pain
/// or symptoms always get "stop and seek appropriate help".
class CoachResponder {
  final WorkoutSessionContext session;
  final WorkoutScheduleProvider schedule;

  const CoachResponder({required this.session, this.schedule = const UserPlanScheduleProvider()});

  static const _noSession =
      "There's no active workout session right now. Open an exercise and tap Start Exercise to begin.";

  CoachResponse respond(IntentResult result, {bool awaitingStopConfirmation = false}) {
    final active = session.hasActiveSession;
    final exercise = session.exercise;

    switch (result.intent) {
      case CoachIntent.painOrSymptom:
        return CoachResponse(
          'Please stop the exercise now and rest. Pain, dizziness or chest discomfort are signals to stop, '
          "not to push through. I can't diagnose injuries — if it is severe or doesn't settle, "
          'contact a doctor or emergency services.'
          '${session.status == SessionStatus.active ? " I've paused your session." : ''}',
          action: session.status == SessionStatus.active ? CoachAction.pauseSession : CoachAction.none,
          chips: active ? const ['End session'] : const [],
        );

      case CoachIntent.confirmYes:
        if (awaitingStopConfirmation && active) {
          return CoachResponse('Okay, ending your session. Nice work.', action: CoachAction.stopSession);
        }
        return _unknown();

      case CoachIntent.confirmNo:
        if (awaitingStopConfirmation) {
          return CoachResponse('Okay, carrying on.', chips: const ['How many reps?', 'Check my form']);
        }
        return _unknown();

      case CoachIntent.stopSession:
        if (!active) return CoachResponse(_noSession, chips: _idleChips);
        return CoachResponse(
          'Do you want to end this ${exercise?.name ?? 'workout'} session? Say yes to end it, or no to keep going.',
          chips: const ['Yes, end it', 'No, keep going'],
          action: CoachAction.askStopConfirmation,
        );

      case CoachIntent.pauseSession:
        if (!active) return CoachResponse(_noSession, chips: _idleChips);
        if (session.status == SessionStatus.paused) {
          return CoachResponse('Your session is already paused.', chips: const ['Resume workout']);
        }
        return CoachResponse(
          'Paused. Say resume when you are ready.',
          chips: const ['Resume workout'],
          action: CoachAction.pauseSession,
        );

      case CoachIntent.resumeSession:
        if (!active) return CoachResponse(_noSession, chips: _idleChips);
        if (session.status == SessionStatus.active) {
          return CoachResponse('Your session is already running.', chips: _activeChips);
        }
        return CoachResponse('Resuming. Let’s go.', chips: _activeChips, action: CoachAction.resumeSession);

      case CoachIntent.repCount:
        return _repCount();
      case CoachIntent.postureFeedback:
        return _postureFeedback();
      case CoachIntent.postureScore:
        return _postureScore();

      case CoachIntent.sessionTime:
        if (!active) return CoachResponse(_noSession, chips: _idleChips);
        return CoachResponse(
          "You've been going for ${_spokenDuration(session.elapsed)}"
          '${session.status == SessionStatus.paused ? ', and the session is paused' : ''}.',
          chips: _activeChips,
        );

      case CoachIntent.nextExercise:
        return _nextExercise();
      case CoachIntent.schedule:
        return _schedule();
      case CoachIntent.exerciseTechnique:
        return _technique(result);

      case CoachIntent.currentExercise:
        if (!active || exercise == null) return CoachResponse(_noSession, chips: _idleChips);
        return CoachResponse(
          "You're doing ${exercise.name}. The target is ${exercise.targetLabel}."
          '${exercise.muscles.isEmpty ? '' : ' It works your ${_join(exercise.muscles)}.'}',
          chips: const ['How do I do it?', 'How many reps?'],
        );

      case CoachIntent.startWorkout:
        if (active) {
          return CoachResponse('Your ${exercise?.name ?? 'workout'} session is already running.', chips: _activeChips);
        }
        return CoachResponse(
          "I can't start a workout by voice yet. Open an exercise from your workout plan and tap Start Exercise.",
          chips: _idleChips,
        );

      case CoachIntent.generalGuidance:
        return CoachResponse(_generalTip(result.topic), chips: active ? _activeChips : _idleChips);

      case CoachIntent.help:
        return CoachResponse(
          'I can tell you your rep count, give feedback on your form, explain how to do an exercise, '
          "tell you what's next, and pause or resume your session.",
          chips: active ? _activeChips : _idleChips,
        );

      case CoachIntent.greeting:
        return CoachResponse(
          active
              ? "Hi! You're in the middle of ${exercise?.name ?? 'a workout'}. Ask me about your reps or your form."
              : 'Hi! Ask me how to do an exercise, or about your workout for today.',
          chips: active ? _activeChips : _idleChips,
        );

      case CoachIntent.unknown:
        return _unknown();
    }
  }

  static const _activeChips = ['How many reps?', 'Check my form', 'Pause workout'];
  static const _idleChips = ["What's my workout today?", 'How do I do a squat?'];

  CoachResponse _unknown() => CoachResponse(
        "Sorry, I can only help with workout questions. Try asking about your reps, your form, or how to do an exercise.",
        chips: session.hasActiveSession ? _activeChips : _idleChips,
      );

  CoachResponse _repCount() {
    final exercise = session.exercise;
    if (!session.hasActiveSession || exercise == null) {
      final last = session.lastSummary;
      if (last != null) {
        return CoachResponse(
          "There's no active session. In your last one, ${last.exercise.name}, you completed ${_reps(last.reps)}.",
          chips: _idleChips,
        );
      }
      return CoachResponse(_noSession, chips: _idleChips);
    }
    if (session.mode == SessionMode.manual) {
      return CoachResponse(
        "You've confirmed ${session.setsCompleted} of ${exercise.sets} sets"
        '${exercise.timed ? '' : ', ${_reps(session.reps)} in total'}. '
        'Manual Guidance counts what you confirm; it does not count reps from the camera.',
        chips: const ['How do I do it?', 'Pause workout'],
      );
    }
    final held = session.holdSeconds;
    if (held != null) {
      final planned = exercise.sets * exercise.seconds;
      return CoachResponse(
        "You've held the position for $held seconds${planned > 0 ? ' of the planned $planned' : ''}.",
        chips: const ['How do I do it?', 'Pause workout'],
      );
    }
    final reps = session.reps;
    final target = exercise.targetReps;
    final buffer = StringBuffer("You've completed ${_reps(reps)}");
    if (target > 0) {
      buffer.write(reps >= target ? ' — you have reached your target of $target' : ' of $target, ${target - reps} to go');
    }
    buffer.write('.');
    if (session.partialReps > 0 && session.formScored) {
      buffer.write(' ${session.partialReps} more ${session.partialReps == 1 ? 'was' : 'were'} too shallow to count.');
    }
    return CoachResponse(buffer.toString(), chips: const ['Check my form', 'Pause workout']);
  }

  CoachResponse _postureFeedback() {
    final exercise = session.exercise;
    if (!session.hasActiveSession || exercise == null) return CoachResponse(_noSession, chips: _idleChips);
    if (session.mode == SessionMode.manual) {
      return CoachResponse(
        "I'm not analysing your posture in Manual Guidance mode, so I can't judge your form. "
        'Use Camera Detection for live feedback.'
        '${exercise.steps.isEmpty ? '' : ' A key cue for ${exercise.name}: ${exercise.steps.first}'}',
        chips: const ['How do I do it?'],
      );
    }
    if (session.status == SessionStatus.paused) {
      return CoachResponse('Your session is paused, so I am not checking your form right now.',
          chips: const ['Resume workout']);
    }
    if (!session.formScored) {
      return CoachResponse(
        'For ${exercise.name} the camera only ${session.holdSeconds != null ? 'times your hold' : 'counts your repetitions'}; '
        "it doesn't judge your form, so I can't tell you whether your technique is right."
        '${exercise.steps.isEmpty ? '' : ' A key cue: ${exercise.steps.first}'}',
        chips: const ['How do I do it?', 'How many reps?'],
      );
    }
    final message = session.feedbackMessage;
    if (!session.landmarksDetected || !session.anglesCalculated || message == null) {
      return CoachResponse(
        "I can't see you clearly enough to check your form. Step back so your whole body is in the frame.",
        chips: const ['How do I do it?'],
      );
    }
    final score = session.postureScore;
    final scoreText = score == null ? '' : ' Your posture score so far is $score percent.';
    if (session.feedbackIsWarning) {
      return CoachResponse('Here is what to fix: $message.$scoreText', chips: const ['How do I do it?', 'How many reps?']);
    }
    return CoachResponse(
      "I don't see a form problem right now. $message.$scoreText",
      chips: const ['How many reps?', 'Pause workout'],
    );
  }

  CoachResponse _postureScore() {
    if (!session.hasActiveSession) {
      final last = session.lastSummary;
      if (last != null && last.postureScore != null) {
        return CoachResponse(
          'In your last session, ${last.exercise.name}, your posture score was ${last.postureScore} percent.',
          chips: _idleChips,
        );
      }
      return CoachResponse(_noSession, chips: _idleChips);
    }
    if (session.mode == SessionMode.manual) {
      return CoachResponse(
        'There is no posture score in Manual Guidance mode because the camera is not analysing your form.',
        chips: const ['How do I do it?'],
      );
    }
    if (!session.formScored) {
      return CoachResponse(
        'There is no posture score for this exercise: the camera only tracks the movement, it does not score form.',
        chips: const ['How do I do it?', 'How many reps?'],
      );
    }
    final score = session.postureScore;
    if (score == null) {
      return CoachResponse(
        "There isn't enough data for a posture score yet. Complete at least one full rep in view of the camera.",
        chips: const ['How do I do it?', 'How many reps?'],
      );
    }
    return CoachResponse(
      'Your posture score so far is $score percent. That is the share of your reps done with acceptable form.',
      chips: const ['Check my form', 'How many reps?'],
    );
  }

  CoachResponse _nextExercise() {
    final upNext = session.upNext;
    if (session.hasActiveSession && upNext.isNotEmpty) {
      return CoachResponse('Next up is ${upNext.first.name}: ${upNext.first.targetLabel}.', chips: _activeChips);
    }
    final current = session.exercise;
    final today = schedule.hasPlan ? schedule.today() : null;
    if (session.hasActiveSession && current != null && today != null) {
      final index = today.exercises.indexWhere((e) => e.id == current.id);
      if (index >= 0 && index < today.exercises.length - 1) {
        final next = today.exercises[index + 1];
        return CoachResponse("In today's plan, ${next.name} comes after ${current.name}: ${next.targetLabel}.",
            chips: _activeChips);
      }
      if (index == today.exercises.length - 1) {
        return CoachResponse("${current.name} is the last exercise in today's plan.", chips: _activeChips);
      }
    }
    if (!session.hasActiveSession) return _schedule();
    return CoachResponse(
      "I don't know the order of this workout, so I can't tell you what comes next.",
      chips: _activeChips,
    );
  }

  CoachResponse _schedule() {
    if (!schedule.hasPlan) {
      return CoachResponse(
        "I don't have a workout schedule for you yet. Complete your health profile to generate a plan.",
        chips: const ['How do I do a squat?'],
      );
    }
    final today = schedule.today();
    if (today == null) {
      return CoachResponse('Today is a rest day in your plan. Light walking or stretching is fine if you feel like moving.');
    }
    final names = [for (final e in today.exercises) e.name];
    return CoachResponse(
      "Today's workout is ${today.name}, about ${today.durationMin} minutes. It includes ${_join(names)}.",
      chips: [if (names.length > 1) 'How do I do ${names[1]}?', "What's next?"],
    );
  }

  CoachResponse _technique(IntentResult result) {
    final named = result.exercise;
    final current = session.hasActiveSession ? session.exercise : null;
    final name = named?.name ?? current?.name;
    final steps = named?.steps ?? current?.steps ?? const <String>[];
    if (name == null) {
      return CoachResponse(
        'Which exercise? For example, ask "how do I do a squat?"',
        chips: const ['How do I do a squat?', 'How do I do a push-up?'],
      );
    }
    if (steps.isEmpty) {
      return CoachResponse("I don't have technique steps for $name.", chips: _idleChips);
    }
    final spoken = [for (var i = 0; i < steps.length; i++) 'Step ${i + 1}: ${steps[i]}'].join(' ');
    return CoachResponse(
      'Here is how to do $name. $spoken',
      chips: session.hasActiveSession ? const ['Check my form', 'How many reps?'] : _idleChips,
    );
  }

  static String _generalTip(String? topic) {
    switch (topic) {
      case 'breathing':
        return 'As a general rule, breathe out on the effort — as you stand up or push — and breathe in on the way down. '
            "Don't hold your breath.";
      case 'rest':
        return 'Rest for the time shown in your plan between sets. If your form starts to slip, rest a little longer.';
      case 'warmup':
        return 'Start with a few minutes of easy movement to warm up, and finish with gentle stretching to cool down.';
      case 'hydration':
        return 'Sip water before, during and after your workout, and more if it is hot.';
      default:
        return "It's fine to slow down or take a longer rest. Good form matters more than speed. "
            'If you feel unwell, stop for today.';
    }
  }

  static String _reps(int n) => n == 1 ? '1 rep' : '$n reps';

  static String _join(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  static String _spokenDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final seconds = '$s second${s == 1 ? '' : 's'}';
    return m == 0 ? seconds : '$m minute${m == 1 ? '' : 's'} $seconds';
  }
}
