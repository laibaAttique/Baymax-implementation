import 'dart:math' as math;

/// A point or vector. Use `z = 0` for 2-D image coordinates.
class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3(this.x, this.y, [this.z = 0]);

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(dot(this));
  static Vec3 midpoint(Vec3 a, Vec3 b) => Vec3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2);
}

/// Geometry used by the form rules (Module 5, FR-4).
class PoseMath {
  PoseMath._();

  static const _epsilon = 1e-6;

  /// Angle ABC in degrees (0..180) at vertex [b], from three landmark
  /// coordinates:
  ///
  ///   θ = arccos( (BA · BC) / (|BA| |BC|) )
  ///
  /// Returns null when a coordinate is not finite or two points coincide (a
  /// zero-length vector has no direction). The cosine is clamped to [-1, 1] so
  /// rounding can never push `acos` out of its domain.
  static double? jointAngle(Vec3 a, Vec3 b, Vec3 c) {
    if (!a.isFinite || !b.isFinite || !c.isFinite) return null;
    final ba = a - b;
    final bc = c - b;
    final lenBa = ba.length;
    final lenBc = bc.length;
    if (lenBa < _epsilon || lenBc < _epsilon) return null;
    final cosine = (ba.dot(bc) / (lenBa * lenBc)).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  /// How far the line [lower]→[upper] leans away from the vertical (y) axis,
  /// in degrees (0 = upright, 90 = horizontal). Null for coincident or
  /// invalid points.
  static double? leanFromVertical(Vec3 lower, Vec3 upper) {
    if (!lower.isFinite || !upper.isFinite) return null;
    final d = upper - lower;
    final horizontal = math.sqrt(d.x * d.x + d.z * d.z);
    final vertical = d.y.abs();
    if (horizontal < _epsilon && vertical < _epsilon) return null;
    return math.atan2(horizontal, vertical) * 180 / math.pi;
  }
}
