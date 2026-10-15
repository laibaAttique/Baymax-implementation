import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// "Step 2 of 3" with a segmented progress bar and the step's title. Used by the three profiling screens.
class StepHeader extends StatelessWidget {
  final int step;
  final int total;
  final String title;
  final String? subtitle;
  const StepHeader({Key? key, required this.step, required this.total, required this.title, this.subtitle}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Step $step of $total. $title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= total; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: i <= step ? AppTheme.buttonGradient : null,
                      color: i <= step ? null : const Color(0xFFDDE0F5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Text('STEP $step OF $total', style: AppTheme.overline),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.8, height: 1.15)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: const TextStyle(fontSize: 14.5, color: AppTheme.textSecondary, height: 1.45, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

/// A row of equal pill buttons where exactly one is selected (gender, units).
class PillChoice extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  final double height;
  const PillChoice({Key? key, required this.options, required this.selected, required this.onChanged, this.height = 50}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(height / 2), border: Border.all(color: Colors.white, width: 1.2), boxShadow: AppTheme.softShadow()),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: o == selected,
                label: o,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(o);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: o == selected ? AppTheme.buttonGradient : null,
                      borderRadius: BorderRadius.circular(height / 2),
                      boxShadow: o == selected ? AppTheme.glowShadow(blur: 12, opacity: 0.3, offset: const Offset(0, 4)) : const [],
                    ),
                    child: Text(o, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: o == selected ? Colors.white : AppTheme.textPrimary)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A selectable chip for multi-select lists (conditions, allergies).
class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SelectChip({Key? key, required this.label, required this.selected, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryLight : AppTheme.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? AppTheme.primary : Colors.white, width: selected ? 1.8 : 1.2),
            boxShadow: selected ? const [] : AppTheme.softShadow(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: selected ? const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check_rounded, size: 18, color: AppTheme.primary)) : const SizedBox.shrink(),
              ),
              Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 14, color: selected ? AppTheme.primary : AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back / Next buttons at the end of a profiling step.
class StepActions extends StatelessWidget {
  final String nextLabel;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final bool loading;
  const StepActions({Key? key, required this.nextLabel, required this.onNext, this.onBack, this.loading = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          SizedBox(
            width: 112,
            child: OutlinedButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Back')),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: GlowButton(label: nextLabel, icon: Icons.arrow_forward_rounded, loading: loading, onPressed: onNext)),
      ],
    );
  }
}
