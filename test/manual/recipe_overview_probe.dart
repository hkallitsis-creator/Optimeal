// Live probe against DEV. No `_test.dart` suffix, so the default
// `flutter test` glob skips it — it makes real, billed OpenAI calls.
//
// Run:  flutter test test/manual/recipe_overview_probe.dart
//
// Prints, for one Fridge Clearer generation and one Custom generation:
//   * the meta line exactly as the overview renders it
//   * every scaled ingredient row at N = 1, 3, 6
//   * the cut-resolver match table

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

void _log(Object? o) {
  // ignore: avoid_print
  print(o);
}

void main() {
  HttpOverrides.global = null;

  test('recipe overview rendering against dev', () async {
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
      required String label,
      required String userQuery,
      required String staticBlock,
      required ChefRecipeSurface surface,
      required String title,
    }) async {
      final userMessage = chef.buildUserMessage(
        userQuery: userQuery,
        recipeTitle: title,
        forceJsonObject: true,
        staticPromptBlock: staticBlock,
      );
      final res = await http.post(
        Uri.parse('$base/functions/v1/ask-chef-harris'),
        headers: {
          'apikey': apiKey,
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'systemPrompt': ChefService.systemPrompt,
          'userMessage': userMessage,
          'temperature': 0.25,
          'forceJsonObject': true,
          'surface': 'overview_probe',
        }),
      );
      if (res.statusCode != 200) {
        _log('PROBE $label: HTTP ${res.statusCode} ${res.body}');
        return null;
      }
      final content = (jsonDecode(res.body) as Map)['content']?.toString() ?? '';
      return parseChefRecipeJson(
        raw: content,
        portions: 2,
        fallbackTitle: title,
        surface: surface,
        useGenericFallbacks: false,
        readDescription: true,
      );
    }

    var totalIngredients = 0;
    var withCut = 0;
    var withPill = 0;

    Future<void> render(String label, CookModeRecipePayload? recipe) async {
      _log('\n════════════════════════════════════════════════════');
      _log('PROBE $label');
      _log('════════════════════════════════════════════════════');
      if (recipe == null) {
        _log('  NO RECIPE');
        return;
      }

      final minutes =
          estimatedMinutes(recipe.steps.map((s) => s.durationMinutes));
      _log('  title:       ${recipe.title}');
      _log('  description: ${recipe.description ?? "(none)"}');
      _log('  META LINE:   ~$minutes min · ${recipe.steps.length} steps');
      _log('  basePortions: ${recipe.basePortions}');

      final structured = recipe.structuredIngredients ?? const [];
      for (final n in [1, 3, 6]) {
        _log('\n  ── Serves $n ──────────────────────────────');
        final scaled = scaleIngredients(
          ingredients: structured,
          basePortions: recipe.basePortions,
          servings: n,
        );
        for (final row in scaled) {
          final pill = resolveCutDiagramKey(
              ingredient: row.raw, steps: recipe.steps);
          final hint = row.roundedUp ? '  · rounded up' : '';
          final pillText = pill == null ? '' : '   [pill: $pill]';
          _log('    ${row.displayLine}$hint$pillText');
        }
      }

      _log('\n  ── cut resolution ────────────────────────');
      for (final ing in structured) {
        totalIngredients++;
        final key = resolveCutKey(ingredient: ing, steps: recipe.steps);
        final pill = resolveCutDiagramKey(ingredient: ing, steps: recipe.steps);
        if (key != null) withCut++;
        if (pill != null) withPill++;
        _log('    ${ing.name.padRight(28)} declared=${ing.cut ?? "-"}'
            '  resolved=${key ?? "-"}  pill=${pill ?? "-"}');
      }
    }

    final fridge = await generate(
      label: '1. FRIDGE CLEARER',
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
            'and a "unit", realistically scaled for 2 people.',
      ].join('\n'),
    );
    await render('1. FRIDGE CLEARER', fridge);

    await Future<void>.delayed(const Duration(seconds: 8));

    final custom = await generate(
      label: '2. CUSTOM CREATOR',
      title: 'Spanish omelette',
      staticBlock: buildCustomCreatorStaticPrompt(),
      surface: ChefRecipeSurface.customAiRecipeCreator,
      userQuery: [
        'The user wants: a classic Spanish omelette.',
        '- Number of people this recipe should serve: 2',
        '- Each ingredient must be a structured object with a numeric "amount" '
            'and a "unit".',
      ].join('\n'),
    );
    await render('2. CUSTOM CREATOR', custom);

    _log('\n════════════════════════════════════════════════════');
    _log('PROBE RESOLVER MATCH RATE');
    _log('  ingredients seen:            $totalIngredients');
    _log('  with any cut detected:       $withCut');
    _log('  pills rendered (built only): $withPill');
    _log('════════════════════════════════════════════════════');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
