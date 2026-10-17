import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Shows an exercise's photos (free-exercise-db). With two or more photos it alternates between them in a loop, which
/// shows the start and end position of the movement (report FR14.1). The loop uses a ticker, so it pauses whenever the
/// screen is not visible. Falls back to the group icon when there are no photos or they cannot be loaded (offline).
class ExercisePhoto extends StatefulWidget {
  final List<String> urls;
  final String group;
  final double height;
  final double radius;

  /// Animate between the photos (detail screen) or show only the first (list cards).
  final bool animate;

  const ExercisePhoto({
    super.key,
    required this.urls,
    required this.group,
    this.height = 176,
    this.radius = AppTheme.rHero,
    this.animate = true,
  });

  @override
  State<ExercisePhoto> createState() => _ExercisePhotoState();
}

class _ExercisePhotoState extends State<ExercisePhoto> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate && widget.urls.length > 1) _loop.repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  Widget _fallback() => Center(child: IconWell(icon: AppIcons.exercise(widget.group), size: widget.height * 0.42));

  Widget _image(String url) => Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: widget.height,
        gaplessPlayback: true,
        semanticLabel: 'Exercise photo',
        loadingBuilder: (context, child, progress) => progress == null ? child : _fallback(),
        errorBuilder: (context, error, stack) {
          if (!_failed) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => _failed = true) : null);
          return _fallback();
        },
      );

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final Widget content;
    if (urls.isEmpty || _failed) {
      content = _fallback();
    } else if (!widget.animate || urls.length == 1) {
      content = _image(urls.first);
    } else {
      content = AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final index = (_loop.value * urls.length).floor().clamp(0, urls.length - 1);
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: KeyedSubtree(key: ValueKey(index), child: _image(urls[index])),
          );
        },
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(color: AppTheme.card, height: widget.height, width: double.infinity, child: content),
    );
  }
}
