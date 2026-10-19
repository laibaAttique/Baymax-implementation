import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../services/exercise_catalog.dart';
import 'exercise_photo.dart';
import 'pose_illustration.dart';

/// What picture an exercise gets: its own free-exercise-db photos, the photos of a closely related dataset exercise
/// (labelled as such), or a drawn start/end illustration.
enum VisualKind { photos, similarPhotos, illustration, none }

class ExerciseVisualInfo {
  final VisualKind kind;
  final List<String> urls;
  final PoseIllustrationSpec? illustration;

  /// The dataset exercise the photos show, when it is a similar one.
  final String? similarName;
  const ExerciseVisualInfo(this.kind, {this.urls = const [], this.illustration, this.similarName});

  String get caption => switch (kind) {
        VisualKind.photos => 'Photos: free-exercise-db (public domain). Start and end positions alternate.',
        VisualKind.similarPhotos =>
          'Photos show a similar exercise, "$similarName" (free-exercise-db, public domain). Start and end positions alternate.',
        VisualKind.illustration => 'Illustration of the start and end position, drawn by Baymax.',
        VisualKind.none => '',
      };

  /// Curated exercises whose closest dataset exercise shows the same movement, beyond the recorded references.
  static const similarExtra = {
    'brisk_walk': 'Walking_Treadmill',
    'calf_raise': 'Calf_Raises_-_With_Bands',
    'wall_pushup': 'Incline_Push-Up',
  };

  static ExerciseVisualInfo of(Exercise e) {
    final own = ExerciseCatalog.imagesFor(e);
    if (own.isNotEmpty) return ExerciseVisualInfo(VisualKind.photos, urls: own);
    // A drawn illustration is preferred over a dataset photo that would show a different variant.
    final spec = PoseIllustrations.specs[e.id];
    if (spec != null) return ExerciseVisualInfo(VisualKind.illustration, illustration: spec);
    final ref = e.referenceMatch == 'related' ? e.referenceId : similarExtra[e.id];
    final similar = ref == null ? null : ExerciseCatalog.byId(ref);
    if (similar != null && similar.imageUrls.isNotEmpty) {
      return ExerciseVisualInfo(VisualKind.similarPhotos, urls: similar.imageUrls, similarName: similar.name);
    }
    return const ExerciseVisualInfo(VisualKind.none);
  }
}

/// The picture for an exercise, wherever one is shown (detail screen, workout cards, Posture Detection lists).
class ExerciseVisual extends StatelessWidget {
  final Exercise exercise;
  final double height;
  final double radius;
  final bool animate;
  const ExerciseVisual({super.key, required this.exercise, this.height = 220, this.radius = 16, this.animate = true});

  @override
  Widget build(BuildContext context) {
    final info = ExerciseVisualInfo.of(exercise);
    return switch (info.kind) {
      VisualKind.illustration => PoseIllustration(spec: info.illustration!, height: height, radius: radius, animate: animate),
      _ => ExercisePhoto(urls: info.urls, group: exercise.group, height: height, radius: radius, animate: animate),
    };
  }
}
