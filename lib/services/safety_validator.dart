/// Safety validator v1 — the deterministic layer.
///
/// Built **only** from `docs/safety_hazard_registry.md`, which Chef Harris
/// signed on 21.08.26 and which was verified complete on 2026-08-22. Eleven
/// active rules (H1–H11), plus H12 as a handwritten addition with no
/// rule/detection/action structure. The someday list (S1 shellfish, S2 raw
/// flour and dough, S3 sprouts) is **INACTIVE** and deliberately absent —
/// `test/services/safety_validator_test.dart` asserts that absence so a
/// half-implementation cannot creep in.
///
/// # How this differs from the compatibility validator, and why they stay apart
///
/// `cooking_compatibility_validator.dart` is **advisory**. Everything about it
/// fails open by design: an unresolvable ingredient produces no flag, and a
/// recipe that still breaks the one-band rule after two corrections is served
/// silently. That is right for timing — a stew that wants 90 minutes and got
/// 60 is a worse dinner, not a hazard.
///
/// This file is **not** advisory, and the two must never be merged into one
/// "validator" abstraction:
///
///  * H1's enforcement is **deterministic injection**. The signed
///    `juices_run_clear` cue is written onto the qualifying step by the app,
///    unconditionally. It does not ask the model, does not depend on the model
///    complying, is not retried, and cannot fail open. It is applied **last**,
///    after every correction round, so no regeneration can undo it.
///  * The remaining rules follow the registry's own signed enforcement —
///    *"correction-and-regenerate, never blocking"*, and *"after 2 failed
///    corrections the recipe is served and the flag logged"*. That is a signed
///    decision about those rules, not this file relaxing its own standard.
///
/// The two layers share infrastructure (the parsed payload, the ring-buffer
/// log shape) and nothing else. Ordering is fixed in
/// `validated_recipe_generation.dart`: compat first, safety second, on the
/// recipe that is actually going to be served.
///
/// # What this file may not contain
///
/// No threshold, temperature, duration or user-facing sentence that is not
/// transcribed from the signed registry. Where the registry names an
/// enforcement whose **wording** Harris has not authored yet (H2's
/// cooked-through line, H8's vulnerable-groups caution), the wording is a
/// `// PLACEHOLDER` and the rule degrades to detection plus a model-facing
/// correction directive. It never invents the sentence.
library;

import 'package:flutter/foundation.dart';

import 'package:optimeal/data/safety_ingredient_names.dart';
import 'package:optimeal/data/sensory_cue_vocabulary.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// The registry's rule identifiers, exactly as numbered on the signed sheet.
enum SafetyRuleId { h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12 }

extension SafetyRuleIdLabel on SafetyRuleId {
  String get label => name.toUpperCase();
}

/// What the app does about a finding. Mirrors the registry's "On flag" lines.
enum SafetyEnforcement {
  /// The app writes the fix onto the recipe itself. H1 only (and H10 where it
  /// rides H1's path). Unconditional, idempotent, never retried.
  inject,

  /// A model-facing correction directive plus a regeneration, capped by
  /// [kMaxSafetyRetries]; then the recipe is served and the flag logged.
  correctAndRegenerate,

  /// Detected and recorded, no action taken. Used where the registry defines
  /// detection but no enforcement (H12), and where the enforcement it names
  /// depends on wording Harris has not authored (H10's centre verification on
  /// non-poultry meat).
  logOnly,
}

/// One finding. Flat and primitive so it serialises into a log line directly,
/// same shape rule as `CompatibilityFlag`.
@immutable
class SafetyFinding {
  const SafetyFinding({
    required this.rule,
    required this.enforcement,
    required this.detail,
    this.stepIndex,
    this.stepTitle,
    this.subject,
  });

  final SafetyRuleId rule;
  final SafetyEnforcement enforcement;

  /// Machine-readable description of what matched. Never shown to a user.
  final String detail;

  final int? stepIndex;
  final String? stepTitle;

  /// The ingredient, dish pattern or protein class that triggered the rule.
  final String? subject;

  bool get isCorrectable => enforcement == SafetyEnforcement.correctAndRegenerate;

  Map<String, dynamic> toJson() => {
        'rule': rule.label,
        'enforcement': enforcement.name,
        'detail': detail,
        if (stepIndex != null) 'step_index': stepIndex,
        if (stepTitle != null) 'step_title': stepTitle,
        if (subject != null) 'subject': subject,
      };

  /// The sentence handed to the model on a correction retry.
  ///
  /// **Model-facing only.** Every one of these restates a rule that is on the
  /// signed sheet; none of them is a user-facing safety sentence, and none
  /// invents a number. Where the registry's required content is itself
  /// spelled out on the sheet (H8), the directive quotes that requirement
  /// rather than composing a new one.
  String get correctionSentence {
    final buffer = StringBuffer('[${rule.label}]');
    if (stepIndex != null) {
      buffer.write(' (step ');
      buffer.write(stepIndex! + 1);
      if (stepTitle != null) {
        buffer.write(', "');
        buffer.write(stepTitle);
        buffer.write('"');
      }
      buffer.write(')');
    }
    buffer.write(' ');
    buffer.write(detail);
    return buffer.toString();
  }

  @override
  String toString() => correctionSentence;
}

/// One applied deterministic injection. Recorded so the log can show that the
/// guarantee actually fired, rather than that it was merely intended to.
@immutable
class SafetyInjection {
  const SafetyInjection({
    required this.rule,
    required this.stepIndex,
    required this.stepTitle,
    required this.cueKey,
    required this.replacedCueKey,
  });

  final SafetyRuleId rule;
  final int stepIndex;
  final String stepTitle;
  final String cueKey;

  /// The cue that was on the step before injection. Equal to
  /// [SensoryCueVocabulary.noCueKey] when the step simply had none. A real
  /// cue key here means a preference cue was displaced by a safety cue.
  final String replacedCueKey;

  bool get displacedAnotherCue =>
      replacedCueKey != SensoryCueVocabulary.noCueKey && replacedCueKey != cueKey;

  Map<String, dynamic> toJson() => {
        'rule': rule.label,
        'step_index': stepIndex,
        'step_title': stepTitle,
        'cue': cueKey,
        'replaced_cue': replacedCueKey,
        'displaced_another_cue': displacedAnotherCue,
      };
}

/// The outcome of one safety pass.
@immutable
class SafetyReport {
  const SafetyReport({
    required this.findings,
    required this.injections,
    required this.stepsChecked,
  });

  const SafetyReport.clean()
      : findings = const [],
        injections = const [],
        stepsChecked = 0;

  final List<SafetyFinding> findings;
  final List<SafetyInjection> injections;
  final int stepsChecked;

  bool get isClean => findings.isEmpty;

  /// Findings that a regeneration could actually fix.
  List<SafetyFinding> get correctable =>
      findings.where((f) => f.isCorrectable).toList(growable: false);

  bool get hasCorrectable => correctable.isNotEmpty;

  /// The correction note appended to a retry prompt, on the **variable** half
  /// of the message — never the cached static prefix.
  String buildCorrectionNote() {
    final items = correctable;
    if (items.isEmpty) return '';
    final buffer = StringBuffer(
      'FOOD SAFETY CORRECTION REQUIRED. Your previous version breaks a '
      'non-negotiable kitchen safety rule. Fix every point below and return '
      'the whole recipe again in the same JSON shape:\n',
    );
    for (final f in items) {
      buffer.writeln('- ${f.correctionSentence}');
    }
    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
        'findings': findings.map((f) => f.toJson()).toList(),
        'injections': injections.map((i) => i.toJson()).toList(),
        'steps_checked': stepsChecked,
      };
}

/// Signed cap, from the registry's "Already decided elsewhere" block:
/// *"After 2 failed corrections the recipe is served and the flag logged."*
const int kMaxSafetyRetries = 2;

// ─────────────────────────────────────────────────────────────────────────────
// Text helpers
// ─────────────────────────────────────────────────────────────────────────────

String _stepText(CookModeStepPayload s) =>
    '${s.title} ${s.bullets.join(' ')}'.toLowerCase();

bool _isOffHeat(CookModeStepPayload s) => s.heat.trim().toLowerCase() == 'off_heat';

String _recipeText(CookModeRecipePayload r) {
  final parts = <String>[
    r.title,
    r.description ?? '',
    ...r.ingredients,
    ...r.steps.map(_stepText),
  ];
  return parts.join(' ').toLowerCase();
}

final Map<String, RegExp> _needleCache = {};

/// Whole-word matcher for the rules' trigger vocabularies.
///
/// **This used to match on a word PREFIX**, which is a bad way for a safety
/// rule to be wrong: `rare` fired on "rarely", `pink` fired on "pinkish", and
/// `rest` fired on "restaurant". Every one of those is a false positive that
/// spends a correction retry and teaches the model to write defensively.
///
/// Now: whole-word, plus regular English inflection, plus the trailing-`e`
/// elision that `bake`→`baking` and `leave`→`leaving` need. So `chill` still
/// covers "chilled" and "chilling" — which matters, because `chill` appears
/// in an *exclusion* list, and an exclusion that silently stopped matching
/// would turn H5 and H6 into false-positive machines rather than quiet ones.
///
/// Irregular forms are not covered ("left" for "leave"). Where a rule needs
/// one, it goes in that rule's list as its own entry.
RegExp _needlePattern(String needle) => _needleCache.putIfAbsent(needle, () {
      final escaped = RegExp.escape(needle);
      final alternatives = <String>[escaped];
      if (needle.endsWith('e')) {
        alternatives.add(RegExp.escape(needle.substring(0, needle.length - 1)));
      }
      return RegExp(
        '\\b(?:${alternatives.join('|')})(?:s|es|d|ed|ing)?\\b',
        caseSensitive: false,
      );
    });

bool _hasAny(String text, List<String> needles) {
  for (final n in needles) {
    if (_needlePattern(n).hasMatch(text)) return true;
  }
  return false;
}

/// The step text plus whatever the step declares it is adding, so a step whose
/// prose says "add it" still resolves to the ingredient by name.
String _stepScope(CookModeStepPayload s) =>
    '${_stepText(s)} ${(s.ingredientsAdded ?? const []).join(' ')}'.toLowerCase();

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Runs every deterministic rule. **Detection only — nothing is mutated.**
/// Injection is a separate call so that it can be applied once, at the end,
/// after all correction rounds. See [applySafetyInjections].
SafetyReport validateRecipeSafety(CookModeRecipePayload recipe) {
  final findings = <SafetyFinding>[];

  _checkH1(recipe, findings);
  _checkH2(recipe, findings);
  _checkH3(recipe, findings);
  _checkH4(recipe, findings);
  _checkH5(recipe, findings);
  _checkH6(recipe, findings);
  _checkH7(recipe, findings);
  _checkH8(recipe, findings);
  _checkH9(recipe, findings);
  _checkH10(recipe, findings);
  _checkH11(recipe, findings);
  _checkH12(recipe, findings);

  return SafetyReport(
    findings: findings,
    injections: const [],
    stepsChecked: recipe.steps.length,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// H1 — poultry and pork doneness is verified, never assumed
//
// Registry: "Every step that cooks poultry or pork carries the signed
// juices_run_clear verification… On flag: the app sets the signed cue on the
// step itself — deterministic injection, never forgotten, no regeneration
// needed."
//
// READING, recorded for signature: the registry says *every* step that cooks
// poultry or pork. Taken absolutely literally that puts a doneness cue on the
// step that browns raw chicken as well as the one that finishes it — four
// identical "cut into the thickest part" cues in a four-step recipe, three of
// them at moments when the answer is meant to be "not yet". This implementation
// injects on the **last on-heat step that handles each qualifying protein**,
// which is the step where doneness is actually decided and the last point
// before the food is served. Every qualifying protein gets its own such step,
// so a recipe cooking chicken and pork separately gets both.
// ─────────────────────────────────────────────────────────────────────────────

/// Oven and grill language. A step declared `off_heat` that says "roast in the
/// oven" is still cooking, and on real dev output the model declares oven
/// steps as `off_heat` routinely — the heat field describes the hob. Without
/// this, H1 skips the exact step where a roast finishes.
const List<String> _ovenLanguage = [
  'oven',
  'roast',
  'bake',
  'grill',
  'broil',
  'air fry',
  'air-fry',
];

/// True when a step is cooking the food, whether on the hob or in the oven.
bool _isCookingStep(CookModeStepPayload s) =>
    !_isOffHeat(s) || _hasAny(_stepText(s), _ovenLanguage);

/// Plating and finishing language.
const List<String> _servingLanguage = [
  'serve',
  'serving',
  'finish with',
  'garnish',
  'plate',
  'scatter',
  'drizzle',
  'squeeze',
  'spoon over',
  'sprinkle',
  'rest',
];

/// True when a step can be the place the doneness cue is anchored.
///
/// The oven allowance above is necessary but too generous on its own: an
/// off-heat garnish step whose bullets say "spoon the pan juices over the
/// **roast** chicken" contains oven language as a *noun*, and being last it
/// would win the anchor. Observed on real dev output — the cue landed on a
/// two-minute step titled "Finish with Lemon" instead of the twenty-five
/// minute one titled "Roast Chicken and Potatoes".
///
/// So an off-heat step that is plainly plating is not a candidate. The
/// exclusion is deliberately limited to off-heat steps: "Finish cooking the
/// pork chops" on medium heat is exactly where a doneness cue belongs, and
/// that step really is the last cooking moment.
bool _isDonenessAnchorCandidate(CookModeStepPayload s) {
  if (!_isCookingStep(s)) return false;
  if (_isOffHeat(s) && _hasAny(_stepText(s), _servingLanguage)) return false;
  return true;
}

/// Step indices that must carry the signed doneness cue, and the protein that
/// put them there.
///
/// One entry per **animal**, not per vocabulary term — see [donenessFamilyOf].
Map<int, String> donenessStepsFor(CookModeRecipePayload recipe) {
  final lastStepByFamily = <String, int>{};
  final termByFamily = <String, String>{};

  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    if (!_isDonenessAnchorCandidate(step)) continue;
    for (final name in matchSafetyNames(_stepScope(step))) {
      if (!name.qualifiesForDonenessRule) continue;
      final family = donenessFamilyOf(name);
      lastStepByFamily[family] = i;
      // Keep the most specific term seen for this animal, for the log line.
      final existing = termByFamily[family];
      if (existing == null || name.term.length > existing.length) {
        termByFamily[family] = name.term;
      }
    }
  }

  // Collapse to one entry per step, naming the most specific protein on it.
  final out = <int, String>{};
  for (final entry in lastStepByFamily.entries) {
    final term = termByFamily[entry.key] ?? entry.key;
    final existing = out[entry.value];
    if (existing == null || term.length > existing.length) {
      out[entry.value] = term;
    }
  }
  return out;
}

void _checkH1(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  donenessStepsFor(recipe).forEach((index, protein) {
    final step = recipe.steps[index];
    if (step.sensoryCue == 'juices_run_clear') return; // already correct
    findings.add(SafetyFinding(
      rule: SafetyRuleId.h1,
      enforcement: SafetyEnforcement.inject,
      stepIndex: index,
      stepTitle: step.title,
      subject: protein,
      detail: 'Poultry/pork step without the signed juices_run_clear '
          'verification cue. The app injects it deterministically.',
    ));
  });
}

/// Writes the signed doneness cue onto every qualifying step.
///
/// **This is the guarantee.** It runs after all correction rounds, on the
/// recipe that is about to be served, and it cannot fail open: it does not
/// consult the model, has no failure path, and re-running it changes nothing.
///
/// Idempotent: a step that already declares `juices_run_clear` is returned
/// untouched and produces no [SafetyInjection] entry.
({CookModeRecipePayload recipe, List<SafetyInjection> injections})
    applySafetyInjections(CookModeRecipePayload recipe) {
  final targets = donenessStepsFor(recipe);
  if (targets.isEmpty) {
    return (recipe: recipe, injections: const []);
  }

  final injections = <SafetyInjection>[];
  final steps = <CookModeStepPayload>[];

  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    if (!targets.containsKey(i) || step.sensoryCue == 'juices_run_clear') {
      steps.add(step);
      continue;
    }
    injections.add(SafetyInjection(
      rule: SafetyRuleId.h1,
      stepIndex: i,
      stepTitle: step.title,
      cueKey: 'juices_run_clear',
      replacedCueKey: step.sensoryCue,
    ));
    steps.add(step.copyWithSensoryCue('juices_run_clear'));
  }

  return (recipe: recipe.copyWithSteps(steps), injections: injections);
}

// ─────────────────────────────────────────────────────────────────────────────
// H2 — minced and comminuted meat is cooked through, no pink ever
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _pinkDonenessLanguage = [
  'medium-rare',
  'medium rare',
  'rare',
  'still pink',
  'slightly pink',
  'pink in the middle',
  'pink in the centre',
  'pink in the center',
  'blushing',
  'rosy',
];

const List<String> _cookedThroughLanguage = [
  'cooked through',
  'cooked all the way through',
  'no longer pink',
  'no pink',
  'right through',
  'all the way through',
  'browned through',
  'thoroughly cooked',
];

// PLACEHOLDER — Harris's signed cooked-through line for H2 does not exist yet.
// The registry's checklist says "wrote or scheduled"; the sheet carries no
// wording. Until it does, H2 corrects and regenerates and never injects a
// sentence of its own. Do not write one here.

void _checkH2(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  // Branch one: pink/rare language on a step that handles comminuted meat.
  // Per step, because the offending sentence is in a specific step and the
  // correction directive has to name it.
  var sawComminuted = false;
  String? subject;

  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    final minced = matchSafetyNames(scope).where((n) => n.comminuted).toList();
    if (minced.isEmpty) continue;

    sawComminuted = true;
    subject ??= minced.first.term;

    if (_hasAny(scope, _pinkDonenessLanguage)) {
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h2,
        enforcement: SafetyEnforcement.correctAndRegenerate,
        stepIndex: i,
        stepTitle: step.title,
        subject: minced.first.term,
        detail: 'This step cooks ${minced.first.term} (comminuted meat) but '
            'describes a rare or pink result. Comminuted meat is always '
            'cooked through with no pink remaining. Rewrite the step so it is '
            'cooked through.',
      ));
    }
  }

  if (!sawComminuted) return;

  // Branch two: the recipe as a whole never says the mince is cooked through.
  // Deliberately recipe-level, not per step. A bolognese mentions its mince in
  // half its steps, and demanding "cooked through" in every one of them would
  // flag a correct recipe four times and fill the correction note with noise.
  // The rule is that the instruction is present, not that it is repeated.
  final anyCookedThrough = recipe.steps.any(
    (s) => _hasAny(_stepScope(s), _cookedThroughLanguage),
  );
  if (anyCookedThrough) return;

  findings.add(SafetyFinding(
    rule: SafetyRuleId.h2,
    enforcement: SafetyEnforcement.correctAndRegenerate,
    subject: subject,
    detail: 'This recipe cooks $subject (comminuted meat) but never states '
        'that it is cooked through. Comminuted meat is always cooked through '
        'with no pink remaining — say so explicitly in the step that cooks it.',
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// H3 — temperature floor
//
// READING, recorded for signature: the registry rule is about **core**
// temperature. A recipe states oven temperatures far more often than core
// temperatures, and "roast at 180 °C" must not be read as a core reading. So a
// number only counts as a core temperature when the step says so — internal,
// core, centre, thermometer, or "until it reaches". Everything else is skipped
// rather than guessed at, which is the fail-safe direction here: a missed oven
// number costs nothing, a misread one would flag every roast in the app.
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _celsiusPattern =
    RegExp(r'(\d{2,3})\s*(?:°\s*c|degrees\s*c|degrees celsius|\bc\b)', caseSensitive: false);

final RegExp _fahrenheitPattern =
    RegExp(r'(\d{2,3})\s*(?:°\s*f|degrees\s*f)', caseSensitive: false);

const List<String> _coreTemperatureLanguage = [
  'internal',
  'core temperature',
  'core temp',
  'centre of',
  'center of',
  'thermometer',
  'reaches',
  'reach',
  'registers',
  'probe',
];

const List<String> _restLanguage = [
  'rest',
  'rested',
  'resting',
  'stand for',
  'standing',
  'leave to sit',
];

void _checkH3(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    if (!_hasAny(scope, _coreTemperatureLanguage)) continue;

    final classes = proteinClassesIn(scope).isNotEmpty
        ? proteinClassesIn(scope)
        : proteinClassesIn(_recipeText(recipe));
    final governing = governingProteinClass(classes);
    if (governing == null) continue;

    if (_fahrenheitPattern.hasMatch(scope) && !_celsiusPattern.hasMatch(scope)) {
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h3,
        enforcement: SafetyEnforcement.correctAndRegenerate,
        stepIndex: i,
        stepTitle: step.title,
        subject: governing.label,
        detail: 'Core temperature is stated in Fahrenheit. State it in '
            'degrees Celsius so it can be checked against the '
            '${governing.label} minimum of ${governing.minimumCelsius} °C.',
      ));
      continue;
    }

    for (final match in _celsiusPattern.allMatches(scope)) {
      final stated = int.tryParse(match.group(1)!);
      if (stated == null) continue;
      // Anything at oven range is not a core reading even in a sentence that
      // mentions a thermometer; core temperatures for these proteins sit well
      // below boiling.
      if (stated > 100) continue;

      if (stated < governing.minimumCelsius) {
        findings.add(SafetyFinding(
          rule: SafetyRuleId.h3,
          enforcement: SafetyEnforcement.correctAndRegenerate,
          stepIndex: i,
          stepTitle: step.title,
          subject: governing.label,
          detail: 'States a core temperature of $stated °C for '
              '${governing.label} with no hold time. The minimum is '
              '${governing.minimumCelsius} °C. Raise it to at least '
              '${governing.minimumCelsius} °C.',
        ));
        continue;
      }

      if (governing.requiresStatedRest && !_hasAny(scope, _restLanguage)) {
        findings.add(SafetyFinding(
          rule: SafetyRuleId.h3,
          enforcement: SafetyEnforcement.correctAndRegenerate,
          stepIndex: i,
          stepTitle: step.title,
          subject: governing.label,
          detail: 'States $stated °C for whole-muscle pork but no rest. The '
              'signed condition is ${governing.minimumCelsius} °C plus a '
              '${governing.restMinutes}-minute rest — the temperature alone is '
              'not the condition. Add the rest.',
        ));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H4 — marinade that touched raw meat is never served as-is
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _marinadeLanguage = ['marinade', 'marinate', 'marinating', 'marinated'];
const List<String> _marinadeServeLanguage = [
  'drizzle',
  'glaze',
  'brush',
  'spoon over',
  'pour over',
  'serve with the',
  'reserved marinade',
  'remaining marinade',
  'as a sauce',
  'as a dressing',
];
const List<String> _boilLanguage = [
  'boil',
  'boiling',
  'bring to the boil',
  'bring to a boil',
  'simmer',
  'reduce',
];

void _checkH4(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  final text = _recipeText(recipe);
  if (!_hasAny(text, _marinadeLanguage)) return;

  final proteins = matchSafetyNames(text)
      .where((n) => n.poultry || n.pork || n.fish)
      .toList();
  if (proteins.isEmpty) return;

  for (var i = 0; i < recipe.steps.length; i++) {
    final scope = _stepScope(recipe.steps[i]);
    if (!_hasAny(scope, _marinadeLanguage)) continue;
    if (!_hasAny(scope, _marinadeServeLanguage)) continue;
    if (_hasAny(scope, _boilLanguage)) continue;

    findings.add(SafetyFinding(
      rule: SafetyRuleId.h4,
      enforcement: SafetyEnforcement.correctAndRegenerate,
      stepIndex: i,
      stepTitle: recipe.steps[i].title,
      subject: proteins.first.term,
      detail: 'Uses marinade that has been in contact with raw '
          '${proteins.first.term} as a sauce, glaze or drizzle without '
          'bringing it to a full boil first. Either discard the marinade or '
          'bring it to a full boil before any such use.',
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H5 — cooked rice and grains: cool fast, chill promptly, reheat hard, once
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _riceAndGrains = [
  'rice',
  'risotto',
  'basmati',
  'jasmine rice',
  'brown rice',
  'quinoa',
  'couscous',
  'bulgur',
  'barley',
  'farro',
  'spelt',
];

const List<String> _roomTemperatureHolding = [
  'room temperature',
  'on the counter',
  'on the worktop',
  'leave out',
  'leave it out',
  'overnight',
  'cool completely',
];

// 'refrigerat' was a bare stem, which only worked because the old matcher was
// prefix-based. Whole-word matching needs the real words, and 'refrigerator'
// is not an inflection of 'refrigerate' so it is listed separately.
const List<String> _fridgeLanguage = [
  'fridge',
  'refrigerate',
  'refrigerator',
  'refrigeration',
  'chill',
  'cold store',
];

const List<String> _pipingHotLanguage = [
  'piping hot',
  'steaming hot',
  'steaming throughout',
  'hot all the way through',
  'thoroughly',
  'right through',
  'all the way through',
];

void _checkH5(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    if (!_hasAny(scope, _riceAndGrains)) continue;

    if (_hasAny(scope, _roomTemperatureHolding) && !_hasAny(scope, _fridgeLanguage)) {
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h5,
        enforcement: SafetyEnforcement.correctAndRegenerate,
        stepIndex: i,
        stepTitle: step.title,
        subject: 'rice or grains',
        detail: 'Leaves cooked rice or grains at room temperature. Cooked '
            'rice must be cooled quickly and moved to the fridge, never held '
            'warm or left out. Rewrite the step accordingly.',
      ));
      continue;
    }

  }

  // Leftover rice is checked at RECIPE level, in both halves.
  //
  // Found on real dev output: the ingredient list said "leftover cooked rice"
  // and every step then said only "rice", with the heat language ("Heat the
  // pan") sitting in a step that never names the rice at all. A step-local
  // check therefore saw an ordinary rice dish and stayed silent on the one
  // hazard H5 exists for. Neither half of the trigger reliably lands in the
  // same sentence, so neither half is looked for there.
  if (!_isLeftoverRiceRecipe(recipe)) return;
  if (recipe.steps.any((s) => _hasAny(_stepScope(s), _pipingHotLanguage))) return;

  final riceStep = recipe.steps.indexWhere(
    (s) => _isCookingStep(s) && _hasAny(_stepScope(s), _riceAndGrains),
  );
  if (riceStep == -1) return;

  findings.add(SafetyFinding(
    rule: SafetyRuleId.h5,
    enforcement: SafetyEnforcement.correctAndRegenerate,
    stepIndex: riceStep,
    stepTitle: recipe.steps[riceStep].title,
    subject: 'leftover rice',
    detail: 'This recipe uses leftover rice but never instructs that it is '
        'reheated piping hot all the way through, once. Say so in the step '
        'that heats the rice.',
  ));
}

const List<String> _leftoverRiceLanguage = [
  'leftover',
  'left over',
  'day-old',
  'day old',
  'cold rice',
  'cooked rice',
  'pre-cooked rice',
  'yesterday',
];

/// True when anything in the recipe — title, description, ingredient list or
/// a step — says the rice was already cooked. All four are read, because on
/// real output the evidence turned up in the ingredient list alone.
bool _isLeftoverRiceRecipe(CookModeRecipePayload recipe) {
  final text = _recipeText(recipe);
  return _hasAny(text, _riceAndGrains) && _hasAny(text, _leftoverRiceLanguage);
}

// ─────────────────────────────────────────────────────────────────────────────
// H6 — no holding perishable food in the danger zone. Signed limit: 2 hours.
// ─────────────────────────────────────────────────────────────────────────────

/// The signed danger-zone limit, in minutes. Registry H6, confirmed by Harris
/// on 2026-08-22 ("2 hours stand"). This is the only place it appears.
const int kDangerZoneLimitMinutes = 120;

final RegExp _hoursPattern = RegExp(r'(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b', caseSensitive: false);
final RegExp _minutesPattern = RegExp(r'(\d+)\s*(?:minutes?|mins?)\b', caseSensitive: false);

const List<String> _holdingLanguage = [
  'rest',
  'hold',
  'leave',
  'sit',
  'stand',
  'set aside',
  'marinate',
  'cool',
];

const List<String> _perishableLanguage = [
  'meat',
  'cooked',
  'cream',
  'milk',
  'yoghurt',
  'yogurt',
  'cheese',
  'egg',
  'butter',
  'stock',
  'sauce',
];

bool _mentionsPerishable(String scope, CookModeRecipePayload recipe) {
  if (matchSafetyNames(scope).isNotEmpty) return true;
  if (_hasAny(scope, _perishableLanguage)) return true;
  return matchSafetyNames(_recipeText(recipe)).isNotEmpty;
}

void _checkH6(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    if (!_hasAny(scope, _holdingLanguage)) continue;
    if (_hasAny(scope, _fridgeLanguage)) continue; // chilled holding is not the rule
    if (!_mentionsPerishable(scope, recipe)) continue;

    if (RegExp(r'\bovernight\b', caseSensitive: false).hasMatch(scope)) {
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h6,
        enforcement: SafetyEnforcement.correctAndRegenerate,
        stepIndex: i,
        stepTitle: step.title,
        subject: 'overnight at room temperature',
        detail: 'Holds perishable food out of the fridge overnight. '
            'Perishable food is never left at room temperature overnight. '
            'Move it to the fridge.',
      ));
      continue;
    }

    var statedMinutes = 0;
    for (final m in _hoursPattern.allMatches(scope)) {
      final v = double.tryParse(m.group(1)!);
      if (v != null) statedMinutes = statedMinutes > (v * 60).round() ? statedMinutes : (v * 60).round();
    }
    for (final m in _minutesPattern.allMatches(scope)) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v > statedMinutes) statedMinutes = v;
    }

    if (statedMinutes > kDangerZoneLimitMinutes) {
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h6,
        enforcement: SafetyEnforcement.correctAndRegenerate,
        stepIndex: i,
        stepTitle: step.title,
        subject: '$statedMinutes minutes at room temperature',
        detail: 'Holds perishable food at room temperature for $statedMinutes '
            'minutes. The limit is $kDangerZoneLimitMinutes minutes. Shorten '
            'it, or move the food to the fridge for that time.',
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H7 — no partial cooking of meat to finish later
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _partialCookLanguage = [
  'par-cook',
  'parcook',
  'par cook',
  'partially cook',
  'partly cook',
  'part-cook',
  'half-cook',
  'cook halfway',
  'cook half way',
  'finish later',
  'finish it later',
  'finish cooking later',
  'sear now and finish',
];

void _checkH7(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    if (!_hasAny(scope, _partialCookLanguage)) continue;

    final proteins = matchSafetyNames(scope)
        .where((n) => n.poultry || n.pork || n.fish || n.comminuted)
        .toList();
    if (proteins.isEmpty) continue; // par-cooking vegetables is fine

    findings.add(SafetyFinding(
      rule: SafetyRuleId.h7,
      enforcement: SafetyEnforcement.correctAndRegenerate,
      stepIndex: i,
      stepTitle: step.title,
      subject: proteins.first.term,
      detail: 'Partially cooks ${proteins.first.term} with the intention of '
          'finishing later. Protein cookery is never interrupted this way — '
          'cook it through in one go, or do not start it until it can be '
          'finished.',
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H8 — raw or undercooked egg in no-cook preparations is called out
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _rawEggDishes = [
  'mayonnaise',
  'mayo',
  'aioli',
  'aïoli',
  'tiramisu',
  'mousse',
  'eggnog',
  'zabaglione',
  'sabayon',
  'caesar dressing',
  'steak tartare',
];

const List<String> _rawEggSafeguardLanguage = [
  'pasteurised',
  'pasteurized',
  'very fresh',
];

// PLACEHOLDER — the H8 vulnerable-groups caution is signed content Harris has
// not authored. The registry names its required *content* (eggs are raw;
// pasteurised or very fresh; caution for pregnant, elderly, young children,
// immunocompromised), which is what the model-facing directive below asks for.
// The user-facing sentence itself is not written here.

void _checkH8(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  final text = _recipeText(recipe);
  final namedDish = _hasAny(text, _rawEggDishes);

  final mentionsEgg = RegExp(r'\begg', caseSensitive: false).hasMatch(text);
  final eggIsCooked = recipe.steps.any(
    (s) => !_isOffHeat(s) && RegExp(r'\begg', caseSensitive: false).hasMatch(_stepScope(s)),
  );

  final rawEggPreparation = namedDish || (mentionsEgg && !eggIsCooked);
  if (!rawEggPreparation) return;
  if (_hasAny(text, _rawEggSafeguardLanguage)) return;

  findings.add(SafetyFinding(
    rule: SafetyRuleId.h8,
    enforcement: SafetyEnforcement.correctAndRegenerate,
    subject: namedDish ? 'named raw-egg preparation' : 'uncooked egg',
    detail: 'Serves raw or barely-cooked egg without calling it out. The '
        'recipe must state that the eggs are raw, instruct pasteurised or very '
        'fresh eggs, and carry a caution for vulnerable groups (pregnant, '
        'elderly, young children, immunocompromised).',
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// H9 — fish served raw must be fit for raw consumption
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _rawFishDishes = [
  'ceviche',
  'tartare',
  'crudo',
  'sushi',
  'sashimi',
  'gravlax',
  'gravadlax',
  'poke',
  'carpaccio',
];

const List<String> _rawFishSafeguardLanguage = [
  'sushi-grade',
  'sushi grade',
  'sashimi-grade',
  'sashimi grade',
  'previously frozen',
  'previously-frozen',
  'frozen for',
  'fit for raw',
];

void _checkH9(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  final text = _recipeText(recipe);
  if (!_hasAny(text, _rawFishDishes)) return;

  final fish = matchSafetyNames(text).where((n) => n.fish).toList();
  if (fish.isEmpty) return; // beef carpaccio / steak tartare are not this rule

  if (_hasAny(text, _rawFishSafeguardLanguage)) return;

  findings.add(SafetyFinding(
    rule: SafetyRuleId.h9,
    enforcement: SafetyEnforcement.correctAndRegenerate,
    subject: fish.first.term,
    detail: 'Serves ${fish.first.term} raw or cured only, without instructing '
        'sushi-grade or previously-frozen fish. Acid does not kill parasites. '
        'Add that instruction.',
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
// H10 — stuffed and rolled meats: the centre counts as the inside of a burger
//
// Registry: "Can reuse the cue-injection path from H1… On flag: Inject or
// regenerate with centre-verification in Harris's signed wording."
//
// Poultry and pork are already carried by H1's injection, and that is recorded
// here rather than double-flagged. **Non-poultry, non-pork stuffed meat is
// log-only**: there is no signed centre-verification wording, and the H1 cue's
// own signed text ("flesh opaque and white throughout") is poultry language
// that would be wrong on a beef roulade. Proposed enforcement is in the
// session report.
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _stuffedOrRolledLanguage = [
  'stuffed',
  'stuff the',
  'rolled',
  'roll the',
  'roulade',
  'involtini',
  'ballotine',
  'galantine',
  'braciole',
  'cordon bleu',
  'roll up',
];

const List<String> _otherMeatLanguage = ['beef', 'lamb', 'veal', 'venison'];

void _checkH10(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  final donenessSteps = donenessStepsFor(recipe);

  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    if (!_hasAny(scope, _stuffedOrRolledLanguage)) continue;

    final poultryOrPork = matchSafetyNames(scope).any((n) => n.qualifiesForDonenessRule);
    if (poultryOrPork) {
      // Carried by H1. Recorded so the log shows the rule was evaluated and
      // which path took it, not silently absorbed.
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h10,
        enforcement: SafetyEnforcement.inject,
        stepIndex: i,
        stepTitle: step.title,
        subject: 'stuffed or rolled poultry/pork',
        detail: 'Stuffed or rolled poultry/pork. Doneness verification is '
            'carried by the H1 cue injection'
            '${donenessSteps.containsKey(i) ? ' on this step' : ' on the final cooking step'}. '
            'Centre-specific wording is not signed yet.',
      ));
      continue;
    }

    if (_hasAny(scope, _otherMeatLanguage)) {
      findings.add(SafetyFinding(
        rule: SafetyRuleId.h10,
        enforcement: SafetyEnforcement.logOnly,
        stepIndex: i,
        stepTitle: step.title,
        subject: 'stuffed or rolled meat (not poultry or pork)',
        detail: 'Stuffed or rolled non-poultry meat: the centre is now '
            'interior surface. No signed centre-verification wording exists '
            'for this case, so this is detected and logged only.',
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H11 — leftovers are reheated piping hot throughout, once
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _reheatLanguage = ['reheat', 'warm up', 'warm through', 'heat through'];
const List<String> _gentleHeatLanguage = ['gently', 'low heat', 'until warm', 'lukewarm', 'warmed through'];

void _checkH11(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  for (var i = 0; i < recipe.steps.length; i++) {
    final step = recipe.steps[i];
    final scope = _stepScope(step);
    if (!_hasAny(scope, _reheatLanguage)) continue;
    if (!_mentionsPerishable(scope, recipe)) continue;
    if (_hasAny(scope, _pipingHotLanguage)) continue;

    findings.add(SafetyFinding(
      rule: SafetyRuleId.h11,
      enforcement: SafetyEnforcement.correctAndRegenerate,
      stepIndex: i,
      stepTitle: step.title,
      subject: _hasAny(scope, _gentleHeatLanguage) ? 'gentle reheat' : 'reheat',
      detail: 'Reheats leftovers without instructing piping hot throughout. '
          'Leftovers are reheated piping hot all the way through, once, never '
          'merely warmed and never cycled. Say so in the step.',
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// H12 — fermentation processes (handwritten addition, Harris)
//
// The signed entry is prose: Chef Harris stays out of fermentation; if someone
// asks for e.g. kimchi he should say normal long fermentation is not advised
// and propose a "quick pickle" technique instead.
//
// **It carries no rule / detection / on-flag structure**, which the registry
// itself records as structural question 1 and the transcription session
// recorded as open item 4. It is also generation-prompt behaviour — what the
// persona should *say* — rather than a post-generation check.
//
// So this is **detection and logging only**, and the signed ruling confirms it
// stays that way: "this rule lands on the persona/prompt side; the
// deterministic layer is LOG-ONLY verification that the prompt behaved."
// No user-facing action, no correction, no injection. The substitution
// behaviour and the "Quick X" note are persona/authoring-batch work and are
// deliberately not implemented here.
//
// The bread carve-out below is **SIGNED** (Harris, 2026-08-21 ruling, recorded
// in docs/DECISIONS.md on 2026-08-23): sourdough and bread baking are out of
// scope entirely, because grain leavening is not a fermentation hazard. It was
// built ahead of that record reaching the repo and was flagged as unsigned at
// the time; the ruling has since been committed and the two agree.
//
// In scope, per the same ruling: vegetable, dairy, soy and beverage ferments.
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _fermentationLanguage = [
  'ferment',
  'fermenting',
  'fermented',
  'fermentation',
  'lacto-ferment',
  'lacto ferment',
  'kimchi',
  'sauerkraut',
  'kombucha',
  'kefir',
  'koji',
  'tempeh',
];

/// SIGNED carve-out (2026-08-21 ruling) — see the block comment above.
const List<String> kFermentationBreadCarveOutDraft = [
  'sourdough',
  'starter',
  'levain',
  'poolish',
  'biga',
  'focaccia',
  'pizza dough',
  'bread dough',
  'yeast',
];

void _checkH12(CookModeRecipePayload recipe, List<SafetyFinding> findings) {
  final text = _recipeText(recipe);
  if (!_hasAny(text, _fermentationLanguage)) return;
  if (_hasAny(text, kFermentationBreadCarveOutDraft)) return;

  final matched = _fermentationLanguage.firstWhere(
    (t) => _hasAny(text, [t]),
    orElse: () => 'fermentation',
  );

  findings.add(SafetyFinding(
    rule: SafetyRuleId.h12,
    enforcement: SafetyEnforcement.logOnly,
    subject: matched,
    detail: 'Fermentation process detected ("$matched"). The signed H12 entry '
        'says Chef Harris stays out of fermentation and proposes a quick '
        'pickle instead, but defines no detection or on-flag structure, so '
        'this is logged and no action is taken.',
  ));
}
