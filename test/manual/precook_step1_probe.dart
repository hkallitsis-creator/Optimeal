// Live probe against DEV. No `_test.dart` suffix, so the default
// `flutter test` glob skips it — it makes real, billed OpenAI calls.
//
// Run:  flutter test test/manual/precook_step1_probe.dart
//
// Prints, for two real generations: the R1 dedup table (generated step count,
// detected prep-step title, final displayed count) and the Step 1 text blocks
// exactly as MiseEnPlaceCard composes them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/models/recipe_scale.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cut_key_resolver.dart';
import 'package:optimeal/services/prep_step_detector.dart';

void _log(Object? o) {
  // ignore: avoid_print
  print(o);
}

void main() {
  HttpOverrides.global = null;

  test('step 1 render against dev', () async {
    final base = AppEnvironmentConfig.supabase.url;
    final apiKey = AppEnvironmentConfig.supabase.anonKey;

    final signUp = await http.post(
      Uri.parse('$base/auth/v1/signup'),
      headers: {'apikey': apiKey, 'Content-Type': 'application/json'},
      body: '{}',
    );
    final jwt = (jsonDecode(signUp.body) as Map)['access_token'] as String;
    _log('PROBE signed in against $base');

    final chef = ChefService();

    Future<CookModeRecipePayload?> generate({
      required String title,
      required String userQuery,
      required String staticBlock,
      required ChefRecipeSurface surface,
    }) async {
      final res = await http.post(
        Uri.parse('$base/functions/v1/ask-chef-harris'),
        headers: {
          'apikey': apiKey,
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'systemPrompt': ChefService.systemPrompt,
          'userMessage': chef.buildUserMessage(
            userQuery: userQuery,
            recipeTitle: title,
            forceJsonObject: true,
            staticPromptBlock: staticBlock,
          ),
          'temperature': 0.25,
          'forceJsonObject': true,
          'surface': 'precook_probe',
        }),
      );
      if (res.statusCode != 200) {
        _log('PROBE HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      return parseChefRecipeJson(
        raw: (jsonDecode(res.body) as Map)['content']?.toString() ?? '',
        portions: 2,
        fallbackTitle: title,
        surface: surface,
        useGenericFallbacks: false,
        readDescription: true,
      );
    }

    void render(String label, CookModeRecipePayload? recipe) {
      _log('\n════════════════════════════════════════════════════');
      _log('PROBE $label');
      _log('════════════════════════════════════════════════════');
      if (recipe == null) {
        _log('  NO RECIPE');
        return;
      }

      final generated = recipe.steps;
      final names = (recipe.structuredIngredients ?? const [])
          .map((i) => i.name)
          .toList(growable: false);

      final isPrep = generated.isNotEmpty &&
          looksLikeGeneratedPrepStep(
            title: generated.first.title,
            bullets: generated.first.bullets,
            ingredientNames: names,
          );

      _log('  R1 generated step count : ${generated.length}');
      _log('  R1 first step title     : '
          '${generated.isEmpty ? "(none)" : generated.first.title}');
      _log('  R1 detected as prep     : $isPrep');
      final cooking = isPrep ? generated.sublist(1) : generated;
      _log('  R1 final displayed count: ${cooking.length + 1} '
          '(1 synthesized + ${cooking.length})');

      final servings = recipe.basePortions ?? 2;
      final scaled = scaleIngredients(
        ingredients: recipe.structuredIngredients ?? const [],
        basePortions: recipe.basePortions,
        servings: servings,
      );

      final knife = <String>[];
      final haveOut = <String>[];
      for (final row in scaled) {
        final cut = resolveCutKey(ingredient: row.raw, steps: recipe.steps);
        final pill =
            resolveCutDiagramKey(ingredient: row.raw, steps: recipe.steps);
        if (cut != null) {
          knife.add('${row.displayLine}'
              '${row.roundedUp ? "  · rounded up" : ""}'
              '${pill != null ? "   [pill: $pill]" : ""}');
        } else {
          haveOut.add(row.displayLine);
        }
      }

      _log('\n  ── STEP 1 AS RENDERED ─────────────────────');
      _log('    [1] Set up your board');
      _log('    ( No heat yet ) ( Serves $servings · set on recipe page )');
      _log('    sage: Everything cut and within reach before the pan gets hot.');
      if (knife.isNotEmpty) {
        _log('\n    NEEDS THE KNIFE');
        for (final k in knife) {
          _log('      $k');
        }
      }
      if (haveOut.isNotEmpty) {
        _log('\n    JUST HAVE IT OUT');
        _log('      ${haveOut.join(' · ')}');
      }
      _log('\n    Next · ${cooking.isEmpty ? "(none)" : cooking.first.title}');
      _log('    CTA: Board\'s clear — heat goes on');
    }

    render(
      '1. FRIDGE CLEARER',
      await generate(
        title: 'Chicken and courgette traybake',
        staticBlock: buildFridgeClearerStaticPrompt(),
        surface: ChefRecipeSurface.fridgeClearer,
        userQuery: [
          'Create a cook-mode recipe for this specific idea: '
              '"Chicken and courgette traybake".',
          '',
          'Context (Swiss home kitchen):',
          '- Ingredients available: chicken thighs, courgette, potatoes, feta, lemon',
          '- Time available: about 40 minutes',
          '- Cookware/appliances available: oven tray, pan',
          '- Number of people this recipe should serve: 2',
          '- Each ingredient must be a structured object with a numeric "amount" '
              'and a "unit".',
        ].join('\n'),
      ),
    );

    await Future<void>.delayed(const Duration(seconds: 8));

    render(
      '2. CUSTOM CREATOR',
      await generate(
        title: 'Spanish omelette',
        staticBlock: buildCustomCreatorStaticPrompt(),
        surface: ChefRecipeSurface.customAiRecipeCreator,
        userQuery: [
          'The user wants: a classic Spanish omelette.',
          '- Number of people this recipe should serve: 2',
          '- Each ingredient must be a structured object with a numeric "amount" '
              'and a "unit".',
        ].join('\n'),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
