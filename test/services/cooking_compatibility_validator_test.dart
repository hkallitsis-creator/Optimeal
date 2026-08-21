import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/data/cooking_times.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/compatibility_flag_log.dart';
import 'package:optimeal/services/cooking_compatibility_validator.dart';
import 'package:optimeal/services/validated_recipe_generation.dart';

/// The compatibility validator, the correction/retry loop and the flag log.
///
/// The worked example the signed table itself gives is potato at 2cm dice (B4)
/// with spinach (B1) — three bands apart — and it shows up here as the
/// canonical violation.
void main() {
  CookModeRecipePayload recipeWith({
    required List<(String name, String? key)> ingredients,
    required List<(String title, int minutes, List<String> added)> steps,
    List<String>? heats,
  }) {
    return CookModeRecipePayload(
      title: 'Test dish',
      ingredients: [for (final i in ingredients) i.$1],
      structuredIngredients: [
        for (final i in ingredients)
          RecipeIngredient(name: i.$1, amount: 100, unit: 'g', cookingTimesKey: i.$2),
      ],
      steps: [
        for (var i = 0; i < steps.length; i++)
          CookModeStepPayload(
            title: steps[i].$1,
            heat: heats == null ? 'medium' : heats[i],
            durationMinutes: steps[i].$2,
            bullets: const ['do the thing'],
            ingredientsAdded: steps[i].$3,
          ),
      ],
    );
  }

  group('rule 3 — one-band tolerance within a step', () {
    test("the doc's worked example flags: potato 2cm dice B4 with spinach B1", () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Cook it all', 12, ['potato', 'spinach'])],
      ));

      final spread = report.flags
          .where((f) => f.kind == CompatibilityFlagKind.bandSpread)
          .toList();
      expect(spread, hasLength(1));
      expect(spread.single.slowKey, 'potato_waxy_2cm_dice');
      expect(spread.single.fastKey, 'spinach_whole_leaf');
      expect(spread.single.slowBand, CookBand.b4);
      expect(spread.single.fastBand, CookBand.b1);
      expect(spread.single.bandDelta, 3);
      expect(report.isClean, isFalse);
    });

    test('same band passes', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('courgette', 'courgette_1cm_slice'),
          ('spring onion', 'spring_onion_1cm_slice'),
        ],
        steps: [('Sauté', 4, ['courgette', 'spring onion'])],
      ));
      expect(report.flags.where((f) => f.kind == CompatibilityFlagKind.bandSpread),
          isEmpty);
    });

    test('EXACTLY one band apart passes — the tolerance edge', () {
      // Assembled from the table rather than asserted blind, so this stays a
      // test of the tolerance and not of two particular rows.
      final pair = _pairExactlyOneBandApart();
      expect(pair, isNotNull, reason: 'the table must contain such a pair');

      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('a', pair!.$1), ('b', pair.$2)],
        steps: [('Together', 20, ['a', 'b'])],
      ));
      expect(
        report.flags.where((f) => f.kind == CompatibilityFlagKind.bandSpread),
        isEmpty,
        reason: '${pair.$1} and ${pair.$2} are one band apart and may go in together',
      );
    });

    test('exactly two bands apart flags — one past the edge', () {
      final pair = _pairExactlyTwoBandsApart();
      expect(pair, isNotNull);

      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('a', pair!.$1), ('b', pair.$2)],
        steps: [('Together', 20, ['a', 'b'])],
      ));
      expect(
        report.flags.where((f) => f.kind == CompatibilityFlagKind.bandSpread).single.bandDelta,
        2,
      );
    });

    test('ingredients in DIFFERENT steps are never compared', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [
          ('Potato first', 12, ['potato']),
          ('Spinach at the end', 1, ['spinach']),
        ],
      ));
      expect(report.isClean, isTrue,
          reason: 'a staggered add is the fix the paper asks for, not a violation');
    });

    test('a dual-band row passes if either of its bands is compatible', () {
      // lamb is B3 pan-fried / B6 braised. Against a B4 it is compatible in
      // its B3 reading, so the permissive (fail-open) result is no flag.
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('lamb', 'lamb_diced_2cm_dice'),
          ('potato', 'potato_waxy_2cm_dice'),
        ],
        steps: [('Brown together', 10, ['lamb', 'potato'])],
      ));
      expect(report.flags.where((f) => f.kind == CompatibilityFlagKind.bandSpread),
          isEmpty);
    });
  });

  group('rule 4 — stated duration against the band', () {
    test('an ingredient added early is credited with every heated step after it', () {
      // Real dev output: stewing beef (B6) browned for 10 minutes and then
      // simmered for 90. The browning step alone is B4; the beef's actual
      // cook time is 100 minutes, so there is nothing wrong here.
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('beef', 'beef_stewing_3cm_dice')],
        steps: [
          ('Brown the beef', 10, ['beef']),
          ('Simmer', 90, <String>[]),
        ],
      ));
      expect(report.flags, isEmpty);
    });

    test('an off-heat step is never checked — nothing is cooking in it', () {
      // Also real dev output: four ingredients listed against a chopping step.
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Prepare ingredients', 10, ['potato', 'spinach'])],
        heats: const ['off_heat'],
      ));
      expect(report.isClean, isTrue);
      expect(report.stepsChecked, 0);
    });

    test('an unrecognised heat value is treated as heated, not skipped', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Cook it all', 12, ['potato', 'spinach'])],
        heats: const ['scorching'],
      ));
      expect(report.flags, isNotEmpty);
    });

    test('off-heat minutes do not count as cooking time', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('beef', 'beef_stewing_3cm_dice')],
        steps: [
          ('Sear', 4, ['beef']),
          ('Rest on the board', 200, <String>[]),
        ],
        heats: const ['medium_high', 'off_heat'],
      ));
      expect(
        report.flags.where((f) => f.kind == CompatibilityFlagKind.durationTooShort),
        hasLength(1),
        reason: 'resting is not cooking',
      );
    });

    test('a step far shorter than its ingredient needs is flagged', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('beef', 'beef_stewing_3cm_dice')],
        steps: [('Simmer briefly', 4, ['beef'])],
      ));
      final duration = report.flags
          .where((f) => f.kind == CompatibilityFlagKind.durationTooShort)
          .toList();
      expect(duration, hasLength(1));
      expect(duration.single.slowKey, 'beef_stewing_3cm_dice');
      expect(duration.single.stepMinutes, 4);
    });

    test('a duration one band off is inside tolerance', () {
      // carrot_1cm_dice is B4 (10-15 min); a step stated at 8 min is B3, one
      // band below, which the signed tolerance allows.
      expect(CookingTimes.resolveBands('carrot_1cm_dice').single, CookBand.b4);
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('carrot', 'carrot_1cm_dice')],
        steps: [('Sauté', 8, ['carrot'])],
      ));
      expect(report.flags, isEmpty);
    });

    test('package-instruction rows are band-checked but never duration-flagged', () {
      for (final key in ['dried_pasta', 'white_rice_absorption', 'brown_rice_absorption']) {
        expect(CookingTimes.hasAdvisoryMinutes(key), isTrue, reason: key);

        // A deliberately absurd duration on an advisory row: no duration flag.
        final duration = validateCookingCompatibility(recipeWith(
          ingredients: [('starch', key)],
          steps: [('Cook', 1, ['starch'])],
        ));
        expect(
          duration.flags.where((f) => f.kind == CompatibilityFlagKind.durationTooShort),
          isEmpty,
          reason: '$key minutes are advisory — the packet governs',
        );

        // ...but its BAND still stands and is still compared to a co-cooker.
        final spread = validateCookingCompatibility(recipeWith(
          ingredients: [('starch', key), ('spinach', 'spinach_whole_leaf')],
          steps: [('Together', 10, ['starch', 'spinach'])],
        ));
        expect(
          spread.flags.where((f) => f.kind == CompatibilityFlagKind.bandSpread),
          isNotEmpty,
          reason: '$key still has a band, and a B6 brown rice still needs a head start',
        );
      }
    });

    test('red lentils is skipped by every timing check, both kinds', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('red lentils', 'red_lentils_simmer'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Together for one minute', 1, ['red lentils', 'spinach'])],
      ));
      expect(report.isClean, isTrue,
          reason: 'no figure exists for this row, so nothing may be concluded from it');
      expect(report.ingredientsSkipped, 1);
      expect(report.ingredientsResolved, 1);
    });
  });

  group('fail-open by construction', () {
    test('an unknown declared key produces no flag and is counted as skipped', () {
      final report = validateCookingCompatibility(
        recipeWith(
          ingredients: [('mystery', null), ('spinach', 'spinach_whole_leaf')],
          steps: [('Together', 1, ['mystery', 'spinach'])],
        ),
        unknownKeys: ['potato_2cm'],
      );
      expect(report.isClean, isTrue);
      expect(report.ingredientsSkipped, 1);
      expect(report.unknownKeys, ['potato_2cm']);
    });

    test('no declared keys anywhere means no checks at all', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('potato', null), ('spinach', null)],
        steps: [('Together', 1, ['potato', 'spinach'])],
      ));
      expect(report.isClean, isTrue);
      expect(report.stepsChecked, 0);
    });

    test('a recipe with no structured ingredients is not checked', () {
      final report = validateCookingCompatibility(const CookModeRecipePayload(
        title: 'Legacy',
        ingredients: ['a', 'b'],
        steps: [],
      ));
      expect(report.isClean, isTrue);
    });

    test('an ingredient named in a step but absent from the list is skipped', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [('potato', 'potato_waxy_2cm_dice')],
        steps: [('Together', 12, ['potato', 'something never listed'])],
      ));
      expect(report.flags.where((f) => f.kind == CompatibilityFlagKind.bandSpread),
          isEmpty);
    });
  });

  group('reading the declared key', () {
    Future<CookModeRecipePayload?> parse(String ingredientJson, List<String> sink) =>
        _parse(
          '{"title":"T","ingredients":[$ingredientJson],'
          '"steps":[{"title":"S","duration_minutes":5,"heat":"medium",'
          '"ingredients_added":["x"],"bullets":["b"]}]}',
          sink,
        );

    test('a valid key is kept', () async {
      final r = await parse(
          '{"name":"x","amount":1,"unit":"g","cooking_times_key":"carrot_1cm_dice"}',
          []);
      expect(r!.structuredIngredients!.single.cookingTimesKey, 'carrot_1cm_dice');
    });

    test('"none" is absence, not a miss — the model copies that convention', () async {
      final sink = <String>[];
      final r = await parse(
          '{"name":"x","amount":1,"unit":"g","cooking_times_key":"none"}', sink);
      expect(r!.structuredIngredients!.single.cookingTimesKey, isNull);
      expect(sink, isEmpty, reason: '"none" must not be logged as a rejected key');
    });

    test('an absent field is silent', () async {
      final sink = <String>[];
      final r = await parse('{"name":"x","amount":1,"unit":"g"}', sink);
      expect(r!.structuredIngredients!.single.cookingTimesKey, isNull);
      expect(sink, isEmpty);
    });

    test('a key outside the closed list is dropped and counted', () async {
      final sink = <String>[];
      final r = await parse(
          '{"name":"x","amount":1,"unit":"g","cooking_times_key":"potato_3cm_dice"}',
          sink);
      expect(r!.structuredIngredients!.single.cookingTimesKey, isNull);
      expect(sink, ['potato_3cm_dice']);
    });

    test('the key survives a jsonb round trip', () {
      final ing = RecipeIngredient(
          name: 'carrot', amount: 100, unit: 'g', cookingTimesKey: 'carrot_1cm_dice');
      expect(RecipeIngredient.fromJson(ing.toJson()).cookingTimesKey,
          'carrot_1cm_dice');
      expect(ing.scaled(2).cookingTimesKey, 'carrot_1cm_dice');
    });
  });

  group('the correction note', () {
    test('names the violating pair, both bands, and both remedies', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Cook it all', 12, ['potato', 'spinach'])],
      ));
      final note = report.buildCorrectionNote();

      expect(note, contains('potato_waxy_2cm_dice'));
      expect(note, contains('spinach_whole_leaf'));
      expect(note, contains('B4'));
      expect(note, contains('B1'));
      expect(note, contains('head start'),
          reason: "the paper's first remedy: stagger the add");
      expect(note, contains('cut it smaller'),
          reason: "the paper's second remedy: bring the cuts closer");
      expect(note.toLowerCase(), contains('correction required'));
    });

    test('is empty on a clean report', () {
      expect(const CompatibilityReport.clean().buildCorrectionNote(), isEmpty);
    });

    test('names every violating step, not just the first', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
          ('rice', 'brown_rice_absorption'),
          ('rocket', 'rocket_whole_leaf'),
        ],
        steps: [
          ('One', 12, ['potato', 'spinach']),
          ('Two', 30, ['rice', 'rocket']),
        ],
      ));
      expect(report.buildCorrectionNote(), contains('Step 1'));
      expect(report.buildCorrectionNote(), contains('Step 2'));
    });
  });

  group('the flag is machine-readable', () {
    test('serialises to flat primitives with everything a fix would need', () {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Cook it all', 12, ['potato', 'spinach'])],
      ));
      final json = report.flags
          .firstWhere((f) => f.kind == CompatibilityFlagKind.bandSpread)
          .toJson();

      expect(json['kind'], 'bandSpread');
      expect(json['step_index'], 0);
      expect(json['step_title'], 'Cook it all');
      expect(json['slow_key'], 'potato_waxy_2cm_dice');
      expect(json['slow_band'], 'B4');
      expect(json['fast_key'], 'spinach_whole_leaf');
      expect(json['fast_band'], 'B1');
      expect(json['band_delta'], 3);

      // Must survive a round trip through the log's encoder untouched.
      expect(jsonDecode(jsonEncode(json)), json);
    });
  });

  group('the retry loop', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    const violating = '''
{"title":"Bad","ingredients":[
 {"name":"potato","amount":300,"unit":"g","cooking_times_key":"potato_waxy_2cm_dice"},
 {"name":"spinach","amount":100,"unit":"g","cooking_times_key":"spinach_whole_leaf"}],
 "steps":[{"title":"Cook it all","duration_minutes":12,"heat":"medium",
 "ingredients_added":["potato","spinach"],"bullets":["everything in"]}]}''';

    const clean = '''
{"title":"Good","ingredients":[
 {"name":"potato","amount":300,"unit":"g","cooking_times_key":"potato_waxy_2cm_dice"},
 {"name":"spinach","amount":100,"unit":"g","cooking_times_key":"spinach_whole_leaf"}],
 "steps":[
 {"title":"Potato first","duration_minutes":12,"heat":"medium",
  "ingredients_added":["potato"],"bullets":["head start"]},
 {"title":"Spinach last","duration_minutes":1,"heat":"medium",
  "ingredients_added":["spinach"],"bullets":["wilt it"]}]}''';

    Future<ValidatedRecipeResult> run(
      List<String?> replies, {
      List<String?>? notesSink,
      List<bool>? retryFlagsSink,
    }) {
      var call = 0;
      return generateValidatedRecipe(
        logSurface: 'test_surface',
        attempt: ({String? correctionNote, required bool isRetry}) async {
          notesSink?.add(correctionNote);
          retryFlagsSink?.add(isRetry);
          return replies[call++];
        },
        parse: (raw, unknownKeys) => _parse(raw, unknownKeys),
      );
    }

    test('a clean first attempt costs no retries', () async {
      final notes = <String?>[];
      final result = await run([clean], notesSink: notes);

      expect(result.recipe, isNotNull);
      expect(result.retriesUsed, 0);
      expect(result.servedWithFlags, isFalse);
      expect(notes, [null]);
    });

    test('a violation triggers a correction retry, and a fixed retry is served', () async {
      final notes = <String?>[];
      final retries = <bool>[];
      final result =
          await run([violating, clean], notesSink: notes, retryFlagsSink: retries);

      expect(result.recipe!.title, 'Good');
      expect(result.retriesUsed, 1);
      expect(result.servedWithFlags, isFalse);

      expect(notes.first, isNull);
      expect(notes[1], contains('potato_waxy_2cm_dice'));
      expect(notes[1], contains('CORRECTION REQUIRED'));
      expect(retries, [false, true],
          reason: 'the retry must bill to its own cost surface');
    });

    test('retries are capped at two, then the flagged recipe is served anyway', () async {
      final retries = <bool>[];
      final result = await run(
        [violating, violating, violating, violating],
        retryFlagsSink: retries,
      );

      expect(retries, [false, true, true],
          reason: 'exactly three calls: the original plus two corrections');
      expect(result.retriesUsed, kMaxCompatibilityRetries);
      expect(result.recipe, isNotNull, reason: 'fail-open — the user still gets a recipe');
      expect(result.servedWithFlags, isTrue);
      expect(result.report.flags, isNotEmpty);
    });

    test('a retry that fails to generate never costs us the recipe we had', () async {
      final result = await run([violating, null]);

      expect(result.recipe, isNotNull);
      expect(result.recipe!.title, 'Bad');
      expect(result.servedWithFlags, isTrue);
    });

    test('a retry that fails to parse never costs us the recipe we had', () async {
      final result = await run([violating, 'not json at all']);

      expect(result.recipe, isNotNull);
      expect(result.servedWithFlags, isTrue);
    });

    test('a first attempt that produces nothing is a generation failure, not a flag', () async {
      final result = await run([null]);

      expect(result.recipe, isNull);
      expect(result.retriesUsed, 0);
      expect(result.servedWithFlags, isFalse);
      expect(result.report.isClean, isTrue);
    });

    test('a worse correction is discarded in favour of the better earlier one', () async {
      const worse = '''
{"title":"Worse","ingredients":[
 {"name":"potato","amount":300,"unit":"g","cooking_times_key":"potato_waxy_2cm_dice"},
 {"name":"spinach","amount":100,"unit":"g","cooking_times_key":"spinach_whole_leaf"},
 {"name":"rice","amount":100,"unit":"g","cooking_times_key":"brown_rice_absorption"}],
 "steps":[{"title":"All in","duration_minutes":12,"heat":"medium",
 "ingredients_added":["potato","spinach","rice"],"bullets":["everything in"]}]}''';

      final result = await run([violating, worse, worse]);
      expect(result.recipe!.title, 'Bad');
    });
  });

  group('the flag log', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('records every generation, clean or not, so a rate can be computed', () async {
      await CompatibilityFlagLog.record(
        surface: 'fridge_clearer',
        report: const CompatibilityReport.clean(),
        retriesUsed: 0,
        servedWithFlags: false,
      );
      final entries = await CompatibilityFlagLog.read();

      expect(entries, hasLength(1));
      expect(entries.single['surface'], 'fridge_clearer');
      expect(entries.single['retries_used'], 0);
      expect(entries.single['served_with_flags'], isFalse);
      expect(entries.single['flags'], isEmpty);
      expect(DateTime.tryParse(entries.single['at'] as String), isNotNull);
    });

    test('a flagged entry carries the whole machine-readable flag', () async {
      final report = validateCookingCompatibility(recipeWith(
        ingredients: [
          ('potato', 'potato_waxy_2cm_dice'),
          ('spinach', 'spinach_whole_leaf'),
        ],
        steps: [('Cook it all', 12, ['potato', 'spinach'])],
      ));
      await CompatibilityFlagLog.record(
        surface: 'custom_creator',
        report: report,
        retriesUsed: 2,
        servedWithFlags: true,
      );

      final entry = (await CompatibilityFlagLog.read()).single;
      expect(entry['retries_used'], 2);
      expect(entry['served_with_flags'], isTrue);
      expect(entry['steps_checked'], 1);
      final flags = entry['flags'] as List;
      expect(flags.first['slow_key'], 'potato_waxy_2cm_dice');
      expect(flags.first['band_delta'], 3);
    });

    test('is newest first and bounded', () async {
      for (var i = 0; i < CompatibilityFlagLog.maxEntries + 5; i++) {
        await CompatibilityFlagLog.record(
          surface: 'surface_$i',
          report: const CompatibilityReport.clean(),
          retriesUsed: 0,
          servedWithFlags: false,
        );
      }
      final entries = await CompatibilityFlagLog.read();

      expect(entries, hasLength(CompatibilityFlagLog.maxEntries));
      expect(entries.first['surface'],
          'surface_${CompatibilityFlagLog.maxEntries + 4}');
    });

    test('a corrupt line costs only itself', () async {
      SharedPreferences.setMockInitialValues({
        CompatibilityFlagLog.storageKey: <String>['{not json', '{"surface":"ok"}'],
      });
      final entries = await CompatibilityFlagLog.read();

      expect(entries, hasLength(1));
      expect(entries.single['surface'], 'ok');
    });
  });
}

/// The real parser, wired exactly as both generation surfaces wire it.
Future<CookModeRecipePayload?> _parse(String raw, List<String> unknownKeys) =>
    parseChefRecipeJson(
      raw: raw,
      portions: 2,
      fallbackTitle: 'Test dish',
      surface: ChefRecipeSurface.fridgeClearer,
      useGenericFallbacks: false,
      unknownCookingTimesKeys: unknownKeys,
    );

/// Assembled from the live table so these stay tests of the tolerance rule,
/// not of two particular rows that could be re-cut on the paper later.
(String, String)? _pairExactlyOneBandApart() => _pairNBandsApart(1);
(String, String)? _pairExactlyTwoBandsApart() => _pairNBandsApart(2);

(String, String)? _pairNBandsApart(int n) {
  for (final a in CookingTimes.rows) {
    if (a.bands.length != 1) continue;
    for (final b in CookingTimes.rows) {
      if (b.bands.length != 1 || a.key == b.key) continue;
      if (a.bands.single.distanceTo(b.bands.single) == n) return (a.key, b.key);
    }
  }
  return null;
}
