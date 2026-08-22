import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/generation_truncation_log.dart';
import 'package:optimeal/services/validated_recipe_generation.dart';

/// The pre-vacation insurance bundle (audit M-3, M-4, M-6): token headroom,
/// one gateway retry, and the full validator chain on every regenerate.

Future<CookModeRecipePayload?> _parse(String raw, List<String> unknownKeys) =>
    parseChefRecipeJson(
      raw: raw,
      portions: 2,
      fallbackTitle: 'Test dish',
      surface: ChefRecipeSurface.fridgeClearer,
      useGenericFallbacks: false,
      unknownCookingTimesKeys: unknownKeys,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ────────────────────────────────────────────────────────────────────────
  group('Part 1 — token headroom (client half; edge redeploy owed)', () {
    test('recipe surfaces send maxTokens 2000; the ideas stage does not', () {
      // The constant, and where it is (and is not) wired. The deployed edge
      // function currently IGNORES the field (hardcoded 1200 — an effective
      // clamp, reported and stopped on per the brief); this pins the client
      // half so the raise lands the moment the function is redeployed.
      expect(kRecipeGenerationMaxTokens, 2000);
      final fridge =
          File('lib/screens/fridge_clearer_screen.dart').readAsStringSync();
      final custom = File('lib/widgets/custom_ai_recipe_creator_sheet.dart')
          .readAsStringSync();
      expect(fridge.contains('maxTokens: kRecipeGenerationMaxTokens'), isTrue);
      expect(custom.contains('maxTokens: kRecipeGenerationMaxTokens'), isTrue);
      // Stage 1 (ideas) deliberately does not send it: measured completions
      // are ~155 tokens against the 1,200 cap.
      final stage1 = fridge.substring(
          fridge.indexOf('_generateIdeasWithAllergenFilter'),
          fridge.indexOf('_generateIdeas()'));
      expect(stage1.contains('maxTokens'), isFalse);
    });

    test('a "length" finish_reason is logged with the surface', () async {
      final chef = ChefService(transport: (payload) async {
        expect(payload['maxTokens'], 2000);
        return {
          'content': '{"title":"Truncated mid',
          'usage': {'completion_tokens': 2000},
          'model': 'gpt-4o',
          'finish_reason': 'length',
        };
      });

      final reply = await chef.askChefHarris(
        userQuery: 'anything',
        forceJsonObject: true,
        surface: 'fridge_clearer',
        maxTokens: kRecipeGenerationMaxTokens,
      );

      // The truncated content falls through UNCHANGED: truncated JSON fails
      // the parser, which is exactly the parse-failure path the orchestrator
      // already retries/error-cards — nothing garbled reaches Cook Mode.
      expect(reply, '{"title":"Truncated mid');
      expect(await _parse(reply, []), isNull,
          reason: 'the parser is the existing failure path');

      await Future<void>.delayed(Duration.zero); // let the unawaited log land
      final log = await GenerationTruncationLog.read();
      expect(log, hasLength(1));
      expect(log.single['surface'], 'fridge_clearer');
      expect(log.single['finish_reason'], 'length');
    });

    test('a normal response logs nothing and behaves exactly as before',
        () async {
      final chef = ChefService(transport: (payload) async {
        return {
          'content': '{"title":"Fine"}',
          'usage': {'completion_tokens': 500},
          'model': 'gpt-4o',
          'finish_reason': 'stop',
        };
      });
      final reply = await chef.askChefHarris(
          userQuery: 'anything', forceJsonObject: true, surface: 's');
      expect(reply, '{"title":"Fine"}');
      expect(await GenerationTruncationLog.read(), isEmpty);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('Part 2 — one gateway retry (502/503/504)', () {
    FunctionException gateway(int status) =>
        FunctionException(status: status, details: 'Upstream AI request failed');

    test('502 then 200 → success, two calls, no extra wait machinery',
        () async {
      var calls = 0;
      final waits = <Duration>[];
      final result = await ChefService.invokeWithGatewayRetry<String>(
        () async {
          calls++;
          if (calls == 1) throw gateway(502);
          return 'ok';
        },
        wait: (d) async => waits.add(d),
      );
      expect(result, 'ok');
      expect(calls, 2);
      expect(waits, [ChefService.kGatewayRetryDelay]);
      expect(ChefService.kGatewayRetryDelay.inMilliseconds, 1500);
    });

    test('502 then 502 → the error surfaces, exactly two calls', () async {
      var calls = 0;
      await expectLater(
        ChefService.invokeWithGatewayRetry<String>(
          () async {
            calls++;
            throw gateway(502);
          },
          wait: (_) async {},
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, 2);
    });

    for (final status in [503, 504]) {
      test('$status is retried like 502', () async {
        var calls = 0;
        final result = await ChefService.invokeWithGatewayRetry<String>(
          () async {
            calls++;
            if (calls == 1) throw gateway(status);
            return 'ok';
          },
          wait: (_) async {},
        );
        expect(result, 'ok');
        expect(calls, 2);
      });
    }

    test('400 is never retried — one call, rethrown', () async {
      var calls = 0;
      await expectLater(
        ChefService.invokeWithGatewayRetry<String>(
          () async {
            calls++;
            throw gateway(400);
          },
          wait: (_) async {},
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, 1);
    });

    test('through askChefHarris: 502 then 200 succeeds end to end', () async {
      var calls = 0;
      final chef = ChefService(transport: (_) async {
        calls++;
        if (calls == 1) throw gateway(502);
        return {'content': 'recovered', 'model': 'gpt-4o'};
      });
      // Zero-length waits in tests: inject nothing — the default 1500 ms wait
      // runs, so use fakeAsync-free real time only where it is one call.
      final reply = await chef.askChefHarris(userQuery: 'hi', surface: 's');
      expect(reply, 'recovered');
      expect(calls, 2);
    });

    test('increments cannot double-count: this file never touches the caps',
        () {
      // Idempotency is structural: UsageCapService.increment fires once per
      // user INTENT in the screens, before generation starts — never inside
      // the transport that retries. A reference appearing here would put a
      // write before the model call and break that.
      // Comments stripped — doc references to both are legitimate and
      // plentiful; what must not exist is executable use.
      final code = File('lib/services/chef_service.dart')
          .readAsStringSync()
          .split('\n')
          .map((l) {
            final i = l.indexOf('//');
            return i == -1 ? l : l.substring(0, i);
          })
          .join('\n');
      expect(code.contains('UsageCapService'), isFalse);
      expect(code.contains('api_call_cost_log'), isFalse,
          reason: 'the cost log is written server-side, only after a '
              'successful OpenAI response — a 502 never had one');
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  group('Part 3 — every regenerate re-enters the full chain', () {
    // A: contains the avoided allergen; compat- and safety-clean.
    const walnutPasta = '''
{"title":"Walnut Pasta",
 "ingredients":[
   {"name":"walnuts","amount":50,"unit":"g","cooking_times_key":"none"},
   {"name":"penne","amount":200,"unit":"g","cooking_times_key":"none"}],
 "steps":[
  {"title":"Boil and toss","duration_minutes":12,"heat":"medium",
   "ingredients_added":["penne","walnuts"],"bullets":["toss with walnuts"]}]}''';

    // B: allergen-corrected (no walnuts) but carries a fresh H2 violation —
    // beef mince with no cooked-through statement anywhere.
    const minceNoCookedThrough = '''
{"title":"Mince Pasta",
 "ingredients":[
   {"name":"beef mince","amount":300,"unit":"g","cooking_times_key":"none"},
   {"name":"penne","amount":200,"unit":"g","cooking_times_key":"none"}],
 "steps":[
  {"title":"Brown the beef mince","duration_minutes":8,"heat":"medium",
   "ingredients_added":["beef mince"],"bullets":["brown it"]}]}''';

    // C: the H2 correction done properly.
    const minceCookedThrough = '''
{"title":"Mince Pasta Fixed",
 "ingredients":[
   {"name":"beef mince","amount":300,"unit":"g","cooking_times_key":"none"},
   {"name":"penne","amount":200,"unit":"g","cooking_times_key":"none"}],
 "steps":[
  {"title":"Brown the beef mince","duration_minutes":8,"heat":"medium",
   "ingredients_added":["beef mince"],
   "bullets":["cook until cooked through with no pink remaining"]}]}''';

    // Allergen-corrected output that cooks chicken with no declared cue —
    // the H1 injection must land on it.
    const chickenNoCue = '''
{"title":"Chicken Pasta",
 "ingredients":[
   {"name":"chicken breast","amount":300,"unit":"g","cooking_times_key":"none"},
   {"name":"penne","amount":200,"unit":"g","cooking_times_key":"none"}],
 "steps":[
  {"title":"Cook the chicken breast","duration_minutes":10,"heat":"medium",
   "ingredients_added":["chicken breast"],"bullets":["turn it once"]}]}''';

    Future<ValidatedRecipeResult> run(
      List<String?> replies, {
      List<RecipeRetryKind>? kinds,
      List<String> avoided = const ['Tree Nuts'],
    }) {
      var call = 0;
      return generateValidatedRecipe(
        logSurface: 'insurance_test',
        avoidedAllergens: avoided,
        attempt: ({String? correctionNote, required RecipeRetryKind retryKind}) async {
          kinds?.add(retryKind);
          return replies[call++];
        },
        parse: _parse,
      );
    }

    test(
        'an allergen regenerate whose output carries H2 gets the H2 '
        'correction round — not just a log line', () async {
      final kinds = <RecipeRetryKind>[];
      final result = await run(
        [walnutPasta, minceNoCookedThrough, minceCookedThrough],
        kinds: kinds,
      );

      expect(kinds, [
        RecipeRetryKind.first,
        RecipeRetryKind.allergen,
        RecipeRetryKind.safety,
      ], reason: 'the accepted allergen output re-enters the chain from the '
          'top; safety judges it and corrects the fresh H2');
      expect(result.recipe!.title, 'Mince Pasta Fixed');
      expect(result.allergenRetriesUsed, 1);
      expect(result.safetyRetriesUsed, 1);
      expect(result.allergenViolations, isEmpty);
      expect(result.servedWithSafetyFindings, isFalse);
    });

    test('H1 injection lands on an allergen-retry branch output too',
        () async {
      final kinds = <RecipeRetryKind>[];
      final result =
          await run([walnutPasta, chickenNoCue], kinds: kinds);

      expect(kinds, [RecipeRetryKind.first, RecipeRetryKind.allergen]);
      expect(result.recipe!.title, 'Chicken Pasta');
      final chickenStep = result.recipe!.steps
          .firstWhere((s) => s.title.contains('chicken'));
      expect(chickenStep.sensoryCue, 'juices_run_clear',
          reason: 'the deterministic injection is applied last, after every '
              'correction round of every layer — this branch included');
    });

    test('budgets are per-validator and never refunded across layers',
        () async {
      // Two allergen corrections both come back worse (still walnuts) —
      // the allergen budget alone is spent; compat and safety never fired
      // and their budgets are intact in the counts.
      final kinds = <RecipeRetryKind>[];
      final result = await run(
        [walnutPasta, walnutPasta, walnutPasta],
        kinds: kinds,
      );
      expect(kinds, [
        RecipeRetryKind.first,
        RecipeRetryKind.allergen,
        RecipeRetryKind.allergen,
      ]);
      expect(result.allergenRetriesUsed, 2);
      expect(result.retriesUsed, 0);
      expect(result.safetyRetriesUsed, 0);
      expect(result.allergenViolations, isNotEmpty,
          reason: 'fail-open with the loud log, exactly as ruled');
    });
  });
}
