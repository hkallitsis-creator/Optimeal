/// Ingredient names that mean each of the fourteen allergens the Profile
/// screen offers.
///
/// # STATUS: SIGNED by Chef Harris, 23 August 2026
///
/// The fourteen keys are exactly the options `ProfileScreen` shows, and match
/// the EU/CH declarable-allergen set. The synonym lists were drafted on
/// 2026-08-23 and signed the same day, including the two calls flagged for
/// attention: `soy sauce` and `beer` sit under **both** Gluten and their own
/// allergen (soy sauce is usually wheat-brewed), and **coconut is NOT a tree
/// nut** — it is not one botanically or under EU rules, though some allergy
/// guidance treats it as one.
///
/// # Why this exists at all
///
/// The prompt already carries an allergen instruction, and on real dev output
/// it works for the recipe itself: a profile avoiding egg, dairy and tree nuts,
/// handed "eggs, cheese, walnuts" as available ingredients, still got a recipe
/// using none of them. That is the model complying. It is not a guarantee.
///
/// This list is the deterministic half — the part that does not depend on the
/// model having a good day. It is matched **whole-word** against generated
/// ingredient names, and a hit is a real finding rather than a hint.
///
/// # Matching rules that matter
///
/// Whole-word, case-insensitive, optional trailing s/es. That is load-bearing:
/// `soy` inside `soya` is fine (listed), but `nut` inside `nutmeg`, `nutrition`
/// and `nutritional yeast` is not — and "nutritional yeast" is a *vegan
/// substitute for cheese* that appeared in real output for exactly this
/// profile. A substring matcher would have flagged the substitute as the
/// allergen it was replacing.
library;

/// Allergen label → the ingredient words that mean it.
///
/// Keys are byte-identical to `ProfileScreen`'s options; a test asserts that,
/// so renaming a chip cannot silently orphan its synonyms.
const Map<String, List<String>> kAllergenSynonymsDraft = {
  'Gluten': [
    'wheat', 'flour', 'bread', 'breadcrumb', 'breadcrumbs', 'pasta',
    'spaghetti', 'penne', 'tagliatelle', 'noodle', 'noodles', 'couscous',
    'barley', 'rye', 'spelt', 'semolina', 'farro', 'bulgur', 'seitan',
    'panko', 'crouton', 'croutons', 'puff pastry', 'filo', 'phyllo',
    'soy sauce', 'beer',
  ],
  'Lactose/Dairy': [
    'milk', 'cream', 'double cream', 'single cream', 'creme fraiche',
    'crème fraîche', 'butter', 'buttermilk', 'cheese', 'parmesan',
    'pecorino', 'cheddar', 'mozzarella', 'feta', 'ricotta', 'mascarpone',
    'gruyere', 'gruyère', 'emmental', 'raclette', 'yoghurt', 'yogurt',
    'ghee', 'quark', 'creme', 'custard',
    // Adjectival forms. "Cheesy Potato Skillet" is a real leaked stage-1
    // title, and whole-word matching means `cheese` does not catch `cheesy` —
    // the dish name is the only thing the ideas screen shows, so the adjective
    // is often the ONLY signal there is.
    'cheesy', 'creamy', 'buttery', 'milky',
  ],
  'Tree Nuts': [
    'almond', 'almonds', 'hazelnut', 'hazelnuts', 'walnut', 'walnuts',
    'pecan', 'pecans', 'cashew', 'cashews', 'pistachio', 'pistachios',
    'macadamia', 'brazil nut', 'brazil nuts', 'pine nut', 'pine nuts',
    'chestnut', 'chestnuts', 'praline', 'marzipan', 'nutella',
    'nutty',
  ],
  'Peanuts': [
    'peanut', 'peanuts', 'groundnut', 'groundnuts', 'peanut butter',
    'satay',
  ],
  'Fish': [
    'fish', 'salmon', 'cod', 'haddock', 'tuna', 'trout', 'mackerel',
    'sardine', 'sardines', 'anchovy', 'anchovies', 'sea bass', 'seabass',
    'halibut', 'plaice', 'pollock', 'hake', 'herring', 'fish sauce',
    'worcestershire',
  ],
  'Crustaceans': [
    'prawn', 'prawns', 'shrimp', 'shrimps', 'crab', 'lobster',
    'langoustine', 'langoustines', 'crayfish', 'scampi', 'crevette',
  ],
  'Molluscs': [
    'mussel', 'mussels', 'clam', 'clams', 'oyster', 'oysters', 'squid',
    'calamari', 'octopus', 'scallop', 'scallops', 'snail', 'snails',
  ],
  'Soy': [
    'soy', 'soya', 'soybean', 'soybeans', 'tofu', 'edamame', 'miso',
    'tempeh', 'soy sauce', 'tamari',
  ],
  'Sesame': [
    'sesame', 'tahini', 'halva', 'gomashio',
  ],
  'Celery': [
    'celery', 'celeriac', 'celery salt',
  ],
  'Mustard': [
    'mustard', 'dijon', 'wholegrain mustard', 'mustard seed',
    'mustard seeds',
  ],
  'Sulfites/Alcohol': [
    'wine', 'white wine', 'red wine', 'beer', 'brandy', 'sherry', 'vermouth',
    'rum', 'vodka', 'whisky', 'whiskey', 'cider', 'prosecco', 'sulfite',
    'sulfites', 'sulphite', 'sulphites',
  ],
  'Lupin': [
    'lupin', 'lupine', 'lupin flour',
  ],
  'Egg': [
    'egg', 'eggs', 'egg white', 'egg whites', 'egg yolk', 'egg yolks',
    'mayonnaise', 'mayo', 'aioli', 'meringue', 'albumen',
  ],
};

final Map<String, RegExp> _patternCache = {};

RegExp _pattern(String word) => _patternCache.putIfAbsent(
      word,
      () => RegExp(
        r'\b' '${RegExp.escape(word)}' r'(?:es|s)?\b',
        caseSensitive: false,
      ),
    );

/// The allergen labels [text] trips, out of [avoided].
///
/// [avoided] comes straight from `UserProfile.allergies`, so a label the user
/// never selected is never checked — this can only ever report something the
/// user actually asked to avoid.
Set<String> allergensIn(String text, List<String> avoided) {
  if (text.trim().isEmpty || avoided.isEmpty) return const {};

  final hits = <String>{};
  for (final label in avoided) {
    final synonyms = kAllergenSynonymsDraft[label];
    if (synonyms == null) continue;
    for (final word in synonyms) {
      if (_pattern(word).hasMatch(text)) {
        hits.add(label);
        break;
      }
    }
  }
  return hits;
}

/// The specific word that tripped [label] in [text], for the log and for the
/// model-facing correction. Null when nothing matched.
String? matchedSynonym(String text, String label) {
  final synonyms = kAllergenSynonymsDraft[label];
  if (synonyms == null) return null;
  for (final word in synonyms) {
    if (_pattern(word).hasMatch(text)) return word;
  }
  return null;
}
