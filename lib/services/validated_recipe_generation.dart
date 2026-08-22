import 'package:flutter/foundation.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/compatibility_flag_log.dart';
import 'package:optimeal/services/cooking_compatibility_validator.dart';
import 'package:optimeal/services/safety_flag_log.dart';
import 'package:optimeal/services/safety_validator.dart';

/// Why a generation attempt is being made. Carried into the attempt so the
/// caller can bill each call to its own cost surface — a compatibility retry
/// and a safety retry are different work and must not land in the same bucket
/// in `api_call_cost_log`.
enum RecipeRetryKind {
  /// The first attempt.
  first,

  /// A regeneration prompted by the cooking-times compatibility validator.
  compatibility,

  /// A regeneration prompted by the safety validator.
  safety,
}

/// One generation attempt. [correctionNote] is null on the first attempt and
/// carries a validator's correction text on a retry; [retryKind] lets the
/// caller bill the call to the right cost surface.
typedef RecipeGenerationAttempt = Future<String?> Function({
  String? correctionNote,
  required RecipeRetryKind retryKind,
});

/// Parses one raw model reply. [unknownKeysSink] is handed to
/// `parseChefRecipeJson` so declared keys outside the closed list are counted.
typedef RecipeAttemptParser = Future<CookModeRecipePayload?> Function(
  String raw,
  List<String> unknownKeysSink,
);

/// What the caller gets back. [recipe] is null only when generation itself
/// failed — an invalid or flagged recipe is still served.
@immutable
class ValidatedRecipeResult {
  const ValidatedRecipeResult({
    required this.recipe,
    required this.report,
    required this.retriesUsed,
    required this.servedWithFlags,
    this.safetyReport = const SafetyReport.clean(),
    this.safetyRetriesUsed = 0,
    this.servedWithSafetyFindings = false,
  });

  final CookModeRecipePayload? recipe;
  final CompatibilityReport report;

  /// How many compatibility corrections were spent, 0 to
  /// [kMaxCompatibilityRetries].
  final int retriesUsed;

  /// True when the recipe handed back still breaks the one-band rule — the
  /// silent fail-open case. **Nothing in the UI reads this**; it exists for
  /// the log and for tests.
  final bool servedWithFlags;

  /// The safety pass over the recipe that is actually being served, including
  /// the deterministic injections that were applied to it.
  final SafetyReport safetyReport;

  /// How many safety corrections were spent, 0 to [kMaxSafetyRetries].
  final int safetyRetriesUsed;

  /// True when a correctable safety finding survived every correction round.
  /// The recipe is still served — that is the registry's signed behaviour —
  /// but H1's injected cue has been applied regardless.
  final bool servedWithSafetyFindings;
}

/// Signed cap. Two corrections, then serve whatever we have.
const int kMaxCompatibilityRetries = 2;

/// Generate → validate (timing) → correct → validate (safety) → correct →
/// inject → serve.
///
/// # Ordering, and why it is this way round
///
/// Compatibility runs first and settles completely; safety then judges **the
/// recipe that is actually going to be served**. If safety ran first, a
/// compatibility retry afterwards would produce a different recipe that no
/// safety rule had ever seen, and the injected cue would be lost with the
/// discarded draft.
///
/// The deterministic injection is applied **last of all**, after every
/// correction round of both layers, so nothing downstream can undo it. That
/// is the concrete meaning of "injection must survive any retry".
///
/// # Two different philosophies in one function
///
/// The compatibility half is advisory and fails open silently
/// (`CookingCompatibilityValidator`'s own doc explains why). The safety half
/// does not fail open on H1: the cue is written onto the recipe by the app
/// whether or not the model ever cooperated, and no failure path skips it.
/// The remaining safety rules follow the registry's signed
/// correction-and-regenerate behaviour, capped at [kMaxSafetyRetries], after
/// which the recipe is served and the finding logged — a signed decision,
/// recorded in `docs/safety_hazard_registry.md`, not a relaxation invented
/// here.
///
/// A retry that fails to generate or fails to parse does NOT discard the
/// recipe we already have, in either half. Losing a servable recipe to a
/// failed correction attempt would be strictly worse than serving the flagged
/// one, which is the same reasoning the caps themselves rest on.
Future<ValidatedRecipeResult> generateValidatedRecipe({
  required RecipeGenerationAttempt attempt,
  required RecipeAttemptParser parse,
  required String logSurface,
  int maxRetries = kMaxCompatibilityRetries,
  int maxSafetyRetries = kMaxSafetyRetries,
}) async {
  CookModeRecipePayload? best;
  var bestReport = const CompatibilityReport.clean();
  var retriesUsed = 0;

  for (var i = 0; i <= maxRetries; i++) {
    final isRetry = i > 0;
    if (isRetry) retriesUsed = i;

    final raw = await attempt(
      correctionNote: isRetry ? bestReport.buildCorrectionNote() : null,
      retryKind: isRetry ? RecipeRetryKind.compatibility : RecipeRetryKind.first,
    );

    if (raw == null || raw.trim().isEmpty) {
      if (best != null) break; // keep what we have
      // First attempt produced nothing at all: that is a generation failure,
      // not a validation outcome, and is the caller's existing error path.
      return const ValidatedRecipeResult(
        recipe: null,
        report: CompatibilityReport.clean(),
        retriesUsed: 0,
        servedWithFlags: false,
      );
    }

    final unknownKeys = <String>[];
    final parsed = await parse(raw, unknownKeys);
    if (parsed == null) {
      if (best != null) break; // a failed correction never costs us a recipe
      return const ValidatedRecipeResult(
        recipe: null,
        report: CompatibilityReport.clean(),
        retriesUsed: 0,
        servedWithFlags: false,
      );
    }

    final report = validateCookingCompatibility(parsed, unknownKeys: unknownKeys);

    // A retry is only worth keeping if it is actually better. The model can
    // "correct" itself into a worse recipe, and there is no reason to prefer
    // the newer one when it is.
    if (best == null || report.flags.length < bestReport.flags.length) {
      best = parsed;
      bestReport = report;
    }

    if (bestReport.isClean) break;
  }

  // ── Safety layer, on the recipe that survived the compatibility half ─────
  var safetyRetriesUsed = 0;
  var safetyReport = validateRecipeSafety(best!);

  for (var i = 1; i <= maxSafetyRetries && safetyReport.hasCorrectable; i++) {
    final raw = await attempt(
      correctionNote: safetyReport.buildCorrectionNote(),
      retryKind: RecipeRetryKind.safety,
    );
    if (raw == null || raw.trim().isEmpty) break;

    final unknownKeys = <String>[];
    final parsed = await parse(raw, unknownKeys);
    if (parsed == null) break;

    safetyRetriesUsed = i;
    final candidate = validateRecipeSafety(parsed);

    // Safety findings outrank timing flags: a correction that fixes a hazard
    // and costs a band is the trade the registry already made by choosing
    // correction over blocking.
    if (candidate.correctable.length < safetyReport.correctable.length) {
      best = parsed;
      safetyReport = candidate;
      bestReport = validateCookingCompatibility(parsed, unknownKeys: unknownKeys);
    }

    if (!safetyReport.hasCorrectable) break;
  }

  // ── The guarantee. Applied last, unconditionally, to what is served ──────
  final injected = applySafetyInjections(best!);
  best = injected.recipe;

  // Re-read the served recipe so the report describes it rather than the
  // draft that preceded injection, and carry the applied injections.
  final finalFindings = validateRecipeSafety(best);
  safetyReport = SafetyReport(
    findings: finalFindings.findings,
    injections: injected.injections,
    stepsChecked: finalFindings.stepsChecked,
  );

  final servedWithFlags = !bestReport.isClean;
  final servedWithSafetyFindings = safetyReport.hasCorrectable;

  await CompatibilityFlagLog.record(
    surface: logSurface,
    report: bestReport,
    retriesUsed: retriesUsed,
    servedWithFlags: servedWithFlags,
  );
  await SafetyFlagLog.record(
    surface: logSurface,
    report: safetyReport,
    retriesUsed: safetyRetriesUsed,
    servedWithFindings: servedWithSafetyFindings,
  );

  return ValidatedRecipeResult(
    recipe: best,
    report: bestReport,
    retriesUsed: retriesUsed,
    servedWithFlags: servedWithFlags,
    safetyReport: safetyReport,
    safetyRetriesUsed: safetyRetriesUsed,
    servedWithSafetyFindings: servedWithSafetyFindings,
  );
}
