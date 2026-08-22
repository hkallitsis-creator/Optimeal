import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/services/chef_service.dart';

/// Fridge Clearer stage 1 must carry variety pressure.
///
/// The signed flow has **no regenerate button** on the three-ideas screen —
/// the only escape from three ideas you do not like is back → "Let's Cook",
/// which re-runs stage 1. Stage 1 was passing no `recentDishTitles` while
/// stage 2 was, so at temperature 0.25 against a byte-identical prompt it
/// returned near-identical dishes: measured on dev, two of three ideas came
/// back the same across a back-and-retry pair. That made the signed escape
/// path a dead end.
void main() {
  final chef = ChefService();

  String stageOneMessage({List<String>? recent}) => chef.buildUserMessage(
        userQuery: 'Suggest three ways to clear this fridge.',
        forceJsonObject: true,
        recentDishTitles: recent,
        staticPromptBlock: buildFridgeIdeasStaticPrompt(),
      );

  test('the recent-titles block is present when titles exist', () {
    final message = stageOneMessage(
      recent: ['Chicken and Courgette Stir-Fry', 'Baked Feta Chicken'],
    );

    expect(message, contains('do NOT repeat any of these'));
    expect(message, contains('Chicken and Courgette Stir-Fry'));
    expect(message, contains('Baked Feta Chicken'));
  });

  test('the block is absent when there is nothing to exclude', () {
    final message = stageOneMessage(recent: const []);
    expect(message, isNot(contains('do NOT repeat any of these')));
  });

  test('the static block still precedes every per-call line', () {
    // The prompt-cache ordering rule: static prefix first, everything
    // per-call after it. Recent titles vary call to call, so if they landed
    // inside or before the static block they would break the cached prefix
    // for every recipe call downstream.
    final message = stageOneMessage(recent: ['Something Cooked Yesterday']);

    final staticBlock = buildFridgeIdeasStaticPrompt().trim();
    final staticAt = message.indexOf(staticBlock.split('\n').first.trim());
    final recentAt = message.indexOf('do NOT repeat any of these');

    expect(staticAt, greaterThanOrEqualTo(0),
        reason: 'the static block must be in the message at all');
    expect(recentAt, greaterThan(staticAt),
        reason: 'recent titles are per-call and must follow the static prefix');
  });

  test('stage 1 and stage 2 use the same exclusion mechanism', () {
    // Not two variety systems — one, reached from both stages, so a fix to
    // either lands on both.
    final stageOne = stageOneMessage(recent: ['Duck Ragu']);
    final stageTwo = chef.buildUserMessage(
      userQuery: 'Create a cook-mode recipe for this specific idea: "X".',
      forceJsonObject: true,
      recentDishTitles: ['Duck Ragu'],
      staticPromptBlock: buildFridgeClearerStaticPrompt(),
    );

    expect(stageOne, contains('do NOT repeat any of these'));
    expect(stageTwo, contains('do NOT repeat any of these'));
    expect(stageOne, contains('Duck Ragu'));
    expect(stageTwo, contains('Duck Ragu'));
  });
}
