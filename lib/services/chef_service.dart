import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/chef_curiculum_techniques.dart';
import 'package:optimeal/chef_curiculum_reference.dart';
import 'package:optimeal/chef_curiculum_lookups.dart';

/// Service for "Ask Chef Harris" AI help.
///
/// Uses Dreamflow's OpenAI proxy (configured via build-time env vars).
class ChefService {
  ChefService();

  /// Every curriculum drawer key a generated recipe may declare as what it
  /// teaches — sourced directly from the drawer maps below, so this list
  /// can never contain a key that doesn't actually exist, or omit one
  /// that does. Single source of truth for both the prompt (what values
  /// the model is told are legal) and the parser (what values are
  /// accepted on the way back) — see [ChefRecipeSurface] callers for the
  /// "curriculum_lesson_id" field this backs.
  ///
  /// Excludes 'general_tips' — a generic SOS fallback, not a taught
  /// lesson (same exclusion the old keyword-matching already made in
  /// [matchedCurriculumDrawerKeys] and [featurableDrawerKeys]).
  static final List<String> curriculumDrawerKeys = [
    ...chefTechniqueDrawers.keys,
    ...chefReferenceDrawers.keys.where((k) => k != 'general_tips'),
  ];

  /// Full Chef Harris persona. Keep this unshortened so responses stay consistent.
  static const String _systemPersona =
      'You are Chef Harris, a European culinary generalist and strategist with a dry, warm sense of humor and an obsession with precise cooking. '
      'Your goal is to transform leftover fridge ingredients into delicious, zero-waste, budget-friendly meals.\n\n'
      'IDENTITY & BACKGROUND:\n'
      '- Name: Chef Harris\n'
      '- Role: Professional chef and culinary strategist trained across European kitchens, with no single home base — draws equally from French technique, Italian simplicity, and other regional traditions.\n'
      '- Style: Practical and no-nonsense, with Mediterranean warmth; efficient, structured, no guesswork.\n'
      '- Personality: Dry, warm wit — a clever line is welcome, but never at the expense of clarity.\n\n'
      'PERSONALITY & HUMOR RULES:\n'
      '- BE WITTY IN TIPS & VOICE: Include a playful, clever culinary remark inside Chef Harris “checkpoint” notes or conversational responses.\n'
      '  Example: "Don\'t rush the onions—caramelization requires patience, not enthusiasm!"\n'
      '- HIGH PRECISION IN STEPS: Keep actual cooking steps crystal-clear, concise, and technical. Do NOT hide instructions inside jokes.\n\n'
      'FEW-SHOT VOICE EXAMPLES (match this exact balance of dry wit + precision — do not copy these verbatim, use them only as a tone/structure reference):\n\n'
      'Example 1 — conversational SOS reply:\n'
      'User: "My risotto looks like wet cement."\n'
      'Chef Harris: "That\'s rice that got impatient — too much liquid went in at once. Kill the heat to low, stop adding stock, and let it sit uncovered 2–3 min so it can reduce. '
      'Stir gently and it\'ll tighten right up. Patience now, glory later. Happy cooking! — Chef Harris"\n\n'
      'Example 2 — a step bullet inside a generated recipe (shows wit folded into an instruction, not replacing it):\n'
      '"Sauté the onions on medium for 6–8 min until translucent — rushing this step is how you end up with regret instead of caramelization."\n\n'
      'CRITICAL COOKING & GENERATION RULES (ALWAYS):\n'
      '1) PRECISION TECHNIQUES: Never write vague instructions. Specify exact pan sizes, oil quantities (e.g., "1 tbsp / 15ml"), '
      'heat levels ("Medium-High"), and visual cues ("sauté 3 min until edges turn translucent and lightly golden").\n'
      '2) COOK MODE COMPATIBILITY: For any procedural steps, ALWAYS include timing + heat.\n'
      '   - If you output step STRINGS, each must contain a timing tag like "~4 min" and a heat label like "Low|Medium|High".\n'
      '   - If you output step OBJECTS, include structured fields for duration (minutes) and heat level so the UI can render badges.\n'
      '3) PRAGMATIC BY DESIGN: Keep recipes simple, delicious, and tailored to everyday European household tastes and standard cookware.\n'
      '4) NO INGREDIENT HALLUCINATIONS: Use ONLY user-selected ingredients plus pantry staples: salt, pepper, cooking oil, water, and basic dried herbs.\n'
      '5) OUTPUT FORMAT (RECIPES): Always return structured JSON for recipes with title, ingredients (array), and steps (array).\n'
      '6) STRUCTURED OUTPUT DISCIPLINE & SCHEMA LOCK: If the user turn includes a JSON schema (field names and example shape), treat it as a strict, '
      'non-negotiable contract — not a loose suggestion:\n'
      '   - Use the EXACT field names given, at the exact nesting level given. Never rename, add, or drop fields.\n'
      '   - Match data types exactly: numeric fields (e.g. amount, duration_minutes) must be actual numbers, not quoted strings.\n'
      '   - If the schema asks for ingredients as objects (e.g. {"name":"...","amount":0,"unit":"..."}), return objects — do NOT collapse them into plain strings.\n'
      '   - If the schema asks for ingredients as plain strings, return plain strings — do NOT wrap them into objects.\n'
      '   - If the user requests JSON, return ONLY valid JSON matching that schema. No markdown, no commentary, no trailing text, no explanation before or after.\n'
      '   - If no explicit schema is given, fall back to the general shape in rule 5 above (title, ingredients array, steps array).\n\n'
      'TONE & VOICE:\n'
      '- Warm, direct, encouraging, and clear.\n'
      '- Use short, actionable sentences.\n'
      '- When NOT returning JSON, sign off micro-guidance with: "Happy cooking! — Chef Harris".';

  /// Bucket A — always-on curriculum knowledge. Small and cheap on purpose:
  /// the 5 universal chef instincts, core food-safety rules, and a
  /// compressed per-technique temp/ratio/doneness cheat-sheet. Full
  /// technique detail lives in Bucket B (chefTechniqueDrawers etc.) and is
  /// only pulled in per-call by _buildCurriculumAddendum below.
  static const String _curriculumCore =
      'CHEF HARRIS CORE CULINARY KNOWLEDGE (always apply):\n\n'
      'THE 5 UNIVERSAL CHEF INSTINCTS:\n'
      '1. Taste at every stage — seasoning is layered, not fixed once at the end.\n'
      '2. Don\'t crowd the pan/oven/grill — the single most common root cause of poor browning/texture across all techniques.\n'
      '3. Preheat before food goes in — cold starting surfaces cause sticking, steaming, and uneven cooking.\n'
      '4. Rest proteins, trust carryover — pulling slightly early and resting locks in juiciness and hits true target doneness.\n'
      '5. Scraps and near-spoiled food are ingredients — the zero-waste mindset is a flavor-building habit, not a limitation.\n\n'
      'CORE FOOD SAFETY (non-negotiable):\n'
      '- Danger zone is 4–60°C/40–140°F — minimize time food spends here.\n'
      '- Raw proteins always stored/handled below ready-to-eat items.\n'
      '- Cooling large batches: 60→21°C within 2 hrs, then 21→4°C within another 4 hrs.\n\n'
      'COMPRESSED TECHNIQUE CUE TABLE (target / key ratio / doneness signal):\n'
      '- Stir-Frying: 200–230°C, thin oil film, 50% wok max — aggressive continuous sizzle-roar.\n'
      '- Sautéing: 160–190°C, ~1mm oil, 70% pan — steady moderate sizzle.\n'
      '- Shallow Frying: 160–180°C, oil ⅓–½ up food — steady rolling bubble/crackle.\n'
      '- Deep Frying: 175–190°C, full submersion, 30% batch max — vigorous continuous bubbling.\n'
      '- Pan Searing: 220–240°C pan, 1–2 tsp oil, don\'t move for 2–3 min — immediate aggressive sizzle.\n'
      '- Boiling: 100°C, full submersion +2in headroom — continuous rolling bubbles.\n'
      '- Simmering: 85–96°C, ½–¾ up food — small lazy intermittent bubbles.\n'
      '- Steaming: 100°C (vapor), water 1–2in below basket — steady continuous steam.\n'
      '- Roasting: 160–230°C oven, 2.5cm spacing between pieces — thermometer + color.\n'
      '- Braising: sear hot then 140–160°C — liquid ⅓–½ up protein — fork-tender.\n'
      '- Grilling: two-zone 60/40 direct-to-indirect — touch test + thermometer.\n'
      '- Sweating Aromatics: 120–150°C — translucent, no browning.\n'
      '- Caramelizing: low-medium, 35–45+ min — deep mahogany color.\n'
      'Full technical detail for any of the above (plus knife work, mise en place, storage, substitutions, flavor pairings, '
      'and cuisine profiles) may be supplied below under CHEF HARRIS CURRICULUM REFERENCE when relevant — treat that as '
      'authoritative and do not contradict it.';

  /// Hard constraint: generated recipe complexity must match the user's kitchen confidence.
  ///
  /// Important: this is about what you generate (steps/techniques/multitasking), not only how you *describe* it.
  static const String _recipeDifficultyByKitchenConfidence =
      'RECIPE DIFFICULTY BY KITCHEN CONFIDENCE (generation constraint — obey):\n'
      '- Beginner: Generate recipes with no more than 5–6 steps. Use ONE main technique the user is very likely already comfortable with '
      '(sauté, boil, roast, simple stovetop assembly). Choose forgiving methods with a wide margin for error. Include at most ONE mildly unfamiliar step.\n'
      '- Intermediate: Allow 6–9 steps. You may combine up to TWO techniques (e.g., sear + pan sauce, or roast + quick reduction). '
      'Assume comfort with basic knife work and timing.\n'
      '- Advanced/Confident: Allow ambitious, technique-forward, multi-component builds (e.g., a seared protein with a proper reduction and a technique-forward side, '
      'braising, or a dish requiring active multitasking across two pans). Explicitly: do NOT default to the simplest possible dish '
      '(like a plain omelette or buttered pasta) for these users unless they specifically asked for something quick and easy.';

  /// Scans [searchText] for technique/topic keywords and returns the
  /// matching Bucket B drawer content (only what's relevant), ready to
  /// append to a prompt. Returns '' if nothing matched.
  String _buildCurriculumAddendum(String searchText) {
    final text = searchText.toLowerCase();
    final blocks = <String>[];

    // --- Technique drawers: match on the technique's plain-English name.
    var techniqueMatches = 0;
    for (final entry in chefTechniqueDrawers.entries) {
      final label = entry.key.replaceAll('_', ' ');
      if (text.contains(label)) {
        blocks.add(entry.value);
        techniqueMatches++;
        if (techniqueMatches >= 3) break;
      }
    }

    // --- Reference drawers: a few trigger keywords per topic.
    const referenceTriggers = <String, List<String>>{
      'mise_en_place': [
        'mise en place',
        'prep order',
        'organize my prep',
        'game plan'
      ],
      'food_storage': [
        'storage',
        'store this',
        'fridge',
        'freezer',
        'shelf life',
        'leftovers',
        'how long does'
      ],
      'cross_contamination': [
        'cross contamination',
        'raw chicken',
        'raw meat',
        'food safety',
        'same board'
      ],
      'knife_grip_mechanics': [
        'knife grip',
        'hold the knife',
        'knife technique',
        'claw grip'
      ],
      'core_knife_cuts': [
        'julienne',
        'brunoise',
        'dice',
        'chiffonade',
        'knife cut',
        'how do i cut',
        'how to cut'
      ],
      'knife_safety_protocol': [
        'knife safety',
        'cut myself',
        'safe with a knife'
      ],
      'general_tips': [
        'tip',
        'stuck',
        'went wrong',
        'ruined',
        'save this dish',
        'too salty',
        'too spicy',
        'too acidic',
        'broke',
        'broken sauce',
        'burnt',
        'flat',
        'bland',
      ],
    };
    var referenceMatches = 0;
    for (final entry in referenceTriggers.entries) {
      if (entry.value.any(text.contains)) {
        final content = chefReferenceDrawers[entry.key];
        if (content != null) {
          blocks.add(content);
          referenceMatches++;
          if (referenceMatches >= 3) break;
        }
      }
    }

    // --- Ingredient substitutions: only search when substitution intent is present.
    const substitutionIntent = [
      'substitute',
      'instead of',
      'swap',
      'replace',
      'alternative',
      'don\'t have',
      'out of',
      'no more',
      'ran out',
    ];
    if (substitutionIntent.any(text.contains)) {
      var subMatches = 0;
      for (final entry in chefIngredientSubstitutions.entries) {
        final label = entry.key.replaceAll('_', ' ');
        final firstWord = entry.key.split('_').first;
        if (text.contains(label) || text.contains(firstWord)) {
          blocks.add('SUBSTITUTION — $label: ${entry.value}');
          subMatches++;
          if (subMatches >= 4) break;
        }
      }
    }

    // --- Flavor pairings: match when at least 2 of a pairing's components appear.
    var pairingMatches = 0;
    for (final entry in chefFlavorPairings.entries) {
      final parts = entry.key.split('_');
      final hits = parts.where(text.contains).length;
      if (parts.length >= 2 && hits >= 2) {
        blocks.add(entry.value);
        pairingMatches++;
        if (pairingMatches >= 2) break;
      }
    }

    // --- Cuisine profiles: match on region name or common aliases (one per call).
    const cuisineAliases = <String, List<String>>{
      'mediterranean': ['mediterranean', 'italian', 'greek', 'spanish'],
      'middle_eastern': ['middle eastern', 'lebanese', 'israeli', 'turkish'],
      'indian': ['indian', 'curry'],
      'southeast_asian': [
        'southeast asian',
        'thai',
        'vietnamese',
        'indonesian'
      ],
      'japanese': ['japanese'],
      'latin_american': ['latin american', 'mexican', 'peruvian', 'caribbean'],
      'north_american': ['north american', 'american', 'tex-mex', 'tex mex'],
      'northern_european': ['northern european', 'scandinavian', 'nordic'],
      // Deliberately NOT the bare word 'swiss' — every Fridge Clearer prompt's
      // boilerplate context line literally says "Swiss home kitchen" (this is
      // a Swiss-first app), which made this block match unconditionally on
      // every single call regardless of what was actually being cooked. Use
      // more specific phrases so genuine "make this taste Swiss" intent still
      // matches without the false-positive tax on every request.
      'central_european': [
        'central european',
        'german',
        'austrian',
        'hungarian',
        'alpine',
        'swiss cuisine',
        'swiss dish',
        'swiss recipe',
        'swiss classic'
      ],
      'west_east_african': [
        'west african',
        'east african',
        'ethiopian',
        'nigerian'
      ],
    };
    for (final entry in cuisineAliases.entries) {
      if (entry.value.any(text.contains)) {
        final content = chefCuisineProfiles[entry.key];
        if (content != null) blocks.add(content);
        break;
      }
    }

    if (blocks.isEmpty) return '';

    return '\n---\n'
        'CHEF HARRIS CURRICULUM REFERENCE (authoritative technical data — use it, do not contradict it):\n\n'
        '${blocks.join('\n\n')}\n'
        '---\n';
  }

  /// Returns curriculum drawer keys that match [searchText] using the same
  /// lightweight keyword matching logic as [_buildCurriculumAddendum].
  ///
  /// - Technique keys are matched by checking whether the technique label
  ///   (underscores replaced with spaces) appears in the text (max 3).
  /// - Reference keys are matched via trigger keywords (max 3), but
  ///   intentionally exclude `general_tips` since that drawer is a generic
  ///   fallback rather than a specific taught topic.
  ///
  /// Returned keys are ordered with technique matches first, then reference
  /// matches, with no duplicates.
  List<String> matchedCurriculumDrawerKeys(String searchText) {
    debugPrint('CurriculumMatch: input="$searchText"');
    final text = searchText.toLowerCase();
    final out = <String>[];
    final seen = <String>{};

    // Small synonym/trigger set for technique drawers. This is intentionally
    // compact and biased toward the kind of language a generated recipe is
    // likely to contain.
    const techniqueTriggers = <String, List<String>>{
      'stir_frying': [
        'stir fry',
        'stir-fry',
        'stir-frying',
        'wok',
        'toss constantly',
        'high heat toss'
      ],
      'sauteing': [
        'sauté',
        'saute',
        'pan sauce',
        'deglaze',
        'sear the',
        'golden brown'
      ],
      'pan_searing': [
        'sear',
        'seared',
        'crust',
        "don't move it",
        'high heat sear'
      ],
      'boiling': ['boil', 'boiling', 'rolling boil'],
      'simmering': ['simmer', 'simmering', 'gentle bubble'],
      'steaming': ['steam', 'steaming', 'steamer basket'],
      'roasting': ['roast', 'roasting', 'oven', 'baking sheet'],
      'braising': ['braise', 'braising', 'low and slow'],
      'grilling': ['grill', 'grilling', 'grill marks'],
      'sweating_aromatics': ['sweat the', 'soften the onion', 'translucent'],
      'caramelization': ['caramelize', 'caramelizing', 'caramelized'],
    };

    var techniqueMatches = 0;
    for (final entry in chefTechniqueDrawers.entries) {
      final label = entry.key.replaceAll('_', ' ');
      final triggers = techniqueTriggers[entry.key];
      final matched =
          triggers == null ? text.contains(label) : triggers.any(text.contains);
      if (matched) {
        if (seen.add(entry.key)) out.add(entry.key);
        techniqueMatches++;
        if (techniqueMatches >= 3) break;
      }
    }

    const referenceTriggers = <String, List<String>>{
      'mise_en_place': [
        'mise en place',
        'prep order',
        'organize my prep',
        'game plan'
      ],
      'food_storage': [
        'storage',
        'store this',
        'fridge',
        'freezer',
        'shelf life',
        'leftovers',
        'how long does'
      ],
      'cross_contamination': [
        'cross contamination',
        'raw chicken',
        'raw meat',
        'food safety',
        'same board'
      ],
      'knife_grip_mechanics': [
        'knife grip',
        'hold the knife',
        'knife technique',
        'claw grip'
      ],
      'core_knife_cuts': [
        'julienne',
        'brunoise',
        'dice',
        'chiffonade',
        'knife cut',
        'how do i cut',
        'how to cut'
      ],
      'knife_safety_protocol': [
        'knife safety',
        'cut myself',
        'safe with a knife'
      ],
      'general_tips': [
        'tip',
        'stuck',
        'went wrong',
        'ruined',
        'save this dish',
        'too salty',
        'too spicy',
        'too acidic',
        'broke',
        'broken sauce',
        'burnt',
        'flat',
        'bland',
      ],
    };

    var referenceMatches = 0;
    for (final entry in referenceTriggers.entries) {
      if (entry.key == 'general_tips') continue;
      if (!entry.value.any(text.contains)) continue;

      final content = chefReferenceDrawers[entry.key];
      if (content == null) continue;

      if (seen.add(entry.key)) out.add(entry.key);
      referenceMatches++;
      if (referenceMatches >= 3) break;
    }

    debugPrint('CurriculumMatch: input="$searchText" → matched=$out');
    return out;
  }

  /// Recent-dish variety cap (CLAUDE.md roadmap item 13): how many recent
  /// dish titles get injected into the prompt as a "don't repeat these"
  /// instruction. Titles are short (~20-40 chars each), so even the max 10
  /// adds well under 100 tokens — negligible next to the ~2000-2500 token
  /// prompt budget already measured (see Roadmap item 5).
  static const int _maxRecentDishExclusions = 10;

  /// Cap on how many prior SOS turns (user + Chef Harris messages combined)
  /// get sent as conversation history — the last 3 exchanges. Uncapped
  /// history would grow every subsequent call within one SOS session
  /// (each answer becomes part of the next call's input), compounding cost
  /// with no bound. 3 exchanges is enough for a typical follow-up
  /// ("what if I don't have X" -> answer -> "ok what about Y") without
  /// that growth.
  static const int _maxSosHistoryMessages = 6;

  /// Curated dish-format/style keywords (lowercase) for the recipe-variety
  /// fix. Title-string exclusion alone can't stop the model renaming the
  /// same dish concept to dodge a literal match — the real bug seen in
  /// testing was five straight Fridge Clearer generations that were all,
  /// under different names, an egg-and-potato bake (frittata → hash → bake
  /// → skillet → bake). This is a hand-maintained list, not a classifier —
  /// it'll catch common cases but won't catch every possible rename; expect
  /// to extend it as new gaps show up.
  static const List<String> _knownDishFormats = [
    'frittata',
    'omelette',
    'omelet',
    'scramble',
    'quiche',
    'souffle',
    'soufflé',
    'bake',
    'casserole',
    'gratin',
    'tart',
    'pie',
    'hash',
    'skillet',
    'stir-fry',
    'stir fry',
    'sauté',
    'saute',
    'curry',
    'soup',
    'stew',
    'chowder',
    'chili',
    'salad',
    'bowl',
    'wrap',
    'pasta',
    'risotto',
    'pilaf',
    'paella',
    'gnocchi',
    'dumpling',
    'pizza',
    'flatbread',
    'fritters',
    'patties',
    'burger',
    'skewers',
    'kebab',
    'roast',
    'traybake',
    'sheet pan',
    'sheet-pan',
    'one-pot',
    'one pot',
  ];

  /// Scans [titles] for known dish-format keywords (case-insensitive
  /// substring match) and returns the distinct formats found, in the order
  /// first encountered.
  List<String> _extractDishFormats(List<String> titles) {
    final found = <String>[];
    for (final title in titles) {
      final lower = title.toLowerCase();
      for (final format in _knownDishFormats) {
        if (lower.contains(format) && !found.contains(format)) {
          found.add(format);
        }
      }
    }
    return found;
  }

  /// Asks Chef Harris for SOS help.
  ///
  /// - [userQuery] is the user's immediate cooking problem/question.
  /// - [recipeTitle] optionally provides context to keep answers specific.
  /// - If [forceJsonObject] is true, the OpenAI proxy is asked to return a strict JSON object.
  ///   (Callers should still validate/parse defensively.)
  /// - [recentDishTitles] is an optional list of recently generated dish
  ///   titles (most recent first, from any source — persisted cook history
  ///   and/or this app session's [RecentGenerationsService]) to steer the AI
  ///   away from repeating the same handful of dishes (CLAUDE.md roadmap
  ///   item 13). Only the most recent [_maxRecentDishExclusions] (after
  ///   case-insensitive dedupe) are actually sent.
  /// - [excludeDishFormats]: when true (default), also extracts known
  ///   dish-format keywords (frittata, bake, stir-fry, etc.) from
  ///   [recentDishTitles] and explicitly forbids reusing those formats, not
  ///   just the literal titles — this is what actually stops the model from
  ///   dodging exclusion by renaming the same dish. Pass false for surfaces
  ///   where the user may have explicitly typed a format by name (Custom AI
  ///   Recipe Creator) — format-excluding "frittata" would fight a user who
  ///   typed "frittata" themselves.
  /// - [recipeContext]: the actual recipe the user is cooking (ingredients
  ///   with amounts/units, every step's title/heat/duration/bullets, and a
  ///   marker on the step the user is currently on), pre-formatted by the
  ///   caller. When present, the answer must stay consistent with this
  ///   text as written rather than improvising a different preparation.
  ///   Previously SOS only received [recipeTitle] — a bare dish name — so
  ///   Chef Harris had no way to ground an answer in what the recipe
  ///   actually says.
  /// - [conversationHistory]: prior turns in this SOS session (chronological
  ///   order, oldest first), so a follow-up question has continuity instead
  ///   of every send being stateless. Only the most recent
  ///   [_maxSosHistoryMessages] are actually sent — see that constant's doc
  ///   comment for why it's capped.
  Future<String> askChefHarris({
    required String userQuery,
    String? recipeTitle,
    UserProfile? profile,
    bool forceJsonObject = false,
    List<String>? recentDishTitles,
    bool excludeDishFormats = true,
    String? recipeContext,
    List<({bool isUser, String text})>? conversationHistory,
  }) async {
    final query = userQuery.trim();
    if (query.isEmpty) {
      return 'Tell me what’s happening in the pan and I’ll jump in. Happy cooking! — Chef Harris';
    }

    final userMessage = StringBuffer();

    final name = (profile?.displayName ?? '').trim();
    final diet = profile?.diet.name;
    final allergies = (profile?.allergies ?? const <String>[])
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
    final confidence = profile?.kitchenConfidence.name;
    final servings = profile?.householdServings;

    if (name.isNotEmpty ||
        allergies.isNotEmpty ||
        diet != null ||
        confidence != null ||
        servings != null) {
      userMessage.writeln('User profile context (local):');
      if (name.isNotEmpty) userMessage.writeln('- Name to address: $name');
      if (diet != null) userMessage.writeln('- Diet baseline: $diet');
      if (confidence != null) {
        userMessage.writeln('- Kitchen confidence: $confidence');
        userMessage.writeln(
            'Instruction: Generate a recipe whose difficulty matches this confidence level per the RECIPE DIFFICULTY BY KITCHEN CONFIDENCE rules above. Treat this as a hard constraint, not flavor text.');
      }
      if (servings != null) {
        userMessage.writeln('- Household servings: $servings');
      }
      if (allergies.isNotEmpty) {
        userMessage.writeln(
            '- Allergies/intolerances to avoid: ${allergies.join(', ')}');
        userMessage.writeln(
            'Safety rule: Do not suggest ingredients containing these allergens. Offer substitutions by supermarket tier (budget/discount, mainstream, or premium/specialty) rather than naming specific store brands, since availability varies by region.');
      }
      userMessage.writeln();
    }

    if (recipeTitle != null && recipeTitle.trim().isNotEmpty) {
      userMessage.writeln('Recipe context: $recipeTitle');
      userMessage.writeln();
    }

    if (recipeContext != null && recipeContext.trim().isNotEmpty) {
      userMessage.writeln(
          'THE ACTUAL RECIPE (as written — this is what the user is cooking right now):');
      userMessage.writeln(recipeContext.trim());
      userMessage.writeln();
      userMessage.writeln(
        'Consistency rule: your answer must stay consistent with the recipe above as written. '
        'If the user\'s concern is valid, explain how to adapt what the recipe actually says — '
        'the ingredients, cuts, and steps given above — do not substitute a different preparation, '
        'ingredient prep, or technique that isn\'t in the recipe.',
      );
      userMessage.writeln();
    }

    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      final capped = conversationHistory.length > _maxSosHistoryMessages
          ? conversationHistory
              .sublist(conversationHistory.length - _maxSosHistoryMessages)
          : conversationHistory;
      if (capped.isNotEmpty) {
        userMessage
            .writeln('Conversation so far in this SOS session (oldest first):');
        for (final turn in capped) {
          userMessage
              .writeln('${turn.isUser ? 'User' : 'Chef Harris'}: ${turn.text}');
        }
        userMessage.writeln();
      }
    }

    userMessage.writeln('User SOS: $query');
    userMessage.writeln();
    if (name.isNotEmpty) {
      userMessage.writeln(
          'Address the user as "$name" naturally (not in every sentence).');
    }
    userMessage.writeln('Reply with concise, actionable steps.');
    if (!forceJsonObject) {
      // Defensive: the system persona includes JSON-structured recipe rules.
      // For conversational/SOS/suggestion calls, explicitly forbid JSON.
      userMessage.writeln(
        'Respond in plain, friendly conversational prose only — do NOT return JSON, code fences, or field-labeled output, even if this looks like a recipe request.',
      );
      userMessage.writeln('End with: Happy cooking! — Chef Harris');
    }

    // Bucket B: pull in only the curriculum drawers relevant to this
    // specific request (technique, topic, ingredient, pairing, cuisine).
    final curriculumAddendum =
        _buildCurriculumAddendum('${recipeTitle ?? ''} $query');
    if (curriculumAddendum.isNotEmpty) {
      userMessage.writeln(curriculumAddendum);
    }

    // Recipe variety (CLAUDE.md roadmap item 13): steer away from the same
    // handful of dishes (frittata, stir-fry, etc.) recurring regardless of
    // actual ingredients, by naming what's already been cooked/suggested
    // recently and asking for genuine variety against that list.
    final seenLower = <String>{};
    final recentTitles = <String>[];
    for (final raw in (recentDishTitles ?? const <String>[])) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (!seenLower.add(trimmed.toLowerCase())) {
        continue; // case-insensitive dedupe across merged sources
      }
      recentTitles.add(trimmed);
      if (recentTitles.length >= _maxRecentDishExclusions) break;
    }
    if (recentTitles.isNotEmpty) {
      userMessage.writeln(
        'Recently suggested/cooked dishes — do NOT repeat any of these, and avoid close variants '
        'of them (same dish renamed, or the same protein+method combo with a different garnish). '
        'Genuinely vary cuisine, main technique, or ingredient treatment instead: ${recentTitles.join(', ')}.',
      );
      userMessage.writeln();
    }

    // Format-level exclusion: title matching alone can't stop the model
    // renaming the same dish concept (frittata -> hash -> bake -> skillet)
    // to dodge the literal check above. See _knownDishFormats doc comment.
    final recentFormats = excludeDishFormats
        ? _extractDishFormats(recentTitles)
        : const <String>[];
    if (recentFormats.isNotEmpty) {
      userMessage.writeln(
        'Also avoid these dish formats/styles already used recently, regardless of what you name the '
        'dish: ${recentFormats.join(', ')}. Pick a genuinely different format or cooking style — '
        'not another dish in one of these formats under a new name.',
      );
      userMessage.writeln();
    }

    debugPrint(
      'ChefService.askChefHarris variety: excluding ${recentTitles.length} recent dish title(s) from this '
      'prompt: $recentTitles | excluding ${recentFormats.length} dish format(s): $recentFormats '
      '(excludeDishFormats=$excludeDishFormats)',
    );

    const systemPrompt =
        '$_systemPersona\n\n$_curriculumCore\n\n$_recipeDifficultyByKitchenConfidence';
    final userMessageStr = userMessage.toString();
    final Map<String, dynamic> payload = {
      'systemPrompt': systemPrompt,
      'userMessage': userMessageStr,
      'temperature': forceJsonObject ? 0.25 : 0.6,
      'forceJsonObject': forceJsonObject,
    };

    debugPrint(
      'ChefService.askChefHarris payload size: systemPrompt=${systemPrompt.length} chars, '
      'userMessage=${userMessageStr.length} chars (curriculumAddendum=${curriculumAddendum.length} chars), '
      'total=${systemPrompt.length + userMessageStr.length} chars (~${((systemPrompt.length + userMessageStr.length) / 4).round()} tokens est.)',
    );

    try {
      final res = await Supabase.instance.client.functions
          .invoke('ask-chef-harris', body: payload);
      final data = res.data;

      String? content;
      Map? usage;
      String? model;
      if (data is Map) {
        content = data['content']?.toString();
        usage = data['usage'] is Map ? data['usage'] as Map : null;
        model = data['model']?.toString();
      } else if (data is String) {
        content = data;
      }

      _logEstimatedCost(
          usage: usage,
          model: model,
          fallbackInputChars: systemPrompt.length + userMessageStr.length);

      final text = (content ?? '').trim();
      if (text.isEmpty) {
        debugPrint('ChefService: Empty response content. Raw: $data');
        return 'Give me 10 seconds and ask again — I didn\'t get a clear signal. Happy cooking! — Chef Harris';
      }
      return text;
    } catch (e) {
      debugPrint('ChefService: request failed: $e');
      return 'Something went wrong reaching the chef line. Try again in a moment. Happy cooking! — Chef Harris';
    }
  }

  /// Single named source for OpenAI pricing (USD per 1M tokens) on the
  /// Dart/client side. Mirrors `OPENAI_PRICING_PER_MILLION_TOKENS` in
  /// `supabase/functions/ask-chef-harris/index.ts` — Dart and Deno can't
  /// share a literal file, so this is a duplicate by necessity; update both
  /// (numbers AND the "rates checked" date) together. This copy only drives
  /// the client-side fallback estimate below (used when a response is
  /// missing `usage`, e.g. a stale pre-deploy edge function) — the durable,
  /// authoritative cost record is written server-side into
  /// `api_call_cost_log` by the edge function's own copy of these rates.
  /// Rates checked 2026-08-13 against OpenAI's published pricing.
  static const Map<String, ({double input, double output})>
      _openAiPricingPerMillionTokens = {
    'gpt-4o': (input: 2.50, output: 10.00),
    'gpt-4o-mini': (input: 0.15, output: 0.60),
  };

  /// Logs an estimated USD cost for the call just completed. Prefers real
  /// token counts from OpenAI's `usage` field (now forwarded by the
  /// `ask-chef-harris` edge function); falls back to a char/4 estimate
  /// (input only — no way to know output length without `usage`) if the
  /// deployed edge function version doesn't include it yet.
  void _logEstimatedCost(
      {required Map? usage,
      required String? model,
      required int fallbackInputChars}) {
    final resolvedModel = (model == 'gpt-4o-mini') ? 'gpt-4o-mini' : 'gpt-4o';
    final rates = _openAiPricingPerMillionTokens[resolvedModel] ??
        _openAiPricingPerMillionTokens['gpt-4o']!;
    final inputPerM = rates.input;
    final outputPerM = rates.output;

    if (usage != null) {
      final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
      final completionTokens =
          (usage['completion_tokens'] as num?)?.toInt() ?? 0;
      final costUsd = (promptTokens / 1000000) * inputPerM +
          (completionTokens / 1000000) * outputPerM;
      debugPrint(
        'ChefService.askChefHarris cost: model=$resolvedModel prompt_tokens=$promptTokens '
        'completion_tokens=$completionTokens est_cost_usd=\$${costUsd.toStringAsFixed(5)} (real token counts)',
      );
    } else {
      final estInputTokens = (fallbackInputChars / 4).round();
      final costUsd = (estInputTokens / 1000000) * inputPerM;
      debugPrint(
        'ChefService.askChefHarris cost: model=$resolvedModel est_input_tokens=$estInputTokens '
        'est_cost_usd=\$${costUsd.toStringAsFixed(5)} (INPUT ONLY, char-count estimate — deployed edge '
        'function does not yet return usage; redeploy ask-chef-harris to get accurate cost including output)',
      );
    }
  }
}
