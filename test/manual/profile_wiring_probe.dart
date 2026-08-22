// Live probe against DEV. No `_test.dart` suffix, so the default
// `flutter test` glob skips it — it makes real, billed OpenAI calls.
//
// Run:  flutter test test/manual/profile_wiring_probe.dart
//
// Answers spec §4: for each of the five profile controls, is it LIVE or
// DECORATIVE? Traces UI → store → payload, then proves it in real output with
// a deliberately adversarial profile.
//
// The hard case, on purpose: the user's allergens are egg, dairy and nuts, and
// they then hand the Fridge Clearer "eggs, cheese, walnuts" as ingredients
// they HAVE. A prompt that merely mentions allergies is not enough here — the
// model is being actively tempted.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';

void _log(Object? o) {
  // ignore: avoid_print
  print(o);
}

final UserProfile adversarial = UserProfile(
  displayName: 'Harris',
  language: 'en',
  diet: UserDiet.vegan,
  allergies: const ['Egg', 'Lactose/Dairy', 'Tree Nuts'],
  kitchenConfidence: KitchenConfidence.beginner,
  householdServings: 5,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
  onboarded: true,
);

void main() {
  HttpOverrides.global = null;

  test('profile wiring against dev', () async {
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

    // ── Payload evidence first: what actually reaches the model ───────────
    final message = chef.buildUserMessage(
      userQuery: 'Suggest three ways to clear this fridge.',
      profile: adversarial,
      forceJsonObject: true,
      staticPromptBlock: buildFridgeIdeasStaticPrompt(),
    );

    _log('\n════════ PAYLOAD EXCERPT — profile block ════════');
    final lines = message.split('\n');
    final start = lines.indexWhere((l) => l.startsWith('User profile context'));
    if (start == -1) {
      _log('  !! NO PROFILE BLOCK IN PAYLOAD — all five fields decorative');
    } else {
      for (var i = start; i < lines.length && i < start + 10; i++) {
        if (lines[i].trim().isEmpty) break;
        _log('  ${lines[i]}');
      }
    }

    // Ordering check: the profile block must come AFTER the static block.
    final staticFirstLine = buildFridgeIdeasStaticPrompt().trim().split('\n').first.trim();
    _log('\n  static block at index : ${message.indexOf(staticFirstLine)}');
    _log('  profile block at index: ${message.indexOf('User profile context')}');

    Future<String?> call(String userQuery, String staticBlock,
        {String? title}) async {
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
            profile: adversarial,
            forceJsonObject: true,
            staticPromptBlock: staticBlock,
          ),
          'temperature': 0.25,
          'forceJsonObject': true,
          'surface': 'profile_probe',
        }),
      );
      if (res.statusCode != 200) {
        _log('  HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      return (jsonDecode(res.body) as Map)['content']?.toString();
    }

    // ── 1. Fridge Clearer: the hard case ─────────────────────────────────
    _log('\n════════ RUN 1 — FRIDGE CLEARER (adversarial) ════════');
    _log('  chips: eggs, cheese, walnuts, potatoes, spinach');
    _log('  profile: vegan · avoid Egg/Dairy/Tree Nuts · beginner · serves 5');

    final ideasRaw = await call(
      [
        'Suggest three ways to clear this fridge.',
        '',
        'Context (Swiss home kitchen):',
        '- Ingredients the user has and wants to use up: eggs, cheese, walnuts, potatoes, spinach',
        '- Time available: about 30 minutes',
        '- Cookware/appliances available: one pan, oven',
        '- Number of people to serve: 5',
      ].join('\n'),
      buildFridgeIdeasStaticPrompt(),
    );
    _log('  RAW IDEAS: ${ideasRaw?.replaceAll('\n', ' ')}');

    await Future<void>.delayed(const Duration(seconds: 6));

    final recipeRaw = await call(
      [
        'Create a cook-mode recipe for this specific idea: "Potato and spinach bake".',
        '',
        'Context (Swiss home kitchen):',
        '- Ingredients available: eggs, cheese, walnuts, potatoes, spinach',
        '- Number of people this recipe should serve: 5',
        '- Each ingredient must be a structured object with a numeric "amount" and a "unit".',
      ].join('\n'),
      buildFridgeClearerStaticPrompt(),
      title: 'Potato and spinach bake',
    );
    final recipe = recipeRaw == null
        ? null
        : await parseChefRecipeJson(
            raw: recipeRaw,
            portions: 5,
            fallbackTitle: 'Potato and spinach bake',
            surface: ChefRecipeSurface.fridgeClearer,
            useGenericFallbacks: false,
            readDescription: true,
          );

    _log('\n  ── generated recipe ─────────────────────');
    if (recipe == null) {
      _log('    NO RECIPE');
    } else {
      _log('    title: ${recipe.title}');
      _log('    basePortions: ${recipe.basePortions}');
      for (final i in recipe.structuredIngredients ?? const []) {
        _log('    ingredient: ${i.name}  (${i.amount} ${i.unit})');
      }
      _log('    step 1 bullets: ${recipe.steps.isEmpty ? "-" : recipe.steps.first.bullets.join(" | ")}');
    }

    await Future<void>.delayed(const Duration(seconds: 6));

    // ── 2. Custom: "carbonara" — a dish that IS egg + dairy + pork ───────
    _log('\n════════ RUN 2 — CUSTOM "carbonara" ════════');
    final customRaw = await call(
      [
        'The user wants: carbonara.',
        '- Number of people this recipe should serve: 5',
        '- Each ingredient must be a structured object with a numeric "amount" and a "unit".',
      ].join('\n'),
      buildCustomCreatorStaticPrompt(),
      title: 'carbonara',
    );
    final custom = customRaw == null
        ? null
        : await parseChefRecipeJson(
            raw: customRaw,
            portions: 5,
            fallbackTitle: 'carbonara',
            surface: ChefRecipeSurface.customAiRecipeCreator,
            useGenericFallbacks: false,
            readDescription: true,
          );

    if (custom == null) {
      _log('    NO RECIPE');
    } else {
      _log('    title: ${custom.title}');
      _log('    basePortions: ${custom.basePortions}');
      for (final i in custom.structuredIngredients ?? const []) {
        _log('    ingredient: ${i.name}  (${i.amount} ${i.unit})');
      }
      _log('    step 1 title: ${custom.steps.isEmpty ? "-" : custom.steps.first.title}');
      _log('    step 1 bullets: ${custom.steps.isEmpty ? "-" : custom.steps.first.bullets.join(" | ")}');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
