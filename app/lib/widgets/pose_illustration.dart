import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A drawn figure moving between an exercise's start and end position, for exercises that have no suitable photo in
/// free-exercise-db. Poses are joint directions in degrees (0 = up, 90 = towards the figure's front/right, 180 = down,
/// 270 = back/left); the figure is drawn side-on unless [FigurePose.front].
class FigurePose {
  /// Hip position in a unit box (x right, y down; the floor is at y = 0.95).
  final Offset hip;
  final double torso;

  /// [upper arm, forearm] and [thigh, shin] for the near and far side.
  final List<double> armNear, armFar, legNear, legFar;
  const FigurePose({
    required this.hip,
    this.torso = 0,
    this.armNear = const [180, 180],
    this.armFar = const [180, 180],
    this.legNear = const [180, 180],
    this.legFar = const [180, 180],
  });

  static double _lerpAngle(double a, double b, double t) {
    final d = ((b - a + 540) % 360) - 180; // shortest way round
    return a + d * t;
  }

  static List<double> _lerpList(List<double> a, List<double> b, double t) => [for (var i = 0; i < a.length; i++) _lerpAngle(a[i], b[i], t)];

  static FigurePose lerp(FigurePose a, FigurePose b, double t) => FigurePose(
        hip: Offset.lerp(a.hip, b.hip, t)!,
        torso: _lerpAngle(a.torso, b.torso, t),
        armNear: _lerpList(a.armNear, b.armNear, t),
        armFar: _lerpList(a.armFar, b.armFar, t),
        legNear: _lerpList(a.legNear, b.legNear, t),
        legFar: _lerpList(a.legFar, b.legFar, t),
      );
}

enum Prop { chair, wall }

class PoseIllustrationSpec {
  final FigurePose start;
  final FigurePose end;

  /// Front view: limbs drawn in the same colour (left and right), not near/far.
  final bool front;
  final Set<Prop> props;
  const PoseIllustrationSpec(this.start, this.end, {this.front = false, this.props = const {}});
}

/// Start and end positions for the curated exercises without a faithful dataset photo. Drawn by the project team as
/// illustrations of the written instructions; not photographs and not a form standard.
class PoseIllustrations {
  PoseIllustrations._();

  // Side view: arms angled a little forward/back so they do not hide behind the body.
  static const _stand = FigurePose(hip: Offset(0.5, 0.51), armNear: [168, 160], armFar: [192, 200]);

  static const _march = PoseIllustrationSpec(
    _stand,
    FigurePose(hip: Offset(0.5, 0.51), armNear: [200, 140], armFar: [150, 60], legNear: [100, 180]),
  );

  static const specs = <String, PoseIllustrationSpec>{
    'jumping_jacks': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.51), armNear: [188, 185], armFar: [172, 175], legNear: [186, 183], legFar: [174, 177]),
      FigurePose(hip: Offset(0.5, 0.53), armNear: [318, 335], armFar: [42, 25], legNear: [206, 200], legFar: [154, 160]),
      front: true,
    ),
    'high_knees': PoseIllustrationSpec(
      _stand,
      FigurePose(hip: Offset(0.5, 0.49), armNear: [210, 120], armFar: [140, 40], legNear: [85, 180]),
    ),
    'march': _march,
    'warmup': _march,
    'burpees': PoseIllustrationSpec(
      _stand,
      FigurePose(hip: Offset(0.45, 0.68), torso: 280, legNear: [128, 128], legFar: [128, 128]),
    ),
    'chair_squat': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.42, 0.73), torso: 15, armNear: [120, 110], armFar: [120, 110], legNear: [90, 180], legFar: [90, 180]),
      FigurePose(hip: Offset(0.5, 0.51), armNear: [168, 160], armFar: [192, 200]),
      props: {Prop.chair},
    ),
    'wall_sit': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.36, 0.51), armNear: [168, 160], armFar: [192, 200]),
      FigurePose(hip: Offset(0.36, 0.73), armNear: [150, 150], armFar: [150, 150], legNear: [90, 180], legFar: [90, 180]),
      props: {Prop.wall},
    ),
    'knee_pushup': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.6, 0.8), torso: 304, legNear: [130, 60], legFar: [130, 60]),
      FigurePose(hip: Offset(0.6, 0.8), torso: 290, armNear: [130, 220], armFar: [130, 220], legNear: [130, 60], legFar: [130, 60]),
    ),
    'side_plank_knee': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.53, 0.93), torso: 301, armNear: [180, 270], armFar: [130, 60], legNear: [95, 50], legFar: [95, 50]),
      FigurePose(hip: Offset(0.53, 0.87), torso: 289, armNear: [180, 270], armFar: [10, 0], legNear: [109, 50], legFar: [109, 50]),
    ),
    'shoulder_taps': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.76), torso: 296, legNear: [115, 115], legFar: [115, 115]),
      FigurePose(hip: Offset(0.5, 0.76), torso: 296, armNear: [150, 330], legNear: [115, 115], legFar: [115, 115]),
    ),
    'bird_dog': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.56, 0.73), torso: 290, legNear: [180, 90], legFar: [180, 90]),
      FigurePose(hip: Offset(0.56, 0.73), torso: 290, armNear: [272, 272], legFar: [92, 92], legNear: [180, 90]),
    ),
    'reverse_snow_angel': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.54, 0.88), torso: 270, armNear: [95, 92], armFar: [95, 92], legNear: [90, 90], legFar: [90, 90]),
      FigurePose(hip: Offset(0.54, 0.88), torso: 270, armNear: [300, 285], armFar: [300, 285], legNear: [90, 90], legFar: [90, 90]),
    ),
    'single_leg_balance': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.51), armNear: [160, 160], armFar: [200, 200]),
      FigurePose(hip: Offset(0.5, 0.51), armNear: [120, 120], armFar: [240, 240], legNear: [125, 200]),
    ),
    'shadow_boxing': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.52), torso: 8, armNear: [150, 20], armFar: [160, 30], legNear: [165, 175], legFar: [200, 185]),
      FigurePose(hip: Offset(0.5, 0.52), torso: 14, armNear: [88, 88], armFar: [160, 30], legNear: [165, 175], legFar: [200, 185]),
    ),
    // free-exercise-db entries that have no photos in the dataset itself
    'Kettlebell_Halo': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.51), armNear: [300, 60], armFar: [60, 300]),
      FigurePose(hip: Offset(0.5, 0.51), armNear: [320, 100], armFar: [40, 100]),
      front: true,
    ),
    'Kettlebell_Halo_With_Overhead_Extension': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.51), armNear: [300, 60], armFar: [60, 300]),
      FigurePose(hip: Offset(0.5, 0.51), armNear: [350, 355], armFar: [10, 5]),
      front: true,
    ),
    'Kettlebell_Overhead_Triceps_Extension': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.51), armNear: [345, 200], armFar: [345, 200]),
      FigurePose(hip: Offset(0.5, 0.51), armNear: [350, 355], armFar: [350, 355]),
    ),
    'cooldown': PoseIllustrationSpec(
      FigurePose(hip: Offset(0.5, 0.51), armNear: [188, 185], armFar: [172, 175]),
      FigurePose(hip: Offset(0.5, 0.51), armNear: [350, 355], armFar: [10, 5]),
      front: true,
    ),
  };

  static bool has(String id) => specs.containsKey(id);
}

/// Animated (or, with [animate] false, still start-position) drawing of [spec].
class PoseIllustration extends StatefulWidget {
  final PoseIllustrationSpec spec;
  final double height;
  final double radius;
  final bool animate;
  const PoseIllustration({super.key, required this.spec, this.height = 220, this.radius = 16, this.animate = true});

  @override
  State<PoseIllustration> createState() => _PoseIllustrationState();
}

class _PoseIllustrationState extends State<PoseIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  /// Plays a few start → end → start cycles, then rests on the start position; a tap replays it. Respects the
  /// system's reduce-motion setting.
  static const _cycles = 10;

  void _play() {
    if (!widget.animate || !mounted || MediaQuery.of(context).disableAnimations) return;
    _loop
      ..reset()
      ..repeat(reverse: true, count: _cycles);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _play();
    }
  }

  bool _started = false;

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: AppTheme.card,
        child: Semantics(
          label: 'Illustration of the start and end position',
          image: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.animate ? _play : null,
            child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_loop.value);
              return CustomPaint(painter: _FigurePainter(widget.spec, FigurePose.lerp(widget.spec.start, widget.spec.end, t)));
            },
            ),
          ),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  final PoseIllustrationSpec spec;
  final FigurePose pose;
  _FigurePainter(this.spec, this.pose);

  static const _torso = 0.26, _upperArm = 0.16, _forearm = 0.15, _thigh = 0.22, _shin = 0.22;

  static Offset _dir(double deg) {
    final r = deg * math.pi / 180;
    return Offset(math.sin(r), -math.cos(r));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The unit box runs from y = -0.08 (raised hands) to the floor at 0.955.
    final side = math.min(size.width, size.height) * 0.9;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2 + side * 0.04);
    Offset px(Offset u) => origin + Offset(u.dx * side, u.dy * side);

    final line = Paint()
      ..color = AppTheme.border
      ..strokeWidth = side * 0.012
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(px(const Offset(0.02, 0.955)), px(const Offset(0.98, 0.955)), line);
    final prop = Paint()
      ..color = AppTheme.textSecondary.withValues(alpha: 0.5)
      ..strokeWidth = side * 0.018
      ..strokeCap = StrokeCap.round;
    if (spec.props.contains(Prop.chair)) {
      canvas.drawLine(px(const Offset(0.24, 0.75)), px(const Offset(0.46, 0.75)), prop);
      canvas.drawLine(px(const Offset(0.26, 0.75)), px(const Offset(0.26, 0.95)), prop);
      canvas.drawLine(px(const Offset(0.44, 0.75)), px(const Offset(0.44, 0.95)), prop);
      canvas.drawLine(px(const Offset(0.24, 0.75)), px(const Offset(0.24, 0.48)), prop);
    }
    if (spec.props.contains(Prop.wall)) {
      canvas.drawLine(px(const Offset(0.28, 0.15)), px(const Offset(0.28, 0.95)), prop);
    }

    final hip = pose.hip;
    final shoulder = hip + _dir(pose.torso) * _torso;
    final head = shoulder + _dir(pose.torso) * 0.075;

    List<Offset> limb(Offset from, List<double> a, double l1, double l2) {
      final mid = from + _dir(a[0]) * l1;
      return [from, mid, mid + _dir(a[1]) * l2];
    }

    final near = AppTheme.primary;
    final far = spec.front ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.4);
    Paint stroke(Color c) => Paint()
      ..color = c
      ..strokeWidth = side * 0.032
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void drawLimb(List<Offset> pts, Color c) {
      final path = Path()..moveTo(px(pts[0]).dx, px(pts[0]).dy);
      for (final p in pts.skip(1)) {
        path.lineTo(px(p).dx, px(p).dy);
      }
      canvas.drawPath(path, stroke(c));
    }

    drawLimb(limb(shoulder, pose.armFar, _upperArm, _forearm), far);
    drawLimb(limb(hip, pose.legFar, _thigh, _shin), far);
    drawLimb([hip, shoulder], near);
    drawLimb(limb(hip, pose.legNear, _thigh, _shin), near);
    drawLimb(limb(shoulder, pose.armNear, _upperArm, _forearm), near);
    canvas.drawCircle(px(head), side * 0.045, Paint()..color = near);
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.pose != pose || old.spec != spec;
}
