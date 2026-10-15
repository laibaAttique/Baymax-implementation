import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// An animated circular progress ring with a gradient arc and [child] in the middle.
/// [value] is 0..1. Use [over] to switch the arc to the error colour (e.g. calories above target).
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double stroke;
  final bool over;
  final Widget? child;
  final String? semanticLabel;
  const ProgressRing({Key? key, required this.value, this.size = 74, this.stroke = 8, this.over = false, this.child, this.semanticLabel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(painter: _RingPainter(v, stroke, over), child: Center(child: child)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final double stroke;
  final bool over;
  _RingPainter(this.value, this.stroke, this.over);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0xFFDDE0F5),
    );
    if (value <= 0) return;
    final colors = over ? const [Color(0xFFE5645C), AppTheme.error] : const [AppTheme.aqua, AppTheme.glow, AppTheme.primary];
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(startAngle: -math.pi / 2, endAngle: math.pi * 1.5, colors: colors, transform: const GradientRotation(0)).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.stroke != stroke || old.over != over;
}
