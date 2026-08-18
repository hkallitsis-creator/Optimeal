import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/ledger_service.dart';

/// Every outcome a completed cook session can produce with respect to the
/// Waste Ledger — see CLAUDE.md, "Waste Ledger legibility — option B"
/// (docs/DECISIONS.md) and Roadmap item 28. Display-only over the existing
/// [LedgerCompletionResult] sealed type and [CookModeSurface] — neither is
/// modified to support this; both already carry enough information (see
/// [selectLedgerVerdict]'s doc for how each variant is distinguished).
enum LedgerVerdict {
  /// A real waste_ledger_events row exists (fresh insert or an idempotent
  /// retry) and the celebration sheet already renders this — see
  /// [selectLedgerVerdict]'s doc; no separate verdict UI needed for this case.
  counted,

  /// The cook was from a surface that never counts (Custom AI Recipe
  /// Creator, Weekly Planner) — `logCompletion` was never called.
  notCountedWrongSurface,

  /// The cook was a re-cook (Home's Recently Cooked) — `logCompletion` was
  /// never called, regardless of the recipe's original surface.
  notCountedReCook,

  /// `logCompletion` was called, the surface was rescue-eligible, this was
  /// not a re-cook, but the write itself failed
  /// ([LedgerCompletionWriteFailed]) — the attempt is saved by
  /// [PendingLedgerWriteService] and will retry, not lost.
  writeFailedQueued,

  /// The hardcoded local-only demo recipe (no real [CookModeRecipePayload]
  /// at all — reachable via the bare `OnePanCookingRoadmapScreen()` route
  /// fallback in nav.dart when no launch extra is provided). Not a real
  /// cook, not a real rescue attempt — no verdict is shown for this case
  /// at all (see the UI call site); it's still its own enum value so the
  /// selection logic never has to guess or conflate it with a genuine
  /// "wrong surface" outcome.
  demo,
}

/// Picks the [LedgerVerdict] for a completed cook session.
///
/// Distinguishes all 5 outcomes from state the post-cook flow already
/// computes, with no changes to [LedgerService] or [CookModeSurface]:
/// - [LedgerVerdict.demo]: `hasPayload` is false (this is the only signal
///   that's independent of `surface`/`isReCook` — a demo cook can otherwise
///   present with the same `surface: null` as a Recently Cooked re-entry).
/// - [LedgerVerdict.notCountedReCook]: `isReCook` is true. Checked before
///   the surface check because Recently Cooked always launches with
///   `surface: null` regardless of the recipe's original surface — if
///   surface were checked first, a re-cook of an originally-eligible
///   recipe would be misclassified as [LedgerVerdict.notCountedWrongSurface].
/// - [LedgerVerdict.notCountedWrongSurface]: `surface` is null (only
///   reachable here, past the demo/re-cook checks, if a `CookModeLaunchRequest`
///   somehow omitted it) or [CookModeSurface.isRescueEligible] is false.
/// - [LedgerVerdict.writeFailedQueued]: everything above passed (a real
///   rescue-eligible, non-re-cook, non-demo completion), `logCompletion` was
///   called, and it returned [LedgerCompletionWriteFailed].
/// - [LedgerVerdict.counted]: same as above, but [LedgerCompletionSuccess].
///
/// [result] is only meaningful (and only ever non-null in real call sites)
/// when neither [demo] nor a "not counted" case applies — passing a non-null
/// result alongside e.g. `isReCook: true` is not a real call shape, but this
/// function still resolves deterministically (the re-cook check wins) rather
/// than throwing, since it's pure classification logic, not a guard.
LedgerVerdict selectLedgerVerdict({
  required bool hasPayload,
  required bool isReCook,
  required CookModeSurface? surface,
  required LedgerCompletionResult? result,
}) {
  if (!hasPayload) return LedgerVerdict.demo;
  if (isReCook) return LedgerVerdict.notCountedReCook;
  if (surface == null || !surface.isRescueEligible) {
    return LedgerVerdict.notCountedWrongSurface;
  }
  if (result is LedgerCompletionSuccess) return LedgerVerdict.counted;
  return LedgerVerdict.writeFailedQueued;
}

/// User-facing verdict copy, exactly one short line per verdict (device-test
/// round F3 — the verdict sheet is one icon, one line, one CTA now, not a
/// multi-line explainer). Plain, warm, non-technical, under 15 words.
/// [LedgerVerdict.counted] has no entry here: the existing celebration
/// sheet already serves as that verdict (CLAUDE.md instruction — keep it,
/// don't duplicate it). [LedgerVerdict.demo] also has no entry: no verdict
/// is shown for it at all.
const Map<LedgerVerdict, String> ledgerVerdictCopy = {
  LedgerVerdict.notCountedWrongSurface:
      "This wasn't cooked from your fridge — only Fridge Clearer cooks count.",
  LedgerVerdict.notCountedReCook:
      "Already counted the first time you cooked this — re-cooks don't count again.",
  LedgerVerdict.writeFailedQueued:
      "Your rescue is saved and will sync automatically — nothing's lost.",
};
