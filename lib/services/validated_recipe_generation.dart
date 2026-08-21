import 'package:flutter/foundation.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/compatibility_flag_log.dart';
import 'package:optimeal/services/cooking_compatibility_validator.dart';

/// One generation attempt. [correctionNote] is null on the first attempt and
/// carries the validator's correction text on a retry; [isRetry] lets the
/// caller bill the call to its own `_retry` cost surface.
typedef RecipeGenerationAttempt = Future<String?> Function({
  String? correctionNote,
  required bool isRetry,
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
  });

  final CookModeRecipePayload? recipe;
  final CompatibilityReport report;

  /// How many correction regenerations were spent, 0 to [kMaxCompatibilityRetries].
  final int retriesUsed;

  /// True when the recipe handed back still breaks the one-band rule — the
  /// silent fail-open case. **Nothing in the UI reads this**; it exists for
  /// the log and for tests.
  final bool servedWithFlags;
}

/// Signed cap. Two corrections, then serve whatever we have.
const int kMaxCompatibilityRetries = 2;

/// Generate → validate → correct → serve.
///
/// Implements rule 6 of the signed table ("on flag, inject a correction and
/// regenerate rather than blocking the user") with the ruling from this
/// build's brief: at most [kMaxCompatibilityRetries] regenerations, then
/// **silent fail-open**. The user is never told, never blocked, and never
/// shown a warning — a flagged recipe reaching the screen is indistinguishable
/// to them from a clean one. Everything that is known about the failure goes
/// to [CompatibilityFlagLog].
///
/// A retry that fails to generate or fails to parse does NOT discard the
/// recipe we already have. Losing a servable recipe to a failed correction
/// attempt would be strictly worse than serving the flagged one, which is the
/// same reasoning the cap itself rests on.
Future<ValidatedRecipeResult> generateValidatedRecipe({
  required RecipeGenerationAttempt attempt,
  required RecipeAttemptParser parse,
  required String logSurface,
  int maxRetries = kMaxCompatibilityRetries,
}) async {
  CookModeRecipePayload? best;
  var bestReport = const CompatibilityReport.clean();
  var retriesUsed = 0;

  for (var i = 0; i <= maxRetries; i++) {
    final isRetry = i > 0;
    if (isRetry) retriesUsed = i;

    final raw = await attempt(
      correctionNote: isRetry ? bestReport.buildCorrectionNote() : null,
      isRetry: isRetry,
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

  final servedWithFlags = best != null && !bestReport.isClean;
  await CompatibilityFlagLog.record(
    surface: logSurface,
    report: bestReport,
    retriesUsed: retriesUsed,
    servedWithFlags: servedWithFlags,
  );

  return ValidatedRecipeResult(
    recipe: best,
    report: bestReport,
    retriesUsed: retriesUsed,
    servedWithFlags: servedWithFlags,
  );
}
