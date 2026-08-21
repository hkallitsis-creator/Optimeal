import 'package:optimeal/data/cooking_times.dart';

/// Closed vocabulary for [RecipeIngredient.cut] — the single source of
/// truth used both to build the AI-facing schema prompt (so the model is
/// told exactly these values are allowed) and to validate the AI's
/// response on the way in (so a value outside this list is treated the
/// same as a missing one, never passed through as free text). Introduced
/// so a reference photo library can be shot against a fixed set of cuts
/// later — this file does not do anything with images itself.
const List<String> ingredientCutVocabulary = [
  'whole',
  'halved',
  'quartered',
  'wedges',
  'rough_chop',
  'small_dice',
  'medium_dice',
  'large_dice',
  'thin_slice',
  'thick_slice',
  'julienne',
  'grated',
  'minced',
  'crushed',
  'torn',
  'none',
];

/// One-line, beginner-actionable definition for each [ingredientCutVocabulary]
/// value, in Chef Harris's voice. Dice and slice entries give an
/// approximate size so "small dice" means something concrete rather than
/// a vague size word. Kept next to the vocabulary itself so the two can
/// never drift apart — every key here is exactly one of
/// [ingredientCutVocabulary]'s values, and every value of
/// [ingredientCutVocabulary] has an entry here.
///
/// Deliberately text-only — no images. A reference photo library shot
/// against this same vocabulary will slot in wherever this definition is
/// shown, later.
const Map<String, String> ingredientCutDefinitions = {
  'whole': 'Left completely intact — skin, peel, and all, nothing removed.',
  'halved': 'Cut straight through the middle into two equal pieces.',
  'quartered': 'Cut into four roughly equal pieces — halve it, then halve each half.',
  'wedges': 'Cut into thick triangular segments, like an orange cut into wedges — wider than a dice or a slice.',
  'rough_chop': "Cut into uneven, chunky pieces roughly 2–3cm across — precision doesn't matter here.",
  'small_dice': 'Cut into neat cubes about 5mm — small enough to cook fast and evenly.',
  'medium_dice': 'Cut into neat cubes about 1cm — the everyday, all-purpose dice.',
  'large_dice': 'Cut into neat cubes about 2cm — chunky enough to hold their shape through a long cook.',
  'thin_slice': 'Sliced about 2–3mm thick — thin enough to cook quickly.',
  'thick_slice': 'Sliced about 1cm thick — hearty enough to hold its shape.',
  'julienne': 'Cut into thin matchsticks, about 2mm × 2mm and 4–5cm long.',
  'grated': 'Shredded on a grater into fine shreds — no knife needed.',
  'minced': 'Chopped as finely as your knife allows — fine enough to almost become a paste.',
  'crushed': 'Smashed with the flat of a knife or a press — skin loosened, no fine chopping needed.',
  'torn': "Torn by hand into rough pieces — no knife needed, and it's kinder to delicate leaves.",
  'none': 'No cutting needed — use it exactly as it comes.',
};

/// Human-readable label for a raw [ingredientCutVocabulary] value, e.g.
/// "small_dice" -> "small dice". Every current value is snake_case with
/// no other punctuation, so a straight underscore-to-space swap is exact.
String ingredientCutLabel(String cut) => cut.replaceAll('_', ' ');

class RecipeIngredient {
  final String name;
  final double amount;
  final String unit; // e.g. "g", "ml", "tbsp", "piece"

  /// How this ingredient is cut/prepped, from the closed
  /// [ingredientCutVocabulary] set. Optional on read: recipes saved before
  /// this field existed, or a raw value outside the vocabulary, both
  /// parse as null rather than failing — see [RecipeIngredient.fromJson].
  final String? cut;

  /// Which row of the signed cooking-times table this ingredient is, from the
  /// closed [CookingTimes.allKeys] list — the fifth instance of the
  /// closed-vocabulary pattern. The model declares only the key; the app
  /// resolves it to a band locally (signed option C). Null when the model
  /// declared nothing, declared something outside the list, or the ingredient
  /// genuinely has no row (seasonings, oil, stock). Null means "no timing
  /// check possible here", which is the fail-open outcome by construction.
  final String? cookingTimesKey;

  RecipeIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    this.cut,
    this.cookingTimesKey,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    final rawCut = json['cut'];
    final cut = (rawCut is String && ingredientCutVocabulary.contains(rawCut)) ? rawCut : null;
    final rawKey = json['cooking_times_key'];
    return RecipeIngredient(
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String,
      cut: cut,
      cookingTimesKey: (rawKey is String && CookingTimes.isKnown(rawKey)) ? rawKey : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
        'cut': cut,
        'cooking_times_key': cookingTimesKey,
      };

  /// Returns a new ingredient with amount scaled by [factor],
  /// e.g. factor = 2.0 doubles the recipe.
  RecipeIngredient scaled(double factor) {
    return RecipeIngredient(
      name: name,
      amount: amount * factor,
      unit: unit,
      cut: cut,
      cookingTimesKey: cookingTimesKey,
    );
  }
}
