// Live probe against DEV — generates one custom recipe and writes it out.
//
// Run:  flutter test test/manual/custom_creator_probe.dart
// Then: flutter test test/manual/custom_creator_render_probe.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/services/chef_service.dart';

void _log(Object? o) {
  // ignore: avoid_print
  print(o);
}

void main() {
  HttpOverrides.global = null;

  test('custom creator generation against dev', () async {
    final base = AppEnvironmentConfig.supabase.url;
    final apiKey = AppEnvironmentConfig.supabase.anonKey;

    final signUp = await http.post(
      Uri.parse('$base/auth/v1/signup'),
      headers: {'apikey': apiKey, 'Content-Type': 'application/json'},
      body: '{}',
    );
    final jwt = (jsonDecode(signUp.body) as Map)['access_token'] as String;

    const craving = 'spicy veggie noodles';
    _log('PROBE typed craving: "$craving"');

    final chef = ChefService();
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
          userQuery: [
            'Create a cook-mode recipe based on this user request:',
            '"$craving"',
            '- Number of people this recipe should serve: 2',
            '- Each ingredient must be a structured object with a numeric '
                '"amount" and a "unit".',
          ].join('\n'),
          recipeTitle: craving,
          forceJsonObject: true,
          staticPromptBlock: buildCustomCreatorStaticPrompt(),
        ),
        'temperature': 0.25,
        'forceJsonObject': true,
        'surface': 'custom_creator',
      }),
    );

    if (res.statusCode != 200) {
      _log('PROBE HTTP ${res.statusCode}: ${res.body}');
      return;
    }
    final content = (jsonDecode(res.body) as Map)['content']?.toString() ?? '';
    File('build/custom_recipe.json').writeAsStringSync(content);
    _log('PROBE wrote build/custom_recipe.json');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
