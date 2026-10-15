import 'package:flutter/material.dart';
import '../services/calorie_optimizer.dart';
import '../theme/app_theme.dart';

/// Weigh-in dots with the smoothed trend line.
class WeightTrendChart extends StatelessWidget {
  final List<WeightPoint> points;
  final double? targetKg;
  const WeightTrendChart({Key? key, required this.points, this.targetKg}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Weight chart with ${points.length} weigh-ins',
      child: CustomPaint(painter: _WeightPainter(points, targetKg), size: Size.infinite),
    );
  }
}

class _WeightPainter extends CustomPainter {
  final List<WeightPoint> pts;
  final double? target;
  _WeightPainter(this.pts, this.target);

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    final trend = trendWeights(pts);
    final all = [...pts.map((p) => p.kg), ...trend.map((p) => p.kg), if (target != null) target!];
    var lo = all.reduce((a, b) => a < b ? a : b), hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1) {
      lo -= 0.5;
      hi += 0.5;
    }
    final t0 = pts.first.date.millisecondsSinceEpoch.toDouble();
    final span = (pts.last.date.millisecondsSinceEpoch - pts.first.date.millisecondsSinceEpoch).toDouble().clamp(1, double.infinity);
    double y(double kg) => size.height - 10 - (size.height - 20) * (kg - lo) / (hi - lo);
    Offset at(WeightPoint p) => Offset(10 + (size.width - 20) * (p.date.millisecondsSinceEpoch - t0) / span, y(p.kg));

    if (target != null) {
      final dash = Paint()
        ..color = AppTheme.success
        ..strokeWidth = 1.5;
      for (double x = 10; x < size.width - 10; x += 10) {
        canvas.drawLine(Offset(x, y(target!)), Offset(x + 5, y(target!)), dash);
      }
    }
    final glow = Paint()
      ..color = AppTheme.glow.withOpacity(0.35)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final line = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(at(trend.first).dx, at(trend.first).dy);
    for (final p in trend.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
    final dot = Paint()..color = AppTheme.textSecondary;
    final ring = Paint()..color = Colors.white;
    for (final p in pts) {
      canvas.drawCircle(at(p), 4.5, ring);
      canvas.drawCircle(at(p), 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightPainter old) => old.pts != pts || old.target != target;
}

class BarDatum {
  final String label;
  final double value;
  final String semantic;
  const BarDatum(this.label, this.value, this.semantic);
}

/// Vertical bars with an optional target line and an optional moving-average line (same scale).
class BarChart extends StatelessWidget {
  final List<BarDatum> bars;
  final double? target;
  final List<double?>? movingAverage;
  final double height;
  final Color barColor;
  const BarChart({Key? key, required this.bars, this.target, this.movingAverage, this.height = 130, this.barColor = AppTheme.primary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final maxV = [for (final b in bars) b.value, if (target != null) target!, 1.0].reduce((a, b) => a > b ? a : b) * 1.12;
    return SizedBox(
      height: height + 22,
      child: Stack(
        children: [
          Positioned.fill(
            bottom: 22,
            child: CustomPaint(painter: _GridPainter(target: target == null ? null : target! / maxV, avg: movingAverage?.map((v) => v == null ? null : v / maxV).toList())),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in bars)
                Expanded(
                  child: Semantics(
                    label: b.semantic,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          height: (height * (b.value / maxV)).clamp(b.value > 0 ? 4.0 : 0.0, height),
                          margin: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppTheme.glow, barColor]),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            boxShadow: b.value > 0 ? AppTheme.glowShadow(blur: 10, opacity: 0.35, offset: const Offset(0, 3)) : const [],
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(height: 18, child: Text(b.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double? target; // 0..1 of the chart height
  final List<double?>? avg;
  _GridPainter({this.target, this.avg});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppTheme.border.withOpacity(0.7)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (target != null) {
      final y = size.height * (1 - target!);
      final p = Paint()
        ..color = AppTheme.success
        ..strokeWidth = 1.6;
      for (double x = 0; x < size.width; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(x + 5, y), p);
      }
    }
    final a = avg;
    if (a != null && a.whereType<double>().length >= 2) {
      final line = Paint()
        ..color = AppTheme.textPrimary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      var started = false;
      for (var i = 0; i < a.length; i++) {
        final v = a[i];
        if (v == null) continue;
        final x = size.width * (i + 0.5) / a.length;
        final y = size.height * (1 - v);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.target != target || old.avg != avg;
}

/// One slice of a [DonutChart].
class DonutSlice {
  final String label;
  final double value;
  final Color color;
  const DonutSlice(this.label, this.value, this.color);
}

/// A ring split into slices (macronutrient shares). [center] is drawn in the middle.
class DonutChart extends StatelessWidget {
  final List<DonutSlice> slices;
  final double size;
  final Widget? center;
  final String semanticLabel;
  const DonutChart({Key? key, required this.slices, this.size = 140, this.center, required this.semanticLabel}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _DonutPainter(slices), child: Center(child: center)),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final total = slices.fold(0.0, (s, e) => s + e.value);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFFDDE0F5);
    if (total <= 0) {
      canvas.drawArc(rect, 0, 6.283185, false, track);
      return;
    }
    var start = -1.5707963;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = 6.283185 * s.value / total;
      final gap = slices.where((x) => x.value > 0).length > 1 ? 0.04 : 0.0; // a thin gap between slices
      canvas.drawArc(
        rect,
        start + gap / 2,
        (sweep - gap).clamp(0.0, 6.283185),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = s.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}
