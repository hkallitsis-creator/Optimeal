// Live probe against the DEV Supabase project. NOT part of the test suite —
// it has no `_test.dart` suffix, so the default `flutter test` glob skips it,
// which matters because it makes real, billed OpenAI calls.
//
// Run:  flutter test test/manual/live_safety_probe.dart
//
// What it exercises, end to end and for real: the actual prompt assembly
// (`ChefService.buildUserMessage`, so prompt order and the static prefix are
// the real ones), the deployed `ask-chef-harris` edge function on dev, the
// real parser, the compatibility validator, the safety validator, and the
// deterministic injection.
//
// It talks to the edge function over plain HTTP with a real anonymous JWT
// rather than through `Supabase.instance`, because `Supabase.initialize` needs
// platform plumbing (secure storage, app links) that does not exist in a
// headless `flutter test` process. Everything above the transport is the
// shipping code path.
//
// This is an observation harness, not an assertion suite.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cooking_compatibility_validator.dart';
import 'package:optimeal/services/safety_validator.dart';

void _log(Object? o) {
  // ignore: avoid_print
  print(o);
}

String _variablePrompt({
  required String dish,
  required List<String> ingredients,
  int portions = 2,
}) =>
    [
      'Create a cook-mode recipe for this specific idea: "$dish".',
      '',
      'Context (Swiss home kitchen):',
      '- Ingredients available (focus on perishables): ${ingredients.join(', ')}',
      '- Assume pantry staples available: oils, salt/pepper, spices, pasta/rice.',
      '- Time available: about 40 minutes',
      '- Cookware/appliances available: one pan, oven, saucepan',
      '- Number of people this recipe should serve: $portions',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit", '
          'realistically scaled for $portions people.',
    ].join('\n');

void main() {
  // NO TestWidgetsFlutterBinding here, and the HTTP override is cleared.
  // flutter_test installs an HttpOverrides that fails every real request with
  // a 400 — which is correct for a unit test and fatal for a live probe. This
  // is the one file in the repo that genuinely wants the network.
  HttpOverrides.global = null;

  const cases = <({String label, String dish, List<String> ingredients})>[
    (
      label: '1. POULTRY — the H1 case',
      dish: 'Pan-roasted chicken thighs with potatoes',
      ingredients: ['chicken thighs', 'potatoes', 'lemon', 'thyme'],
    ),
    (
      label: '2. PORK whole-muscle — H1 plus the H3 rest condition',
      dish: 'Pork chops with apple and sage',
      ingredients: ['pork chops', 'apple', 'sage', 'onion'],
    ),
    (
      label: '3. MINCE — the H2 case',
      dish: 'Quick beef ragu with spaghetti',
      ingredients: ['beef mince', 'tinned tomatoes', 'carrot', 'onion'],
    ),
    (
      label: '4. FERMENTATION — the H12 case',
      dish: 'Kimchi-style spiced cabbage to serve alongside rice',
      ingredients: ['napa cabbage', 'spring onion', 'chilli flakes', 'garlic'],
    ),
    (
      label: '5. LEFTOVER RICE — H5 and H11',
      dish: 'Egg fried rice from yesterday cooked rice',
      ingredients: ['leftover cooked rice', 'eggs', 'peas', 'spring onion'],
    ),
    (
      label: '6. VEGETABLE CONTROL — everything should stay quiet',
      dish: 'Courgette and lentil traybake',
      ingredients: ['courgette', 'red lentils', 'red pepper', 'feta'],
    ),
  ];

  test('live safety probe against dev', () async {
    final base = AppEnvironmentConfig.supabase.url;
    final apiKey = AppEnvironmentConfig.supabase.anonKey;

    final signUp = await http.post(
      Uri.parse('$base/auth/v1/signup'),
      headers: {'apikey': apiKey, 'Content-Type': 'application/json'},
      body: '{}',
    );
    final jwt = (jsonDecode(signUp.body) as Map)['access_token'] as String;
    _log('PROBE signed in anonymously against $base');

    final chef = ChefService();

    Future<String?> callChef(String userQuery, String dish, String surface) async {
      final userMessage = chef.buildUserMessage(
        userQuery: userQuery,
        recipeTitle: dish,
        forceJsonObject: true,
        staticPromptBlock: buildFridgeClearerStaticPrompt(),
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
          'surface': surface,
        }),
      );
      if (res.statusCode != 200) {
        _log('PROBE   edge function HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(res.body);
      if (data is Map) {
        final usage = data['usage'];
        if (usage is Map) {
          _log('PROBE   tokens: prompt=${usage['prompt_tokens']} '
              'completion=${usage['completion_tokens']} '
              'cached=${(usage['prompt_tokens_details'] is Map) ? (usage['prompt_tokens_details'] as Map)['cached_tokens'] : 'n/a'}');
        }
        return data['content']?.toString();
      }
      return data?.toString();
    }

    for (final c in cases) {
      _log('\n════════════════════════════════════════════════════');
      _log('PROBE ${c.label}');
      _log('  request: ${c.dish}');
      _log('════════════════════════════════════════════════════');

      // Firing six generations back to back reliably drew 502s from the edge
      // function ("Upstream AI request failed") on the later cases. Spacing
      // them out is a property of this probe, not of the app.
      await Future<void>.delayed(const Duration(seconds: 8));

      final variable = _variablePrompt(dish: c.dish, ingredients: c.ingredients);
      final started = DateTime.now();

      try {
        // ── attempt 1 ────────────────────────────────────────────────────
        final raw = await callChef(variable, c.dish, 'live_probe');
        if (raw == null) {
          _log('PROBE result: NO REPLY');
          continue;
        }

        final unknownKeys = <String>[];
        final parsed = await parseChefRecipeJson(
          raw: raw,
          portions: 2,
          fallbackTitle: c.dish,
          surface: ChefRecipeSurface.fridgeClearer,
          useGenericFallbacks: false,
          readDescription: true,
          unknownCookingTimesKeys: unknownKeys,
        );
        if (parsed == null) {
          _log('PROBE result: PARSE FAILED');
          continue;
        }
        CookModeRecipePayload recipe = parsed;

        var compat = validateCookingCompatibility(recipe, unknownKeys: unknownKeys);
        var safety = validateRecipeSafety(recipe);
        var safetyRetries = 0;

        _log('PROBE first pass — compat flags: ${compat.flags.length}, '
            'safety findings: ${safety.findings.length} '
            '(${safety.correctable.length} correctable)');
        for (final f in safety.findings) {
          _log('PROBE   PRE  ${f.rule.label} [${f.enforcement.name}] '
              'step=${f.stepIndex} subject=${f.subject}');
        }

        // ── safety correction rounds ─────────────────────────────────────
        while (safety.hasCorrectable && safetyRetries < kMaxSafetyRetries) {
          safetyRetries++;
          _log('PROBE   → safety correction round $safetyRetries');
          final retryRaw = await callChef(
            '$variable\n\n${safety.buildCorrectionNote()}',
            c.dish,
            'live_probe_safety_retry',
          );
          if (retryRaw == null) break;
          final retryKeys = <String>[];
          final candidate = await parseChefRecipeJson(
            raw: retryRaw,
            portions: 2,
            fallbackTitle: c.dish,
            surface: ChefRecipeSurface.fridgeClearer,
            useGenericFallbacks: false,
            readDescription: true,
            unknownCookingTimesKeys: retryKeys,
          );
          if (candidate == null) break;
          final candidateSafety = validateRecipeSafety(candidate);
          if (candidateSafety.correctable.length < safety.correctable.length) {
            recipe = candidate;
            safety = candidateSafety;
            compat = validateCookingCompatibility(candidate, unknownKeys: retryKeys);
          }
        }

        // ── the guarantee ────────────────────────────────────────────────
        final injected = applySafetyInjections(recipe);
        recipe = injected.recipe;
        final finalSafety = validateRecipeSafety(recipe);

        final elapsed = DateTime.now().difference(started);
        _log('PROBE title: ${recipe.title}   (${elapsed.inSeconds}s, '
            'safety retries: $safetyRetries)');
        _log('PROBE compat flags on served recipe: ${compat.flags.length}');
        for (final inj in injected.injections) {
          _log('PROBE   INJECTED ${inj.cueKey} on step ${inj.stepIndex + 1} '
              '"${inj.stepTitle}" (replaced: ${inj.replacedCueKey})');
        }
        for (final f in finalSafety.findings) {
          _log('PROBE   POST ${f.rule.label} [${f.enforcement.name}] '
              'step=${f.stepIndex} subject=${f.subject}');
        }
        if (injected.injections.isEmpty && finalSafety.findings.isEmpty) {
          _log('PROBE   (clean — no injections, no findings)');
        }
        for (var i = 0; i < recipe.steps.length; i++) {
          final s = recipe.steps[i];
          _log('PROBE   step ${i + 1}: heat=${s.heat} ${s.durationMinutes}min '
              'cue=${s.sensoryCue} :: ${s.title}');
        }
      } catch (e) {
        _log('PROBE ERROR: $e');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
