/// Shelf-stable pantry staples excluded from the Waste Ledger's "ingredients
/// rescued" count (device-test round F13, Harris's decision — replaces the
/// old `LedgerService.freshProduceOnly` blocklist entirely).
///
/// Provenance is the new rule's default: an entered ingredient that shows
/// up in the cooked recipe counts UNLESS it's on this list. That's the
/// opposite bias from the old blocklist, which grew to include things
/// (potatoes, onions, garlic, ginger) that are genuinely perishable and
/// were being wrongly excluded — see CLAUDE.md Roadmap item 8's "the
/// potato case". This list should only ever hold things with a genuinely
/// long shelf life that nobody would call "at risk of going to waste" —
/// salt doesn't spoil.
///
/// Content list — Harris edits this as content later; matching is a plain
/// case-insensitive substring check ([isPantryStaple]), no code change
/// needed to add or remove an entry.
const List<String> pantryStaples = [
  'salt',
  'pepper',
  'oil',
  'olive oil',
  'vegetable oil',
  'sunflower oil',
  'sesame oil',
  'vinegar',
  'sugar',
  'flour',
  'pasta',
  'rice',
  'dried herbs',
  'dried spices',
  'paprika',
  'cumin',
  'cinnamon',
  'oregano',
  'thyme',
  'bay leaf',
  'stock cube',
  'bouillon',
];

/// True if [ingredient] matches a [pantryStaples] entry as a
/// case-insensitive substring.
bool isPantryStaple(String ingredient) {
  final lower = ingredient.toLowerCase();
  return pantryStaples.any((staple) => lower.contains(staple));
}
