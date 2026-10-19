import 'package:flutter/material.dart';

import '../../models/workout_readiness.dart';
import '../../services/api_client.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass.dart';

/// Module 4: the safety questions the health profile does not cover — warning symptoms, a doctor's clearance, current
/// injuries and available equipment. The answers decide whether a plan may be generated at all and which exercises it
/// may contain (see `workout_rules/safety_rule_repository.dart`).
class WorkoutReadinessScreen extends StatefulWidget {
  /// Saves the answers; defaults to [UserSession.saveReadiness]. Replaced in tests.
  final Future<void> Function(WorkoutReadiness)? onSave;

  const WorkoutReadinessScreen({super.key, this.onSave});

  @override
  State<WorkoutReadinessScreen> createState() => _WorkoutReadinessScreenState();
}

class _WorkoutReadinessScreenState extends State<WorkoutReadinessScreen> {
  late final WorkoutReadiness _initial = UserSession.instance.readiness;
  late final Set<String> _symptoms = {..._initial.symptoms};
  late final Set<String> _injuries = {..._initial.injuries};
  late final Set<String> _equipment = {..._initial.equipment};
  late bool? _clearance = _initial.clearance;

  /// "None of these" has to be chosen explicitly, so an untouched list is not mistaken for "no symptoms".
  late bool _noSymptoms = _initial.answered && _initial.symptoms.isEmpty;
  bool _saving = false;

  bool get _complete => _noSymptoms || _symptoms.isNotEmpty;

  Future<void> _save() async {
    if (!_complete) return;
    setState(() => _saving = true);
    final answers = WorkoutReadiness(
      equipment: _equipment,
      injuries: _injuries,
      symptoms: _noSymptoms ? const {} : _symptoms,
      clearance: _clearance,
    );
    final save = widget.onSave ?? UserSession.instance.saveReadiness;
    String message = 'Saved. Your plan has been updated.';
    try {
      await save(answers);
    } on ApiException catch (e) {
      message = 'Your plan uses these answers now, but they could not be saved to your account: ${e.message}';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context, true);
  }

  Widget _section(String title, String hint) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
        ]),
      );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
        value: value,
        onChanged: (v) => setState(() => onChanged(v ?? false)),
        title: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise readiness')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'A few safety questions before Baymax builds your plan. They are a screening aid based on standard pre-exercise '
              'questionnaires — not a medical assessment.',
              style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.45),
            ),
          ),
          _section('1. Do any of these apply to you?', 'Choose all that apply, or "None of these".'),
          for (final entry in WorkoutReadiness.symptomOptions.entries)
            _check(entry.value, _symptoms.contains(entry.key), (v) {
              v ? _symptoms.add(entry.key) : _symptoms.remove(entry.key);
              if (v) _noSymptoms = false;
            }),
          _check('None of these', _noSymptoms, (v) {
            _noSymptoms = v;
            if (v) _symptoms.clear();
          }),
          _section('2. Has a doctor told you it is safe for you to exercise?',
              'Needed if you have a heart condition; useful for everyone with a medical condition.'),
          RadioGroup<int>(
            groupValue: _clearance == true ? 1 : (_clearance == false ? 0 : 2),
            onChanged: (v) => setState(() => _clearance = v == 1 ? true : (v == 0 ? false : null)),
            child: const Column(children: [
              RadioListTile<int>(value: 1, title: Text('Yes'), dense: true),
              RadioListTile<int>(value: 0, title: Text('No'), dense: true),
              RadioListTile<int>(value: 2, title: Text('Not sure / I have not asked'), dense: true),
            ]),
          ),
          _section('3. Any current injury or pain that limits movement?',
              'Exercises that load these areas are adapted, and high-impact ones are left out.'),
          for (final entry in WorkoutReadiness.injuryOptions.entries)
            _check(entry.value, _injuries.contains(entry.key), (v) => v ? _injuries.add(entry.key) : _injuries.remove(entry.key)),
          _section('4. What equipment do you have?',
              'Body weight is always included. Equipment exercises come from the free-exercise-db dataset with its own (unreviewed) instructions.'),
          for (final entry in WorkoutReadiness.equipmentOptions.entries)
            _check(entry.value, _equipment.contains(entry.key), (v) => v ? _equipment.add(entry.key) : _equipment.remove(entry.key)),
          if (!_complete)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('Please answer question 1 to continue.', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: GlowButton(
            label: 'Save answers',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _complete && !_saving ? _save : null,
          ),
        ),
      ),
    );
  }
}
