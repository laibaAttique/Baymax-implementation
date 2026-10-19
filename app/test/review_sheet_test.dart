import 'dart:convert';
import 'dart:io';

import 'package:app/services/workout_rules/classification_profiles.dart';
import 'package:app/services/workout_rules/safety_rule_engine.dart';
import 'package:app/services/workout_rules/safety_rule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Module 4 (ledger K8): the sheet a qualified reviewer fills in. It lists every safety rule, classification profile,
/// profile note and MET mapping rule with what it does and what it cites, plus empty columns for the decision.
///
/// The committed sheet must match the code. To regenerate it after a change:
///   BAYMAX_WRITE_REVIEW=1 flutter test test/review_sheet_test.dart        (PowerShell: $env:BAYMAX_WRITE_REVIEW='1')
const _path = 'docs/review/module4_review_sheet.csv';

String _cell(Object? v) {
  final s = (v ?? '').toString().replaceAll('\n', ' ');
  return s.contains(RegExp(r'[",]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _pred(Pred p) => '${p.fact.name} ${p.op.name}${p.value == null ? '' : ' ${p.value is Set ? (p.value as Set).join('|') : p.value}'}';

String _effects(Effects e) => [
      if (e.gate != null) 'gate=${e.gate!.name}',
      if (e.excludeImpact.isNotEmpty) 'excludeImpact=${e.excludeImpact.join('|')}',
      if (e.excludeTags.isNotEmpty) 'excludeTags=${e.excludeTags.join('|')}',
      if (e.injuredJoint != null) 'injuredJoint=${e.injuredJoint}',
      if (e.maxLevel != null) 'maxLevel=${e.maxLevel}',
      if (e.maxCatalogLevel != null) 'maxCatalogLevel=${e.maxCatalogLevel}',
      if (e.maxDays != null) 'maxDays=${e.maxDays}',
      if (e.maxSessionMin != null) 'maxSessionMin=${e.maxSessionMin}',
      if (e.maxHoldSeconds != null) 'maxHoldSeconds=${e.maxHoldSeconds}',
      if (e.includeBalance) 'includeBalance',
      if (e.strengthFocus) 'strengthFocus',
      if (e.modification != null) 'modify ${e.modifyTags.join('|')}: ${e.modification}',
    ].join('; ');

String buildSheet() {
  final catalog = jsonDecode(File('assets/data/exercise_catalog.json').readAsStringSync()) as Map<String, dynamic>;
  final byRule = <String, int>{};
  for (final e in catalog['exercises'] as List) {
    final rule = ((e as Map)['met'] as Map)['rule'] as String?;
    if (rule != null) byRule[rule] = (byRule[rule] ?? 0) + 1;
  }
  final mapping = jsonDecode(File('ml/exercise_catalog/met_mapping_rules.json').readAsStringSync()) as Map<String, dynamic>;

  const header = ['kind', 'id', 'version', 'title', 'basis', 'applies when', 'effect', 'user-facing text', 'evidence', 'status',
    'reviewer decision (approve/change/reject)', 'reviewer name and role', 'comments'];
  final rows = <List<Object?>>[header];
  for (final r in SafetyRuleRepository.rules) {
    rows.add(['safety rule (${r.kind.name})', r.id, SafetyRuleRepository.version, r.title, r.basis.name,
      r.when.map(_pred).join(r.matchAny ? ' OR ' : ' AND '), _effects(r.effects), r.note, r.evidence.join('|'), r.reviewStatus, '', '', '']);
  }
  for (final p in ClassificationProfiles.all) {
    rows.add(['classification profile', p.id, ClassificationProfiles.version, p.category, 'band cap: ${p.bandBasis.name}',
      'Module 2 category = ${p.category}',
      'maxBand=${p.maxBand.name}; aerobic ${p.aerobicMin}-${p.aerobicMax} min/week; strength ${p.strengthDays}+ days; '
          'stretching ${p.flexibilityDays}+ days${p.maxRestDaysInRow == null ? '' : '; max ${p.maxRestDaysInRow} rest days in a row'}',
      p.emphasis, p.evidence.join('|'), p.reviewStatus, '', '', '']);
  }
  for (final n in ClassificationProfiles.notes) {
    rows.add(['profile note', n.id, ClassificationProfiles.version, '', 'explanation only', n.when.map(_pred).join(' AND '),
      'none (text only)', n.text, n.evidence.join('|'), n.reviewStatus, '', '', '']);
  }
  for (final m in (mapping['rules'] as List).cast<Map<String, dynamic>>()) {
    final when = [
      for (final k in ['category', 'equipment', 'force', 'mechanic', 'nameAny'])
        if (m[k] != null) '$k: ${(m[k] is List ? (m[k] as List).join('|') : m[k])}',
    ].join('; ');
    rows.add(['MET mapping', m['id'], mapping['version'], 'Compendium ${m['code'] ?? '(none)'}', m['match'], when,
      '${byRule[m['id']] ?? 0} catalogue exercises', m['why'], '2024 Adult Compendium', 'pending', '', '', '']);
  }
  return '${rows.map((r) => r.map(_cell).join(',')).join('\n')}\n';
}

void main() {
  test('the review sheet lists every rule, profile, note and MET mapping, and is up to date', () {
    final sheet = buildSheet();
    final file = File(_path);
    if (Platform.environment['BAYMAX_WRITE_REVIEW'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(sheet);
    }
    expect(file.existsSync(), isTrue, reason: 'run with BAYMAX_WRITE_REVIEW=1 to create $_path');
    expect(file.readAsStringSync().replaceAll('\r\n', '\n'), sheet, reason: 'the sheet is out of date; regenerate it with BAYMAX_WRITE_REVIEW=1');
    final lines = sheet.trim().split('\n');
    expect(lines.length,
        1 + SafetyRuleRepository.rules.length + ClassificationProfiles.all.length + ClassificationProfiles.notes.length + 29);
    expect(sheet, isNot(contains(',approved,')), reason: 'nothing is marked approved by the project team');
  });
}
