/// Detects a generated "prepare your ingredients" step so the app never shows
/// two prep steps.
///
/// # Why this exists
///
/// Cook Mode has always prepended a client-synthesized mise-en-place step.
/// Generations *also* routinely emit their own prep step ("Prepare Your
/// Ingredients", "Gather and prep"), and nothing removed it — so on device the
/// user saw the synthesized Step 1 followed immediately by the model's own
/// prep step saying the same thing. Confirmed on Harris's 22 Aug screenshots.
///
/// # Deliberately conservative
///
/// A false positive deletes a real cooking step, which is far worse than a
/// duplicate prep step. So this only ever inspects the **first** step — step 2
/// onward is never a candidate, whatever it says — and requires either an
/// explicit prep-ish title or the much stricter "no cooking verb anywhere AND
/// every bullet names an ingredient" shape.
library;

/// Title words that make a first step a prep step outright.
final RegExp _prepTitle =
    RegExp(r'\b(prep|prepare|preparation|mise|gather|ingredients|set\s?up)\b',
        caseSensitive: false);

/// Any of these anywhere in the step means it is real cooking, not prep, and
/// overrides everything below.
final RegExp _cookingVerb = RegExp(
  r'\b(heat|heats|heated|heating|sear|sears|seared|searing|fry|fries|fried|'
  r'frying|saut|boil|boils|boiled|boiling|simmer|simmers|simmered|simmering|'
  r'roast|roasts|roasted|roasting|bake|bakes|baked|baking|grill|grills|'
  r'grilled|grilling|steam|steams|steamed|steaming|toast|toasts|toasted|'
  r'toasting|brown|browns|browned|browning|cook|cooks|cooked|cooking|'
  r'deglaze|reduce|reduces|reduced|reducing|melt|melts|melted|melting|'
  r'stir-fry|poach|poaches|poached|poaching|blanch|braise|simmer)\b',
  caseSensitive: false,
);

/// True when [title]/[bullets] describe a prep step rather than cooking.
///
/// [ingredientNames] are the recipe's own ingredient names, used for the
/// stricter second branch.
bool looksLikeGeneratedPrepStep({
  required String title,
  required List<String> bullets,
  required List<String> ingredientNames,
}) {
  final body = bullets.join(' ');
  final whole = '$title $body';

  // A cooking verb anywhere disqualifies it, even under a prep-ish title:
  // "Prep and sear the chicken" is a cooking step with a misleading name, and
  // deleting it would delete the sear.
  if (_cookingVerb.hasMatch(whole)) return false;

  if (_prepTitle.hasMatch(title)) return true;

  // Second branch, much stricter: no cooking verb (already established) AND
  // every bullet names a real ingredient from this recipe.
  if (bullets.isEmpty || ingredientNames.isEmpty) return false;

  final needles = ingredientNames
      .map(_headNoun)
      .where((n) => n.isNotEmpty)
      .toSet();
  if (needles.isEmpty) return false;

  return bullets.every((b) {
    final lower = b.toLowerCase();
    return needles.any((n) => RegExp(
            r'\b' '${RegExp.escape(n)}' r'(?:e?s)?\b',
            caseSensitive: false)
        .hasMatch(lower));
  });
}

String _headNoun(String name) {
  final words = name
      .toLowerCase()
      .replaceAll(RegExp(r'[(),.]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  var head = words.last;
  if (head.length > 4 && head.endsWith('es')) {
    head = head.substring(0, head.length - 2);
  } else if (head.length > 3 && head.endsWith('s')) {
    head = head.substring(0, head.length - 1);
  }
  return head;
}
