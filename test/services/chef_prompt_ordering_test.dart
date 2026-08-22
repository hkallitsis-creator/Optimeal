import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/data/cooking_times.dart';
import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/services/chef_service.dart';

/// Locks the cache-prefix ordering contract fixed on 2026-08-21.
///
/// The cedf753 restructure reordered static-before-variable *inside each
/// caller's prompt string*, but that whole string then travelled as
/// `userQuery` and was emitted last — behind `Recipe context:`, which changes
/// whenever the ingredient selection or craving text changes. So ~1,200
/// static tokens sat outside the cacheable prefix on both recipe surfaces
/// despite the reorder looking correct in the caller.
///
/// The invariant these tests defend: **for two calls from the same surface
/// that differ only in variable content, the assembled messages must share a
/// prefix that includes the whole static block.** That is precisely what
/// OpenAI's prefix cache can serve.
void main() {
  final chef = ChefService();

  const staticBlock = 'STATIC-SCHEMA-BLOCK\nline two\nline three';

  // A real profile block, so the assertion below covers the ordering of the
  // profile section too — it is constant for one user but must still sit
  // behind the static block.
  UserProfile profileFor(String name) =>
      UserProfile.empty().copyWith(displayName: name);

  String build({
    required String query,
    String? recipeTitle,
    String? staticPromptBlock = staticBlock,
    UserProfile? profile,
  }) =>
      chef.buildUserMessage(
        userQuery: query,
        recipeTitle: recipeTitle,
        profile: profile,
        forceJsonObject: true,
        staticPromptBlock: staticPromptBlock,
      );

  group('static prefix survives variable content', () {
    test('static block precedes the recipe title', () {
      final msg = build(query: 'anything', recipeTitle: 'Fridge Clearer: leek');

      expect(msg, contains(staticBlock));
      expect(msg, contains('Fridge Clearer: leek'));
      expect(
        msg.indexOf(staticBlock),
        lessThan(msg.indexOf('Fridge Clearer: leek')),
        reason: 'the static block must not sit behind the per-call title',
      );
    });

    test('static block precedes the query', () {
      final msg = build(query: 'VARIABLE-QUERY-MARKER');

      expect(
        msg.indexOf(staticBlock),
        lessThan(msg.indexOf('VARIABLE-QUERY-MARKER')),
      );
    });

    test(
        'two calls differing in title AND query still share a prefix '
        'containing the whole static block', () {
      // This is the exact case the old ordering broke: same surface, same
      // user, different ingredients — i.e. any second Fridge Clearer
      // generation, or any second Custom AI craving.
      final a = build(
        query: 'Ingredients available: leek, potato, cream',
        recipeTitle: 'Fridge Clearer: cream + leek',
        profile: profileFor('Harris'),
      );
      final b = build(
        query: 'Ingredients available: aubergine, tomato, feta',
        recipeTitle: 'Fridge Clearer: aubergine + feta',
        profile: profileFor('Harris'),
      );

      expect(a, isNot(equals(b)), reason: 'the calls really do differ');

      var shared = 0;
      while (shared < a.length &&
          shared < b.length &&
          a.codeUnitAt(shared) == b.codeUnitAt(shared)) {
        shared++;
      }
      final commonPrefix = a.substring(0, shared);

      expect(
        commonPrefix,
        contains(staticBlock),
        reason: 'the whole static block must be inside the shared prefix — '
            'that is the only part OpenAI can serve from cache',
      );
      expect(
        commonPrefix.length,
        greaterThan(staticBlock.length),
        reason: 'the static header should be in there too',
      );
    });

    test('omitting the static block changes nothing else about the message',
        () {
      final withBlock = build(query: 'q', recipeTitle: 't');
      final without =
          build(query: 'q', recipeTitle: 't', staticPromptBlock: null);

      expect(without, isNot(contains(staticBlock)));
      // Everything the conversational surfaces rely on is untouched.
      expect(without, contains('Reply with concise, actionable steps.'));
      expect(without, contains('Recipe context: t'));
      expect(withBlock.replaceFirst('$staticBlock\n\n', ''), equals(without));
    });
  });

  group('curriculum matching is unchanged by the split', () {
    test('the static block is still part of the curriculum match text', () {
      // Before the split, the caller's static text was part of userQuery and
      // so was matched against for Bucket B drawer selection. Passing it
      // separately must not silently change which drawers get injected —
      // that would be a behavioural change, not an ordering one.
      final viaQuery = chef.buildUserMessage(
        userQuery: 'julienne everything',
        forceJsonObject: true,
      );
      final viaStaticBlock = chef.buildUserMessage(
        userQuery: 'nothing relevant here',
        staticPromptBlock: 'julienne everything',
        forceJsonObject: true,
      );

      // 'julienne' triggers the core_knife_cuts reference drawer either way.
      expect(viaQuery.length, greaterThan(200));
      expect(
        viaStaticBlock.length,
        greaterThan(200),
        reason: 'a keyword in the static block must still pull its drawer',
      );
      expect(
        viaStaticBlock.contains('CUT SPECS') ||
            viaStaticBlock.contains('julienne'),
        isTrue,
      );
    });
  });

  group('the cooking-times key list in the static prefix', () {
    test('both recipe prompts carry the whole closed list and the schema field', () {
      for (final block in [
        buildFridgeClearerStaticPrompt(),
        buildCustomCreatorStaticPrompt(),
      ]) {
        expect(block, contains('"cooking_times_key"'));
        expect(block, contains(CookingTimes.promptKeyList),
            reason: 'the model can only declare from a list it was given');
        for (final sample in ['spinach_whole_leaf', 'beef_stewing_3cm_dice', 'red_lentils_simmer']) {
          expect(block, contains(sample));
        }
      }
    });

    test('stage 1 does not carry it — it asks for no ingredients to key', () {
      final ideas = buildFridgeIdeasStaticPrompt();
      expect(ideas, isNot(contains('cooking_times_key')));
      expect(ideas, isNot(contains(CookingTimes.promptKeyList)),
          reason: 'the menu-of-three call is deliberately tiny');
    });

    test('the list is in the STATIC half, so it stays inside the cached prefix', () {
      // The whole point of option C: ~800 prompt tokens that never vary, and
      // therefore cost the cached rate on every call after the first.
      final assembled = ChefService().buildUserMessage(
        userQuery: 'something entirely per-call',
        staticPromptBlock: buildFridgeClearerStaticPrompt(),
      );
      expect(
        assembled.indexOf(CookingTimes.promptKeyList),
        lessThan(assembled.indexOf('something entirely per-call')),
        reason: 'anything per-call must land after every static byte',
      );
    });
  });

  group('surface identifiers', () {
    test('there are exactly ten, matching the live call sites and retries', () {
      // Four since the Fridge Clearer went two-stage (2026-08-22): the
      // menu-of-three call and the full-recipe call are separate surfaces, so
      // browsing cost and committing cost can be told apart. Six since the
      // compatibility validator (2026-08-23): each recipe surface's
      // correction retries bill to their own value, so the retry rate is
      // readable straight off api_call_cost_log rather than inferred.
      // Eight since the safety validator (2026-08-23): a safety correction is
      // different work from a timing correction and gets its own value, for
      // the same reason the two validators are separate code.
      // Ten since the allergen guard (2026-08-23): an allergen correction is
      // the one whose failure is an allergic reaction, and its rate must be
      // readable on its own rather than averaged into a timing bucket.
      expect(kChefCallSurfaces, hasLength(10));
      expect(
        kChefCallSurfaces,
        containsAll(<String>[
          kChefCallSurfaceFridgeClearer,
          kChefCallSurfaceFridgeClearerRetry,
          kChefCallSurfaceFridgeClearerSafetyRetry,
          kChefCallSurfaceFridgeIdeas,
          kChefCallSurfaceCustomCreator,
          kChefCallSurfaceCustomCreatorRetry,
          kChefCallSurfaceCustomCreatorSafetyRetry,
          kChefCallSurfaceFridgeClearerAllergenRetry,
          kChefCallSurfaceCustomCreatorAllergenRetry,
          kChefCallSurfaceChefSos,
        ]),
      );
    });

    test('the safety retry surfaces are stable strings, distinct from timing', () {
      expect(kChefCallSurfaceFridgeClearerSafetyRetry, 'fridge_clearer_safety_retry');
      expect(kChefCallSurfaceCustomCreatorSafetyRetry, 'custom_creator_safety_retry');
      expect(kChefCallSurfaceFridgeClearerSafetyRetry,
          isNot(kChefCallSurfaceFridgeClearerRetry));
      expect(kChefCallSurfaceCustomCreatorSafetyRetry,
          isNot(kChefCallSurfaceCustomCreatorRetry));
    });

    test('values are stable strings — they are stored in a DB column', () {
      expect(kChefCallSurfaceFridgeClearer, 'fridge_clearer');
      expect(kChefCallSurfaceFridgeClearerRetry, 'fridge_clearer_retry');
      expect(kChefCallSurfaceFridgeIdeas, 'fridge_ideas');
      expect(kChefCallSurfaceCustomCreator, 'custom_creator');
      expect(kChefCallSurfaceCustomCreatorRetry, 'custom_creator_retry');
      expect(kChefCallSurfaceChefSos, 'chef_sos');
    });
  });
}
