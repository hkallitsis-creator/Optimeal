import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:optimeal/models/recipe_model.dart';

/// Servings scaling for the recipe overview — pure arithmetic and formatting,
/// no widgets, so the rules that matter can be tested directly.
///
/// # The signed rules
///
/// * Quantities rescale live from structured data: `base × N / basePortions`.
/// * **Whole-piece rule:** countable ingredients ROUND UP to the next whole,
///   and the row says so when rounding actually changed the number. "1.5 eggs"
///   is not a thing a kitchen can produce; "2 eggs · rounded up" is honest
///   about why it is not 1.5.
/// * Non-count units display exact, at sensible precision.
/// * Range 1–6, extended only when the profile household exceeds it.
///
/// Scale is **launch context, never persisted**. A saved recipe keeps its
/// `basePortions`; the N the user picked on the overview travels on
/// `CookModeLaunchRequest` and dies with it.

/// Signed range floor.
const int kServingsMin = 1;

/// Signed range ceiling, extended only by [servingsCeilingFor].
const int kServingsMax = 6;

/// Units whose quantities are countable, and therefore round up whole.
///
/// An empty unit counts too: the model sometimes emits `{name: "eggs",
/// amount: 4, unit: ""}`, and a unit-less amount is a count by definition.
const Set<String> kCountableUnits = {'piece', 'pieces', 'clove', 'cloves', 'slice', 'slices'};

/// Units where a half or a quarter is a normal thing to write, so fractions
/// read better than decimals.
const Set<String> kFractionUnits = {'tsp', 'tbsp'};

/// Units measured finely enough that a value of 100+ does not want a
/// single-gram claim of precision.
const Set<String> kBulkUnits = {'g', 'ml', 'gram', 'grams', 'millilitre', 'millilitres'};

/// The ceiling for the stepper. 6 unless the household is bigger, in which
/// case cooking for the household must remain reachable.
int servingsCeilingFor({int? householdServings}) {
  final household = householdServings ?? 0;
  return household > kServingsMax ? household : kServingsMax;
}

/// The N the overview opens on, by signed precedence:
/// planner slot context > profile household > the recipe's own basePortions.
///
/// Each source is used only when it actually says something: a null planner
/// context does not out-rank a real profile value.
int defaultServingsFor({
  int? plannerServings,
  int? profileHouseholdServings,
  int? recipeBasePortions,
}) {
  final chosen = plannerServings ??
      profileHouseholdServings ??
      recipeBasePortions ??
      2;
  final ceiling = servingsCeilingFor(householdServings: profileHouseholdServings);
  return chosen.clamp(kServingsMin, ceiling);
}

/// One ingredient, scaled and formatted for display.
@immutable
class ScaledIngredient {
  const ScaledIngredient({
    required this.name,
    required this.displayAmount,
    required this.roundedUp,
    required this.raw,
  });

  /// The ingredient's name, verbatim from the model. Deliberately not
  /// re-cased: it is generated content, and lower-casing it would mangle
  /// "Parmesan" and "Dijon" to fix nothing.
  final String name;

  /// Quantity plus unit, already formatted — "4", "200 g", "½ tsp".
  /// The unit word "piece" never appears; a count is just a number.
  final String displayAmount;

  /// True when the whole-piece rule actually changed the number, which is the
  /// only time the row earns its hint.
  final bool roundedUp;

  final RecipeIngredient raw;

  /// The full row text, for tests and for anywhere a single string is wanted.
  String get displayLine =>
      displayAmount.isEmpty ? name : '$displayAmount $name';
}

/// Scales one ingredient list from [basePortions] to [servings].
///
/// A null or non-positive [basePortions] means the recipe never declared what
/// it was written for, so there is nothing to scale *from*: quantities are
/// shown as generated. The stepper is disabled in that case rather than
/// silently multiplying by a number nobody asserted.
List<ScaledIngredient> scaleIngredients({
  required List<RecipeIngredient> ingredients,
  required int? basePortions,
  required int servings,
}) {
  final base = (basePortions ?? 0) > 0 ? basePortions! : null;
  final factor = base == null ? 1.0 : servings / base;

  return [
    for (final ing in ingredients) _scaleOne(ing, factor),
  ];
}

ScaledIngredient _scaleOne(RecipeIngredient ing, double factor) {
  final unit = ing.unit.trim().toLowerCase();
  final scaled = ing.amount * factor;

  if (_isCountable(unit)) {
    // Ceil, always. Half an egg is not a quantity.
    final whole = scaled <= 0 ? 0 : scaled.ceil();
    final changed = (whole - scaled).abs() > 1e-9;
    return ScaledIngredient(
      name: ing.name,
      displayAmount: whole == 0 ? '' : '$whole',
      roundedUp: changed,
      raw: ing,
    );
  }

  final amountText = _formatAmount(scaled, unit);
  final unitText = ing.unit.trim();
  return ScaledIngredient(
    name: ing.name,
    displayAmount:
        amountText.isEmpty ? '' : (unitText.isEmpty ? amountText : '$amountText $unitText'),
    roundedUp: false,
    raw: ing,
  );
}

bool _isCountable(String unit) => unit.isEmpty || kCountableUnits.contains(unit);

String _formatAmount(double value, String unit) {
  if (value <= 0) return '';

  if (kFractionUnits.contains(unit)) {
    final fraction = _asFraction(value);
    if (fraction != null) return fraction;
  }

  if (kBulkUnits.contains(unit) && value >= 100) {
    // Nearest 5. A scaled 187.5 g is a false precision; 190 g is what a cook
    // would actually weigh.
    final rounded = (value / 5).round() * 5;
    return '$rounded';
  }

  // One decimal at most, trailing .0 dropped.
  final oneDecimal = (value * 10).round() / 10;
  if ((oneDecimal - oneDecimal.roundToDouble()).abs() < 1e-9) {
    return '${oneDecimal.round()}';
  }
  return oneDecimal.toStringAsFixed(1);
}

/// ½ / ¼ / ¾ and their mixed forms, for spoon measures only.
String? _asFraction(double value) {
  final whole = value.floor();
  final remainder = value - whole;

  String? glyph;
  if ((remainder - 0.5).abs() < 1e-6) glyph = '½';
  if ((remainder - 0.25).abs() < 1e-6) glyph = '¼';
  if ((remainder - 0.75).abs() < 1e-6) glyph = '¾';
  if (glyph == null) return null;

  return whole == 0 ? glyph : '$whole$glyph';
}

/// Total heated minutes across a recipe's steps, for the meta line.
int estimatedMinutes(Iterable<int> stepDurations) =>
    stepDurations.fold(0, (a, b) => a + math.max(0, b));
