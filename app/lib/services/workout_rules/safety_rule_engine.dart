import '../../models/health_profile.dart';
import '../../models/plan.dart';
import '../../models/workout_readiness.dart';
import '../health_classifier.dart';

/// Module 4 knowledge base, part 2: the health → exercise safety rules.
///
/// Rules are data (see `safety_rule_repository.dart`); this file only evaluates them. Evaluation is deterministic and
/// conservative:
///  * restrictions from different rules are merged by taking the most restrictive value (union of exclusions, smallest
///    cap, most severe plan gate), so a conflict can never loosen a restriction;
///  * a rule can only ever ADD restrictions unless it carries an `allow` effect, and `allow` effects are ignored unless
///    the rule's review status is `approved` — and even then they can only lift program-scope exclusions, never a
///    medical or screening one;
///  * missing safety information is never treated as confirmed safety: an exercise whose impact is unknown is not
///    scheduled for anyone with an impact restriction or a reported injury.

/// Who wrote the rule and why.
enum RuleKind {
  /// Pre-exercise screening: decides whether a plan may be generated at all.
  screening,

  /// A medical condition or body measurement.
  medical,

  /// A reported injury.
  injury,

  /// What the program covers (e.g. no maximal lifting in an unsupervised app). Not a medical judgement.
  program,
}

enum RuleBasis {
  /// The guideline itself recommends it.
  guideline,

  /// A conservative precaution chosen by the project team, motivated by (not quoted from) the cited guidelines.
  teamPrecaution,
}

/// A fact about the person the rules can test.
/// [Fact.age] is the age the rules use: the recorded age, or 30 when no date of birth is stored (the Module 3
/// convention). [Fact.ageRecorded] says whether a date of birth exists.
enum Fact { classification, conditions, bmi, age, ageRecorded, weightKg, heightCm, activityLevel, intensity, answered, symptoms, injuries, clearance }

enum Op { eq, ne, gte, lt, contains, notContains, notEmpty, missing }

class Pred {
  final Fact fact;
  final Op op;
  final Object? value;
  const Pred(this.fact, this.op, [this.value]);
}

/// What a rule does when it applies.
class Effects {
  final WorkoutGateStatus? gate;
  final Set<String> excludeImpact;
  final Set<String> excludeTags;

  /// Exclude high-impact exercises that load this joint, and adapt the others that load it.
  final String? injuredJoint;
  final int? maxLevel;
  final int? maxDays;
  final int? maxSessionMin;
  final int? maxHoldSeconds;
  final bool includeBalance;
  final bool strengthFocus;

  /// Exclude catalogue (free-exercise-db) exercises above this level; curated exercises are covered by [maxLevel].
  final int? maxCatalogLevel;

  /// Adaptation shown on every exercise carrying one of these tags.
  final Set<String> modifyTags;
  final String? modification;

  /// Lifts program-scope tag exclusions. Only honoured for approved rules.
  final Set<String> allowTags;

  const Effects({
    this.gate,
    this.excludeImpact = const {},
    this.excludeTags = const {},
    this.injuredJoint,
    this.maxLevel,
    this.maxDays,
    this.maxSessionMin,
    this.maxHoldSeconds,
    this.includeBalance = false,
    this.strengthFocus = false,
    this.maxCatalogLevel,
    this.modifyTags = const {},
    this.modification,
    this.allowTags = const {},
  });
}

class SafetyRule {
  final String id;
  final String title;
  final RuleKind kind;
  final RuleBasis basis;

  /// All must hold (or any, when [matchAny]).
  final List<Pred> when;
  final bool matchAny;
  final Effects effects;

  /// Shown to the user when the rule applies (and [noteWhen] holds, if given).
  final String? note;
  final List<Pred> noteWhen;

  /// Keys into [SafetyRuleRepository.evidence].
  final List<String> evidence;

  /// pending | approved. Every rule shipped today is pending professional review.
  final String reviewStatus;
  final String? approvedBy;

  const SafetyRule({
    required this.id,
    required this.title,
    required this.kind,
    required this.basis,
    required this.when,
    this.matchAny = false,
    required this.effects,
    this.note,
    this.noteWhen = const [],
    required this.evidence,
    this.reviewStatus = 'pending',
    this.approvedBy,
  });

  bool get approved => reviewStatus == 'approved';
}

class EvidenceSource {
  final String citation;
  final String? url;
  const EvidenceSource(this.citation, [this.url]);
}

/// The person as the rules see them. Only fields Baymax actually collects; nothing is filled in for missing data.
class HealthFacts {
  final String classification;
  final Set<String> conditions;
  final double bmi;
  final int? age;
  final double weightKg;
  final double heightCm;
  final String activityLevel;

  /// Low / Moderate / High, from the plan generator's intensity rule.
  final String intensity;

  /// Null when screening is not run (plan generated without the readiness answers).
  final WorkoutReadiness? readiness;

  /// From the stored health profile and the Module 2 classification. [intensity] is the plan generator's intensity.
  factory HealthFacts.from(HealthProfile p, ClassificationResult cls, String intensity, {WorkoutReadiness? readiness}) => HealthFacts(
        classification: cls.category,
        conditions: {...p.medicalConditions},
        bmi: p.bmi,
        age: p.age,
        weightKg: p.weightKg,
        heightCm: p.heightCm,
        activityLevel: p.activityLevel,
        intensity: intensity,
        readiness: readiness,
      );

  const HealthFacts({
    required this.classification,
    required this.conditions,
    required this.bmi,
    required this.age,
    required this.weightKg,
    required this.heightCm,
    required this.activityLevel,
    required this.intensity,
    this.readiness,
  });

  Object? _value(Fact f) {
    switch (f) {
      case Fact.classification:
        return classification;
      case Fact.conditions:
        return conditions;
      case Fact.bmi:
        return bmi;
      case Fact.age:
        return age ?? 30;
      case Fact.ageRecorded:
        return age != null;
      case Fact.weightKg:
        return weightKg;
      case Fact.heightCm:
        return heightCm;
      case Fact.activityLevel:
        return activityLevel;
      case Fact.intensity:
        return intensity;
      case Fact.answered:
        return readiness?.answered;
      case Fact.symptoms:
        return readiness?.symptoms;
      case Fact.injuries:
        return readiness?.injuries;
      case Fact.clearance:
        return readiness?.clearance;
    }
  }

  /// Screening facts are unknown (not false) when screening is not run, so screening rules never fire then.
  bool _isScreening(Fact f) => f == Fact.answered || f == Fact.symptoms || f == Fact.injuries || f == Fact.clearance;

  bool test(Pred p) {
    if (readiness == null && _isScreening(p.fact)) return false;
    final v = _value(p.fact);
    switch (p.op) {
      case Op.missing:
        return v == null;
      case Op.eq:
        return v == p.value;
      case Op.ne:
        return v != p.value;
      case Op.gte:
        return v is num && v >= (p.value as num);
      case Op.lt:
        return v is num && v < (p.value as num);
      case Op.contains:
        return v is Set && v.contains(p.value);
      case Op.notContains:
        return v is Set && !v.contains(p.value);
      case Op.notEmpty:
        return v is Set && v.isNotEmpty;
    }
  }
}

enum ExerciseOutcome { eligible, eligibleWithModifications, requiresInformation, requiresClearance, excluded }

class ExerciseDecision {
  final ExerciseOutcome outcome;
  final List<String> ruleIds;

  /// Plain-language reasons or adaptations, each tagged with its rule id.
  final List<String> notes;
  const ExerciseDecision(this.outcome, {this.ruleIds = const [], this.notes = const []});

  /// May be put in a plan.
  bool get schedulable => outcome == ExerciseOutcome.eligible || outcome == ExerciseOutcome.eligibleWithModifications;
}

class RuleHit {
  final SafetyRule rule;
  final bool noteShown;
  const RuleHit(this.rule, this.noteShown);
}

/// The merged result of every rule that applies to one person.
class SafetyAssessment {
  final String rulesVersion;
  final List<RuleHit> hits;
  final WorkoutGate gate;
  final Set<String> excludedImpact;
  final Set<String> excludedTags;
  final Set<String> injuredJoints;
  final int maxLevel;
  final int maxCatalogLevel;
  final int maxDays;
  final int maxSessionMin;
  final int? maxHoldSeconds;
  final bool includeBalance;
  final bool strengthFocus;
  final List<String> notes;
  final Map<String, Set<String>> _ruleIdsByEffect;
  final List<(Set<String>, String, String)> _tagModifications; // tags, text, rule id

  SafetyAssessment._({
    required this.rulesVersion,
    required this.hits,
    required this.gate,
    required this.excludedImpact,
    required this.excludedTags,
    required this.injuredJoints,
    required this.maxLevel,
    required this.maxCatalogLevel,
    required this.maxDays,
    required this.maxSessionMin,
    required this.maxHoldSeconds,
    required this.includeBalance,
    required this.strengthFocus,
    required this.notes,
    required Map<String, Set<String>> ruleIdsByEffect,
    required List<(Set<String>, String, String)> tagModifications,
  })  : _ruleIdsByEffect = ruleIdsByEffect,
        _tagModifications = tagModifications;

  List<String> _ids(String key) => (_ruleIdsByEffect[key] ?? const <String>{}).toList()..sort();

  /// Applies the merged rules to one exercise.
  ExerciseDecision decide(Exercise e) {
    final level = e.level;
    if (level > maxLevel) {
      return ExerciseDecision(ExerciseOutcome.excluded,
          ruleIds: _ids('maxLevel'), notes: ['Above the difficulty allowed for you (level $maxLevel)']);
    }
    if (e.source == 'free-exercise-db' && level > maxCatalogLevel) {
      return ExerciseDecision(ExerciseOutcome.excluded,
          ruleIds: _ids('maxCatalogLevel'), notes: const ['Expert-level dataset exercise; not scheduled without supervision']);
    }
    if (excludedImpact.contains(e.impact)) {
      return ExerciseDecision(ExerciseOutcome.excluded,
          ruleIds: _ids('impact:${e.impact}'), notes: ['${e.impact == 'high' ? 'High-impact' : 'This'} movement is excluded for you']);
    }
    final blockedTags = e.tags.where(excludedTags.contains).toList()..sort();
    if (blockedTags.isNotEmpty) {
      return ExerciseDecision(ExerciseOutcome.excluded,
          ruleIds: {for (final t in blockedTags) ..._ids('tag:$t')}.toList()..sort(),
          notes: ['Excluded for you: ${blockedTags.join(', ')}']);
    }
    if (e.impact == 'unknown' && (excludedImpact.isNotEmpty || injuredJoints.isNotEmpty)) {
      // Unknown is not "safe": with an impact restriction or an injury the movement cannot be cleared automatically.
      return const ExerciseDecision(ExerciseOutcome.requiresInformation,
          notes: ['Impact level of this exercise is not recorded, so it cannot be checked against your restrictions']);
    }

    final ruleIds = <String>{};
    final notes = <String>[];
    final hurtJoints = e.joints.where(injuredJoints.contains).toList()..sort();
    if (hurtJoints.isNotEmpty) {
      final ids = {for (final j in hurtJoints) ..._ids('joint:$j')};
      if (e.impact == 'high') {
        return ExerciseDecision(ExerciseOutcome.excluded,
            ruleIds: ids.toList()..sort(), notes: ['High-impact on your injured ${hurtJoints.map(_jointLabel).join(' and ')}']);
      }
      ruleIds.addAll(ids);
      notes.add('Loads your ${hurtJoints.map(_jointLabel).join(' and ')}: use a smaller, pain-free range and stop if it hurts '
          '(${(ids.toList()..sort()).join(', ')})');
    }
    for (final (tags, text, id) in _tagModifications) {
      if (e.tags.any(tags.contains)) {
        ruleIds.add(id);
        notes.add('$text ($id)');
      }
    }
    if (e.tags.contains('isometric') && maxHoldSeconds != null) {
      final ids = _ids('maxHold');
      ruleIds.addAll(ids);
      notes.add('Hold capped at $maxHoldSeconds s; keep breathing (${ids.join(', ')})');
    }
    return ExerciseDecision(
      notes.isEmpty ? ExerciseOutcome.eligible : ExerciseOutcome.eligibleWithModifications,
      ruleIds: ruleIds.toList()..sort(),
      notes: notes,
    );
  }

  static String _jointLabel(String j) => WorkoutReadiness.injuryOptions[j]?.toLowerCase() ?? j;
}

class SafetyRuleEngine {
  final String version;
  final List<SafetyRule> rules;
  const SafetyRuleEngine({required this.version, required this.rules});

  static const _defaultMaxLevel = 3;
  static const _defaultMaxDays = 6;
  static const _defaultSessionMin = 55;

  SafetyAssessment assess(HealthFacts facts) {
    final hits = <RuleHit>[];
    var gate = WorkoutGateStatus.eligible;
    final gateReasons = <String>[];
    final gateIds = <String>[];
    final excludedImpact = <String>{};
    final excludedTags = <String>{};
    final programTagExclusions = <String, Set<String>>{}; // tag -> program rule ids
    final allowedTags = <String>{};
    final injured = <String>{};
    var maxLevel = _defaultMaxLevel;
    var maxCatalogLevel = _defaultMaxLevel;
    var maxDays = _defaultMaxDays;
    var maxSession = _defaultSessionMin;
    int? maxHold;
    var balance = false;
    var strength = false;
    final notes = <String>[];
    final byEffect = <String, Set<String>>{};
    final mods = <(Set<String>, String, String)>[];

    void record(String key, String id) => (byEffect[key] ??= <String>{}).add(id);

    for (final r in rules) {
      final applies = r.matchAny ? r.when.any(facts.test) : r.when.every(facts.test);
      if (!applies) continue;
      final showNote = r.note != null && r.noteWhen.every(facts.test);
      hits.add(RuleHit(r, showNote));
      final note = r.note?.replaceAll('{bmi}', facts.bmi.toStringAsFixed(1));
      if (showNote) notes.add(note!);
      final e = r.effects;

      final g = e.gate;
      if (g != null) {
        if (g.index > gate.index) gate = g;
        if (note != null) gateReasons.add(note);
        gateIds.add(r.id);
      }
      for (final i in e.excludeImpact) {
        excludedImpact.add(i);
        record('impact:$i', r.id);
      }
      for (final t in e.excludeTags) {
        if (r.kind == RuleKind.program) {
          (programTagExclusions[t] ??= <String>{}).add(r.id);
        } else {
          excludedTags.add(t);
        }
        record('tag:$t', r.id);
      }
      if (e.injuredJoint != null) {
        injured.add(e.injuredJoint!);
        record('joint:${e.injuredJoint}', r.id);
      }
      if (e.maxLevel != null && e.maxLevel! <= maxLevel) {
        maxLevel = e.maxLevel!;
        record('maxLevel', r.id);
      }
      if (e.maxCatalogLevel != null && e.maxCatalogLevel! <= maxCatalogLevel) {
        maxCatalogLevel = e.maxCatalogLevel!;
        record('maxCatalogLevel', r.id);
      }
      if (e.maxDays != null && e.maxDays! < maxDays) maxDays = e.maxDays!;
      if (e.maxSessionMin != null && e.maxSessionMin! < maxSession) maxSession = e.maxSessionMin!;
      if (e.maxHoldSeconds != null && (maxHold == null || e.maxHoldSeconds! <= maxHold)) {
        maxHold = e.maxHoldSeconds;
        record('maxHold', r.id);
      }
      balance = balance || e.includeBalance;
      strength = strength || e.strengthFocus;
      if (e.modification != null && e.modifyTags.isNotEmpty) mods.add((e.modifyTags, e.modification!, r.id));
      // Only an approved rule may relax anything, and only program-scope exclusions.
      if (r.approved) allowedTags.addAll(e.allowTags);
    }

    for (final entry in programTagExclusions.entries) {
      if (!allowedTags.contains(entry.key)) excludedTags.add(entry.key);
    }
    if (notes.isEmpty) {
      notes.add('No medical restrictions detected. Warm up before every session and stop if something hurts.');
    }

    return SafetyAssessment._(
      rulesVersion: version,
      hits: hits,
      gate: WorkoutGate(gate, reasons: gate == WorkoutGateStatus.eligible ? const [] : gateReasons, ruleIds: gateIds),
      excludedImpact: excludedImpact,
      excludedTags: excludedTags,
      injuredJoints: injured,
      maxLevel: maxLevel,
      maxCatalogLevel: maxCatalogLevel,
      maxDays: maxDays,
      maxSessionMin: maxSession,
      maxHoldSeconds: maxHold,
      includeBalance: balance,
      strengthFocus: strength,
      notes: notes,
      ruleIdsByEffect: byEffect,
      tagModifications: mods,
    );
  }
}
