import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// The mist gradient with soft indigo / violet / teal light, painted once behind every screen (see `main.dart`).
class GlassBackground extends StatelessWidget {
  final Widget child;
  const GlassBackground({Key? key, required this.child}) : super(key: key);

  Widget _orb(Alignment a, double size, Color c, double alpha) => Align(
        alignment: a,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withOpacity(alpha), c.withOpacity(0)])),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _orb(const Alignment(-1.1, -0.95), 420, AppTheme.glow, 0.34),
          _orb(const Alignment(1.25, -0.30), 360, AppTheme.aqua, 0.22),
          _orb(const Alignment(-0.95, 0.80), 400, AppTheme.violet, 0.24),
          _orb(const Alignment(1.1, 1.05), 320, AppTheme.aqua, 0.16),
          child,
        ],
      ),
    );
  }
}

/// Wraps [child] so it reacts to touch: a gentle press-in scale, an ink ripple, and a light haptic tick.
/// Everything tappable in the app goes through this (or a Material button), so every control gives feedback.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final String? semanticLabel;
  final bool haptic;
  const Pressable({
    Key? key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.radius = AppTheme.rLarge,
    this.semanticLabel,
    this.haptic = true,
  }) : super(key: key);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget w = AnimatedScale(
      scale: (_down && !reduce) ? 0.975 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.radius),
          onTap: enabled
              ? () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (v) => setState(() => _down = v),
          splashColor: AppTheme.glow.withOpacity(0.18),
          highlightColor: AppTheme.glow.withOpacity(0.08),
          child: widget.child,
        ),
      ),
    );
    if (widget.semanticLabel != null || enabled) {
      w = Semantics(button: enabled, enabled: enabled, label: widget.semanticLabel, container: true, child: w);
    }
    return w;
  }
}

/// A frosted card: translucent white, light rim, soft indigo shadow. Pass [onTap] to make the whole card a button.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final VoidCallback? onTap;
  final Color? tint;
  final String? semanticLabel;

  const GlassCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.s16),
    this.margin = EdgeInsets.zero,
    this.radius = AppTheme.rLarge,
    this.onTap,
    this.tint,
    this.semanticLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) content = Pressable(radius: radius, onTap: onTap, semanticLabel: semanticLabel, child: content);
    final card = Container(margin: margin, decoration: AppTheme.glass(radius: radius, tint: tint), child: content);
    return (semanticLabel == null || onTap != null) ? card : Semantics(label: semanticLabel, child: card);
  }
}

/// A rounded square holding a Material icon: the replacement for emoji everywhere in the app.
class IconWell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool filled;
  const IconWell({Key? key, required this.icon, this.color = AppTheme.primary, this.size = 44, this.filled = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final r = size * 0.32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: filled ? AppTheme.buttonGradient : null,
        color: filled ? null : AppTheme.tint(color, 0.13),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: Colors.white.withOpacity(0.85), width: 1),
        boxShadow: filled ? AppTheme.glowShadow(blur: 14, opacity: 0.32, offset: const Offset(0, 5)) : const [],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: filled ? Colors.white : color),
    );
  }
}

/// A heading above a block of content, with an optional trailing action ("See all").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {Key? key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(20, 24, 12, 10)}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// A small pill with an optional icon: statuses, tags, streaks.
class InfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const InfoChip(this.label, {Key? key, this.icon, this.color = AppTheme.primary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.tint(color, 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
          Flexible(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color == AppTheme.primary ? AppTheme.primary : color))),
        ],
      ),
    );
  }
}

/// Fades and slides [child] in when it first appears, staggered by [index]. Skipped when the system asks for reduced motion.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  const Reveal({Key? key, required this.child, this.index = 0}) : super(key: key);

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 10));
    _t = Timer(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - _a.value)), child: child),
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const NavItem(this.icon, this.selectedIcon, this.label);
}

/// Floating frosted navigation bar. A glowing pill slides to the selected item; every item is a labelled button.
class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavItem> items;
  const GlassNavBar({Key? key, required this.currentIndex, required this.onTap, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), boxShadow: AppTheme.glowShadow(blur: 24, opacity: 0.14, offset: const Offset(0, 6))),
          child: AppTheme.blurred(
            sigma: 20,
            radius: BorderRadius.circular(30),
            child: Container(
              height: 68,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.74),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(0.95), width: 1.2),
              ),
              child: Stack(
                children: [
                  // the sliding indicator
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment(n == 1 ? 0 : -1 + 2 * currentIndex / (n - 1), 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / n,
                      heightFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.buttonGradient,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppTheme.glowShadow(blur: 16, opacity: 0.40, offset: const Offset(0, 5)),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(child: _NavButton(item: items[i], selected: i == currentIndex, onTap: () => onTap(i))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavButton({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        splashColor: AppTheme.glow.withOpacity(0.25),
        highlightColor: Colors.transparent,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(selected ? item.selectedIcon : item.icon,
                    key: ValueKey(selected), size: 22, color: selected ? Colors.white : AppTheme.textSecondary),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.1, color: selected ? Colors.white : AppTheme.textSecondary),
                child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A primary action button with the gradient and glow (for hero actions; ordinary buttons use the theme).
class GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  const GlowButton({Key? key, required this.label, this.icon, this.onPressed, this.loading = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: enabled || loading ? AppTheme.buttonGradient : null,
          color: enabled || loading ? null : const Color(0xFFD9DCF0),
          borderRadius: BorderRadius.circular(AppTheme.rMedium + 2),
          boxShadow: enabled ? AppTheme.glowShadow(blur: 22, opacity: 0.34, offset: const Offset(0, 8)) : const [],
        ),
        child: Pressable(
          radius: AppTheme.rMedium + 2,
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                else ...[
                  if (icon != null) ...[Icon(icon, color: enabled ? Colors.white : AppTheme.textSecondary, size: 20), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(label,
                        style: TextStyle(color: enabled ? Colors.white : AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.1),
                        textAlign: TextAlign.center),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A centred message for an empty or failed screen: an icon, a sentence, and an optional retry button.
class MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  const MessageState({Key? key, required this.message, this.icon = Icons.cloud_off_rounded, this.onRetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconWell(icon: icon, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15, height: 1.45)),
              if (onRetry != null) ...[
                const SizedBox(height: 18),
                GlowButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
