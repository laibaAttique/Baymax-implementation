import 'package:flutter/material.dart';

import '../../../services/posture/pose_landmark.dart';
import '../../../theme/app_theme.dart';

/// An angle value drawn next to a joint.
class AngleLabel {
  final int landmark;
  final double degrees;
  const AngleLabel(this.landmark, this.degrees);
}

/// Draws the detected skeleton over the camera preview (report FR16.1).
/// Joints in [highlight] are drawn in the error colour to show where the form
/// problem is.
class PoseOverlayPainter extends CustomPainter {
  final PoseFrame? frame;
  final Set<int> highlight;
  final List<AngleLabel> angles;
  final bool mirrored;
  final double minVisibility;

  PoseOverlayPainter({
    required this.frame,
    this.highlight = const {},
    this.angles = const [],
    this.mirrored = false,
    this.minVisibility = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frame = this.frame;
    if (frame == null || !frame.hasPose) return;
    final points = frame.landmarks;

    bool visible(int i) => points[i].isFinite && points[i].visibility >= minVisibility;
    Offset at(int i) => Offset((mirrored ? 1 - points[i].x : points[i].x) * size.width, points[i].y * size.height);

    final unit = size.shortestSide / 100;
    final bone = Paint()
      ..strokeWidth = unit * 1.1
      ..strokeCap = StrokeCap.round;
    for (final c in PoseIndex.connections) {
      if (!visible(c[0]) || !visible(c[1])) continue;
      final warn = highlight.contains(c[0]) && highlight.contains(c[1]);
      bone.color = (warn ? AppTheme.error : AppTheme.success).withValues(alpha: 0.85);
      canvas.drawLine(at(c[0]), at(c[1]), bone);
    }

    final joint = Paint();
    final ring = Paint()..color = Colors.white;
    for (final i in PoseIndex.drawnJoints) {
      if (!visible(i)) continue;
      final warn = highlight.contains(i);
      final radius = unit * (warn ? 2.6 : 1.7);
      canvas.drawCircle(at(i), radius + unit * 0.5, ring);
      canvas.drawCircle(at(i), radius, joint..color = warn ? AppTheme.error : AppTheme.success);
    }

    for (final label in angles) {
      if (!visible(label.landmark)) continue;
      final text = TextPainter(
        text: TextSpan(
          text: '${label.degrees.round()}°',
          style: TextStyle(fontSize: unit * 4.2, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final origin = at(label.landmark) + Offset(unit * 3.5, -text.height / 2);
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx - unit * 1.5, origin.dy - unit * 0.6, text.width + unit * 3, text.height + unit * 1.2),
        Radius.circular(unit * 3),
      );
      canvas.drawRRect(box, Paint()..color = Colors.white.withValues(alpha: 0.9));
      text.paint(canvas, origin);
    }
  }

  @override
  bool shouldRepaint(PoseOverlayPainter old) =>
      old.frame != frame || old.mirrored != mirrored || old.highlight != highlight;
}
