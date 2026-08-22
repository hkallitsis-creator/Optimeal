// Live probe against DEV — one deliberately LONG recipe request, to measure
// completion size against the deployed max_tokens cap (audit M-6).
//
// Run:  flutter test test/manual/long_recipe_probe.dart
//
// Reports the deployed function's token usage and whether it returns
// finish_reason (as of 2026-08-23 it does not — that, plus the hardcoded
// max_tokens: 1200, is the edge redeploy handed over in
// docs/sessions/2026-08-23_insurance-bundle.md).

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

  test('long recipe request against dev', () async {
    final base = AppEnvironmentConfig.supabase.url;
    final apiKey = AppEnvironmentConfig.supabase.anonKey;

    final signUp = await http.post(
      Uri.parse('$base/auth/v1/signup'),
      headers: {'apikey': apiKey, 'Content-Type': 'application/json'},
      body: '{}',
    );
    final jwt = (jsonDecode(signUp.body) as Map)['access_token'] as String;

    const craving =
        '8-step one-pan chicken and vegetable traybake with a pan sauce';
    _log('PROBE long request: "$craving"');

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
            '- Number of people this recipe should serve: 4',
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
        // Ignored by the deployed function (hardcoded 1200) — sent so this
        // probe doubles as the post-redeploy verification with no edit.
        'maxTokens': kRecipeGenerationMaxTokens,
      }),
    );

    if (res.statusCode != 200) {
      _log('PROBE HTTP ${res.statusCode}: ${res.body}');
      return;
    }
    final body = jsonDecode(res.body) as Map;
    final usage = body['usage'] as Map?;
    final content = body['content']?.toString() ?? '';
    _log('PROBE usage: prompt=${usage?['prompt_tokens']} '
        'cached=${(usage?['prompt_tokens_details'] as Map?)?['cached_tokens']} '
        'completion=${usage?['completion_tokens']}');
    _log('PROBE finish_reason in response: '
        '${body.containsKey('finish_reason') ? body['finish_reason'] : 'ABSENT (deployed function does not return it yet)'}');
    _log('PROBE completion vs deployed cap: '
        '${usage?['completion_tokens']} / 1200'
        '${(usage?['completion_tokens'] as num? ?? 0) >= 1200 ? '  ← AT THE CAP: truncated' : ''}');
    final looksComplete = content.trimRight().endsWith('}');
    _log('PROBE content chars: ${content.length} · '
        'JSON closes cleanly: $looksComplete');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
