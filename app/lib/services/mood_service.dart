import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'food_log_service.dart';
import 'realtime_db.dart';

/// How the user says they feel (Home dashboard mood check-in, Module 3 FR-4).
enum Mood { happy, neutral, sad, angry, stressed }

extension MoodInfo on Mood {
  String get label => const ['Happy', 'Neutral', 'Sad', 'Angry', 'Stressed'][index];
  String get id => name;

  IconData get icon => const [
        Icons.sentiment_very_satisfied_rounded,
        Icons.sentiment_neutral_rounded,
        Icons.sentiment_dissatisfied_rounded,
        Icons.sentiment_very_dissatisfied_rounded,
        Icons.psychology_alt_rounded,
      ][index];

  /// A gentle suggestion for today's session. This is NOT the emotion-aware recommendation engine of the scope (that detects emotion
  /// from the face and rewrites the plan); it only suggests an easier session when the user says they feel low or tense.
  String get suggestion {
    switch (this) {
      case Mood.happy:
        return 'Great. A good day to follow your plan, or to try the next step up.';
      case Mood.neutral:
        return 'Follow your plan today. Starting is usually the hardest part.';
      case Mood.sad:
        return 'Be kind to yourself. A short walk or a gentle mobility session is enough today.';
      case Mood.angry:
        return 'Movement can help. Try steady, controlled exercise rather than anything maximal.';
      case Mood.stressed:
        return 'Choose a low-intensity mobility or stretching session today and breathe slowly.';
    }
  }

  static Mood? fromId(String? id) {
    for (final m in Mood.values) {
      if (m.name == id) return m;
    }
    return null;
  }
}

/// Stores one mood per day at `users/{uid}/moods/{YYYY-MM-DD}`.
class MoodService {
  MoodService._();
  static final MoodService instance = MoodService._();

  Future<Mood?> forDate(DateTime d) {
    return RealtimeDb.guard(() async {
      final snap = await RealtimeDb.userRef('moods/${FoodLogService.dateKey(d)}/mood').get();
      return snap.exists ? MoodInfo.fromId(snap.value as String?) : null;
    });
  }

  Future<void> set(DateTime d, Mood? mood) {
    return RealtimeDb.guard(() async {
      final ref = RealtimeDb.userRef('moods/${FoodLogService.dateKey(d)}');
      if (mood == null) {
        await ref.remove();
      } else {
        await ref.set({'mood': mood.id, 'at': ServerValue.timestamp});
      }
    });
  }
}
