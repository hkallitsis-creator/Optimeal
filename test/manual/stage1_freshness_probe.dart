// Live probe against DEV. Not part of the suite — no `_test.dart` suffix, so
// the default `flutter test` glob skips it, which matters because it makes
// real, billed OpenAI calls.
//
// Run:  flutter test test/manual/stage1_freshness_probe.dart
//
// Question it answers (Part 4 of the 2026-08-23 design-QA round): the signed
// Fridge Clearer flow has NO regenerate button on the three-ideas screen. The
// only escape from three ideas you do not like is back → "Let's Cook", which
// re-runs stage 1. If that produced the same three ideas, the user would be in
// a dead end with no way out.
//
// This fires stage 1 twice with byte-identical input and prints both sets.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/models/fridge_idea.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/services/chef_service.dart';

void _log(Object? o) {
  // ignore: avoid_print
  print(o);
}

/// Mirrors `_FridgeClearerScreenState._buildIdeasVariablePrompt` exactly.
String _ideasVariablePrompt(List<String> ingredients, int portions) => [
      'Suggest three ways to clear this fridge.',
      '',
      'Context (Swiss home kitchen):',
      '- Ingredients the user has and wants to use up: ${ingredients.join(', ')}',
      '- Time available: about 30 minutes',
      '- Cookware/appliances available: one pan, oven, saucepan',
      '- Number of people to serve: $portions',
    ].join('\n');

void main() {
  // flutter_test installs an HttpOverrides that fails every real request with
  // a 400. This is one of the two files in the repo that genuinely wants the
  // network.
  HttpOverrides.global = null;

  test('stage 1 twice, identical input', () async {
    final base = AppEnvironmentConfig.supabase.url;
    final apiKey = AppEnvironmentConfig.supabase.anonKey;

    final signUp = await http.post(
      Uri.parse('$base/auth/v1/signup'),
      headers: {'apikey': apiKey, 'Content-Type': 'application/json'},
      body: '{}',
    );
    final jwt = (jsonDecode(signUp.body) as Map)['access_token'] as String;
    _log('PROBE signed in anonymously against $base');

    const ingredients = ['courgette', 'chicken thighs', 'spring onion', 'feta'];
    const portions = 2;
    final variable = _ideasVariablePrompt(ingredients, portions);
    final chef = ChefService();

    // Mirrors RecentGenerationsService: the screen now records each idea it
    // showed, so a second stage-1 call in the same session sees the first
    // three and is told not to repeat them.
    final seenTitles = <String>[];

    Future<List<FridgeIdea>?> runStageOne(String label) async {
      final userMessage = chef.buildUserMessage(
        userQuery: variable,
        forceJsonObject: true,
        recentDishTitles: List<String>.from(seenTitles),
        staticPromptBlock: buildFridgeIdeasStaticPrompt(),
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
          'surface': 'fridge_ideas',
        }),
      );
      if (res.statusCode != 200) {
        _log('PROBE $label: HTTP ${res.statusCode} ${res.body}');
        return null;
      }
      final data = jsonDecode(res.body) as Map;
      final usage = data['usage'];
      if (usage is Map) {
        _log('PROBE $label tokens: prompt=${usage['prompt_tokens']} '
            'completion=${usage['completion_tokens']}');
      }
      return parseFridgeIdeasJson(data['content']?.toString() ?? '');
    }

    _log('\nPROBE input (identical for both runs): ${ingredients.join(', ')}');

    final first = await runStageOne('RUN 1');
    _log('\n── RUN 1 ────────────────────────────────────────────');
    for (final i in first ?? const <FridgeIdea>[]) {
      _log('  • ${i.title}');
      seenTitles.add(i.title);
    }

    // The user pressing back and then "Let's Cook" again.
    await Future<void>.delayed(const Duration(seconds: 6));

    final second = await runStageOne('RUN 2');
    _log('\n── RUN 2 (back → Let\'s Cook, same chips) ────────────');
    for (final i in second ?? const <FridgeIdea>[]) {
      _log('  • ${i.title}');
    }

    final a = (first ?? []).map((e) => e.title.toLowerCase().trim()).toSet();
    final b = (second ?? []).map((e) => e.title.toLowerCase().trim()).toSet();
    _log('\nPROBE overlap: ${a.intersection(b).length} of ${a.length}');
    _log('PROBE identical set: ${a.length == b.length && a.difference(b).isEmpty}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
