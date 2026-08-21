/// The byte-identical halves of the two recipe-generation prompts.
///
/// These live here, outside the widgets that send them, for one reason: they
/// are the *cacheable prefix*. They must be assertable on their own — a test
/// has to be able to prove that nothing per-call has crept into them — and a
/// State class buried in a screen file cannot be reached from a test.
///
/// **Everything in this file must be genuinely static**: identical on every
/// call from that surface, for every user, forever. The moment a `$portions`
/// or an ingredient name appears in one of these strings, every token after
/// it stops being cacheable. Guideline lines that must embed a per-call value
/// stay in the callers' variable halves.
///
/// Sent via `ChefService.askChefHarris(staticPromptBlock: ...)`, never
/// concatenated into `userQuery` — see [ChefService.buildUserMessage] for
/// what that distinction is worth and how it was lost once already.
library;

import 'package:optimeal/data/cooking_times.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/services/chef_service.dart';

/// Fridge Clearer's schema, guidelines, and closed-vocabulary declarations.
String buildFridgeClearerStaticPrompt() {
  return [
      'Return ONLY valid JSON (no markdown, no extra text) matching this schema:',
      '{',
      '  "title": "...",',
      '  "description": "...",',
      '  "curriculum_lesson_id": "...",',
      '  "ingredients": [',
      '    {"name": "...", "amount": 0, "unit": "g|ml|tbsp|tsp|piece|clove|slice", "cut": "${ingredientCutVocabulary.join('|')}", "cooking_times_key": "..."}',
      '  ],',
      '  "kitchen_gear": ["..."],',
      '  "steps": [',
      '    {',
      '      "title": "...",',
      '      "duration_minutes": 0,',
      '      "heat": "low|medium|medium_high|off_heat",',
      '      "ingredients_added": ["..."],',
      '      "sensory_cue": "...",',
      '      "technique_diagram_id": "...",',
      '      "bullets": ["..."]',
      '    }',
      '  ]',
      '}',
      '',
      'Guidelines:',
      '- The "description" field must be exactly one short, appetizing sentence (max ~20 words) in Chef Harris\' witty, warm voice — describe what makes the dish worth cooking, not technique.',
      '- Steps must be actionable and short (so they fit Cook Mode cards).',
      '- Use 4–8 steps. Provide realistic durations (1–15 minutes each).',
      '- Heat should be one of the allowed values (default "medium").',
      '- Each ingredient\'s "cut" field must be exactly one of: ${ingredientCutVocabulary.join(', ')}. This is a closed set — do not write a free-text cut description in this field, and do not invent a value outside this list. Use "none" if the ingredient needs no cutting. Step bullets may still describe the cut in your own voice; the "cut" field is the structured record of it.',
      '- SEQUENCING RULE (non-negotiable): each step\'s "ingredients_added" field must list every ingredient that step actually adds to the pan/pot, using the exact "name" values from the ingredients list above. If the ingredients in "ingredients_added" do not have comparable cook times, you may not add them at the same moment. Either stagger them within the step — the bullets must state exactly what goes in first, how many minutes it cooks alone, and when each remaining ingredient joins — or split them across separate steps instead. WHAT NOT TO DO: do not write a step like "thinly slice potatoes and onions, then cook together" — thinly sliced onion softens in a few minutes while thinly sliced potato needs several minutes longer to cook through, so the onion will burn or turn bitter well before the potato is done. Instead, add the potato first and give it a real head start before the onion joins, or cook them as two separate steps.',
      '- The "curriculum_lesson_id" field is required and must name the ONE curriculum technique or topic this recipe actually teaches, chosen exactly from this list: ${ChefService.curriculumDrawerKeys.join(', ')}. Base the choice on what the steps physically do, not the dish\'s theme, name, or ingredients — a recipe built from fridge leftovers is not "food_storage" just because using up leftovers is this app\'s whole point; if the steps sauté something, the answer is "sauteing"; if they braise, it\'s "braising"; and so on. Choose the single best match for the technique actually demonstrated.',
      '- Each step\'s "sensory_cue" field is required and must be exactly one key from this closed list, or "no_cue" if genuinely nothing fits — never invent a value outside this list, and never leave the field out:\n${ChefService.sensoryCuePromptDeclaration}\nSelection rule: a "readiness" cue belongs on a step where something first enters a pan, oven, or pot. A "doneness" cue belongs on the step where cooking actually completes. A "during" cue is only for a step whose entire instruction IS heat management (e.g. "keep it at a steady sizzle") — not any step that merely happens to involve heat. WHAT NOT TO DO: do not declare "juices_run_clear" (a doneness cue) on a step that only says "season the chicken and set it aside" — nothing has finished cooking yet, so "no_cue" is correct there; save "juices_run_clear" for the step where the chicken actually finishes cooking through.',
      '- Each ingredient\'s "cooking_times_key" field names which row of the app\'s cooking-times reference that ingredient is, so the app can check your sequencing against it. Include it for every ingredient that is actually cooked; omit it entirely for anything with no row of its own (oil, salt, pepper, dried spices, stock, a herb used as garnish). When present it must be exactly one key from this closed list — never invent a key, never write a time or a number in this field, and never guess at a near match from a different ingredient:\n${CookingTimes.promptKeyList}\nPick the key whose cut matches what your recipe actually does: "potato_waxy_1cm_dice" and "potato_waxy_2cm_dice" are separate rows and the difference is the whole point of the field. If your cut has no matching row, choose the nearest row of the SAME ingredient rather than a closer cut of a different one.',
      '- Each step\'s "technique_diagram_id" field is optional — include it only when the step visually demonstrates one of these five techniques, using exactly one key, or "none"/omit otherwise. Most steps should have no value here:\n${ChefService.techniqueDiagramPromptDeclaration}',
  ].join('\n');
}

/// Custom AI Recipe Creator's schema, guidelines, and closed-vocabulary
/// declarations. Deliberately a separate list from the Fridge Clearer one
/// even though they overlap heavily — the two prompts have diverged before
/// (this one has no "description" field and different step-count guidance)
/// and merging them would couple two surfaces that are free to differ.
String buildCustomCreatorStaticPrompt() {
  return [
      'Return ONLY valid JSON (no markdown, no extra text) matching this schema:',
      '{',
      '  "title": "...",',
      '  "curriculum_lesson_id": "...",',
      '  "ingredients": [',
      '    {"name": "...", "amount": 0, "unit": "g|ml|tbsp|tsp|piece|clove|slice", "cut": "${ingredientCutVocabulary.join('|')}", "cooking_times_key": "..."}',
      '  ],',
      '  "kitchen_gear": ["..."],',
      '  "steps": [',
      '    {',
      '      "title": "...",',
      '      "duration_minutes": 0,',
      '      "heat": "low|medium|medium_high|off_heat",',
      '      "ingredients_added": ["..."],',
      '      "sensory_cue": "...",',
      '      "technique_diagram_id": "...",',
      '      "bullets": ["..."]',
      '    }',
      '  ]',
      '}',
      '',
      'Guidelines:',
      '- Use 4–9 steps. Each step duration 1–15 minutes.',
      '- Heat must be one of the allowed values (default "medium").',
      '- Each ingredient\'s "cut" field must be exactly one of: ${ingredientCutVocabulary.join(', ')}. This is a closed set — do not write a free-text cut description in this field, and do not invent a value outside this list. Use "none" if the ingredient needs no cutting. Step bullets may still describe the cut in your own voice; the "cut" field is the structured record of it.',
      '- SEQUENCING RULE (non-negotiable): each step\'s "ingredients_added" field must list every ingredient that step actually adds to the pan/pot, using the exact "name" values from the ingredients list above. If the ingredients in "ingredients_added" do not have comparable cook times, you may not add them at the same moment. Either stagger them within the step — the bullets must state exactly what goes in first, how many minutes it cooks alone, and when each remaining ingredient joins — or split them across separate steps instead. WHAT NOT TO DO: do not write a step like "thinly slice potatoes and onions, then cook together" — thinly sliced onion softens in a few minutes while thinly sliced potato needs several minutes longer to cook through, so the onion will burn or turn bitter well before the potato is done. Instead, add the potato first and give it a real head start before the onion joins, or cook them as two separate steps.',
      '- The "curriculum_lesson_id" field is required and must name the ONE curriculum technique or topic this recipe actually teaches, chosen exactly from this list: ${ChefService.curriculumDrawerKeys.join(', ')}. Base the choice on what the steps physically do, not the dish\'s theme, name, or ingredients — a recipe built from fridge leftovers is not "food_storage" just because using up leftovers is this app\'s whole point; if the steps sauté something, the answer is "sauteing"; if they braise, it\'s "braising"; and so on. Choose the single best match for the technique actually demonstrated.',
      '- Each step\'s "sensory_cue" field is required and must be exactly one key from this closed list, or "no_cue" if genuinely nothing fits — never invent a value outside this list, and never leave the field out:\n${ChefService.sensoryCuePromptDeclaration}\nSelection rule: a "readiness" cue belongs on a step where something first enters a pan, oven, or pot. A "doneness" cue belongs on the step where cooking actually completes. A "during" cue is only for a step whose entire instruction IS heat management (e.g. "keep it at a steady sizzle") — not any step that merely happens to involve heat. WHAT NOT TO DO: do not declare "juices_run_clear" (a doneness cue) on a step that only says "season the chicken and set it aside" — nothing has finished cooking yet, so "no_cue" is correct there; save "juices_run_clear" for the step where the chicken actually finishes cooking through.',
      '- Each ingredient\'s "cooking_times_key" field names which row of the app\'s cooking-times reference that ingredient is, so the app can check your sequencing against it. Include it for every ingredient that is actually cooked; omit it entirely for anything with no row of its own (oil, salt, pepper, dried spices, stock, a herb used as garnish). When present it must be exactly one key from this closed list — never invent a key, never write a time or a number in this field, and never guess at a near match from a different ingredient:\n${CookingTimes.promptKeyList}\nPick the key whose cut matches what your recipe actually does: "potato_waxy_1cm_dice" and "potato_waxy_2cm_dice" are separate rows and the difference is the whole point of the field. If your cut has no matching row, choose the nearest row of the SAME ingredient rather than a closer cut of a different one.',
      '- Each step\'s "technique_diagram_id" field is optional — include it only when the step visually demonstrates one of these five techniques, using exactly one key, or "none"/omit otherwise. Most steps should have no value here:\n${ChefService.techniqueDiagramPromptDeclaration}',
  ].join('\n');
}

/// Stage 1 of the two-stage Fridge Clearer flow: a **menu**, not meals.
///
/// Deliberately tiny next to [buildFridgeClearerStaticPrompt]. That is the
/// whole economic argument for splitting the flow — this call has to come back
/// fast enough that three choices feel cheaper than one guess, so it asks for
/// no steps, no quantities, no cuts, no vocabulary declarations, and no
/// curriculum key. Everything the full recipe needs is asked for once, later,
/// for the one idea the user actually chose.
///
/// Static in the strict sense this file requires: identical on every stage-1
/// call, for every user, forever. The ingredients, time box, gear and portions
/// all travel in the caller's variable half, which lands after this block —
/// see `ChefService.buildUserMessage`.
///
/// `ingredients_left` is requested even though the app computes clearance
/// itself and never reads that field. It is there to force the model to
/// partition the user's list rather than casually over-claiming in
/// `ingredients_cleared`; the app's arithmetic is what reaches the screen.
String buildFridgeIdeasStaticPrompt() {
  return [
    'Return ONLY valid JSON (no markdown, no extra text) matching this schema:',
    '{',
    '  "ideas": [',
    '    {',
    '      "title": "...",',
    '      "total_time_minutes": 0,',
    '      "ingredients_cleared": ["..."],',
    '      "ingredients_left": ["..."]',
    '    }',
    '  ]',
    '}',
    '',
    'Guidelines:',
    '- Return EXACTLY three ideas. Each is a one-line menu suggestion, not a recipe: no steps, no quantities, no method description.',
    '- "title" is the dish, in plain appetising words a home cook would recognise. Keep it under 6 words.',
    '- "total_time_minutes" is the whole thing start to finish, including prep.',
    '- "ingredients_cleared" must list ONLY ingredients the user actually gave you, copied in their words, and only the ones this dish genuinely uses in a meaningful quantity. Do not pad it. A garnish-sized pinch does not clear an ingredient.',
    '- "ingredients_left" must list every ingredient the user gave you that this dish does NOT use. Together the two lists must account for the user\'s whole list exactly once.',
    '- Do not add ingredients the user did not list, beyond assumed pantry staples (oil, salt, pepper, common dried spices, pasta/rice/flour).',
    '- Make the three genuinely different from each other — different technique or different shape of meal, not three names for the same dish. At least one should aim to use everything the user has.',
  ].join('\n');
}
