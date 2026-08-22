import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/safety_flag_log.dart';
import 'package:optimeal/services/safety_validator.dart';
import 'package:optimeal/services/validated_recipe_generation.dart';

/// The ordering contract between the two validators.
///
/// The rule this file exists to protect: **safety judges the recipe that is
/// actually served, and the deterministic injection is applied after every
/// correction round of both layers.** A compatibility retry produces a whole
/// new recipe; if injection happened before that retry it would be thrown away
/// with the draft it was written onto, and H1's guarantee would quietly become
/// "usually".
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
  // Initialised so the flag logs take their real write path here rather than
  // their catch block. The logs are meant to be unable to break a generation,
  // and the surrounding tests would pass either way — this makes them test the
  // path that actually runs on a device.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Potato at 2cm dice (B4) with spinach (B1) is the signed table's own worked
  // violation — three bands apart in one step. Both recipes below cook chicken
  // and declare no sensory cue, so H1 applies to both.
  const compatViolatingChicken = '''
{"title":"Bad timing",
 "ingredients":[
   {"name":"chicken breast","amount":300,"unit":"g","cooking_times_key":"chicken_breast_2cm_dice"},
   {"name":"potato","amount":200,"unit":"g","cooking_times_key":"potato_waxy_2cm_dice"},
   {"name":"spinach","amount":50,"unit":"g","cooking_times_key":"spinach_whole_leaf"}],
 "steps":[
  {"title":"Everything at once","duration_minutes":12,"heat":"medium",
   "ingredients_added":["potato","spinach"],"bullets":["in it all goes"]},
  {"title":"Cook the chicken breast","duration_minutes":10,"heat":"medium",
   "ingredients_added":["chicken breast"],"bullets":["turn it once"]}]}''';

  const compatCleanChicken = '''
{"title":"Good timing",
 "ingredients":[
   {"name":"chicken breast","amount":300,"unit":"g","cooking_times_key":"chicken_breast_2cm_dice"},
   {"name":"potato","amount":200,"unit":"g","cooking_times_key":"potato_waxy_2cm_dice"},
   {"name":"spinach","amount":50,"unit":"g","cooking_times_key":"spinach_whole_leaf"}],
 "steps":[
  {"title":"Potato first","duration_minutes":12,"heat":"medium",
   "ingredients_added":["potato"],"bullets":["head start"]},
  {"title":"Cook the chicken breast","duration_minutes":10,"heat":"medium",
   "ingredients_added":["chicken breast"],"bullets":["turn it once"]},
  {"title":"Spinach last","duration_minutes":1,"heat":"medium",
   "ingredients_added":["spinach"],"bullets":["wilt it"]}]}''';

  Future<ValidatedRecipeResult> run(
    List<String?> replies, {
    List<RecipeRetryKind>? kinds,
    List<String?>? notes,
  }) {
    var call = 0;
    return generateValidatedRecipe(
      logSurface: 'ordering_test',
      attempt: ({String? correctionNote, required RecipeRetryKind retryKind}) async {
        kinds?.add(retryKind);
        notes?.add(correctionNote);
        return replies[call++];
      },
      parse: _parse,
    );
  }

  test('the injected cue survives a compatibility retry', () async {
    final kinds = <RecipeRetryKind>[];
    final result = await run([compatViolatingChicken, compatCleanChicken], kinds: kinds);

    expect(kinds, [RecipeRetryKind.first, RecipeRetryKind.compatibility],
        reason: 'the compatibility layer runs first and owns the first retry');

    // The served recipe is the corrected one...
    expect(result.recipe!.title, 'Good timing');
    expect(result.servedWithFlags, isFalse);

    // ...and the cue is on it, even though it was never on the draft that the
    // safety layer would have seen if it had run before the retry.
    final chickenStep = result.recipe!.steps
        .firstWhere((s) => s.title.contains('chicken'));
    expect(chickenStep.sensoryCue, 'juices_run_clear');
    expect(result.safetyReport.injections, hasLength(1));
    expect(result.safetyReport.injections.single.stepIndex, 1);
  });

  test('injection also applies when no retry happens at all', () async {
    final kinds = <RecipeRetryKind>[];
    final result = await run([compatCleanChicken], kinds: kinds);

    expect(kinds, [RecipeRetryKind.first]);
    expect(result.retriesUsed, 0);
    expect(result.safetyRetriesUsed, 0);
    expect(
      result.recipe!.steps.firstWhere((s) => s.title.contains('chicken')).sensoryCue,
      'juices_run_clear',
    );
  });

  test('injection still applies when the compatibility layer fails open', () async {
    // Three violating replies: two corrections spent, still flagged, served
    // anyway. The safety guarantee is not conditional on that outcome.
    final result = await run([
      compatViolatingChicken,
      compatViolatingChicken,
      compatViolatingChicken,
    ]);

    expect(result.servedWithFlags, isTrue, reason: 'compatibility failed open');
    expect(result.recipe, isNotNull);
    expect(
      result.recipe!.steps.firstWhere((s) => s.title.contains('chicken')).sensoryCue,
      'juices_run_clear',
      reason: 'a timing failure must not cost the safety guarantee',
    );
  });

  test('the served safety report describes the recipe after injection', () async {
    final result = await run([compatCleanChicken]);

    // H1 is satisfied on the served recipe, so it no longer appears as a
    // finding — but the injection that satisfied it is recorded.
    expect(
      result.safetyReport.findings.where((f) => f.rule == SafetyRuleId.h1),
      isEmpty,
    );
    expect(result.safetyReport.injections, hasLength(1));
    expect(result.servedWithSafetyFindings, isFalse);
  });

  test('a correctable safety finding spends its own retry, billed separately', () async {
    // Beef mince with no cooked-through instruction anywhere: H2, correctable.
    const mincePink = '''
{"title":"Mince",
 "ingredients":[{"name":"beef mince","amount":400,"unit":"g","cooking_times_key":"beef_mince_loose"}],
 "steps":[{"title":"Brown the beef mince","duration_minutes":8,"heat":"medium",
   "ingredients_added":["beef mince"],"bullets":["stir now and then"]}]}''';
    const minceFixed = '''
{"title":"Mince",
 "ingredients":[{"name":"beef mince","amount":400,"unit":"g","cooking_times_key":"beef_mince_loose"}],
 "steps":[{"title":"Brown the beef mince","duration_minutes":8,"heat":"medium",
   "ingredients_added":["beef mince"],"bullets":["cook it through, no pink left"]}]}''';

    final kinds = <RecipeRetryKind>[];
    final notes = <String?>[];
    final result = await run([mincePink, minceFixed], kinds: kinds, notes: notes);

    expect(kinds, [RecipeRetryKind.first, RecipeRetryKind.safety],
        reason: 'no compatibility flag here, so the only retry is the safety one');
    expect(notes[1], contains('FOOD SAFETY CORRECTION REQUIRED'));
    expect(notes[1], contains('[H2]'));
    expect(result.safetyRetriesUsed, 1);
    expect(result.retriesUsed, 0, reason: 'the compatibility counter is untouched');
    expect(result.servedWithSafetyFindings, isFalse);
  });

  test('safety retries are capped, then the recipe is served with the finding logged', () async {
    const mincePink = '''
{"title":"Mince",
 "ingredients":[{"name":"beef mince","amount":400,"unit":"g","cooking_times_key":"beef_mince_loose"}],
 "steps":[{"title":"Brown the beef mince","duration_minutes":8,"heat":"medium",
   "ingredients_added":["beef mince"],"bullets":["stir now and then"]}]}''';

    final kinds = <RecipeRetryKind>[];
    final result = await run([mincePink, mincePink, mincePink], kinds: kinds);

    expect(kinds, [
      RecipeRetryKind.first,
      RecipeRetryKind.safety,
      RecipeRetryKind.safety,
    ]);
    expect(result.safetyRetriesUsed, kMaxSafetyRetries);
    expect(result.recipe, isNotNull,
        reason: 'the registry signed correction-and-regenerate, never blocking');
    expect(result.servedWithSafetyFindings, isTrue);
  });

  group('the safety flag log', () {
    test('writes one entry per generation, into its own buffer', () async {
      await SafetyFlagLog.clear();
      await run([compatCleanChicken]);

      final entries = await SafetyFlagLog.read();
      expect(entries, hasLength(1));

      final e = entries.single;
      expect(e['surface'], 'ordering_test');
      expect(e['retries_used'], 0);
      expect(e['served_with_findings'], isFalse);
      expect(e['injections_applied'], 1);
      expect(e['steps_checked'], 3);
      expect(e['at'], isA<String>());
      expect(DateTime.tryParse(e['at'] as String), isNotNull);

      final injections = e['injections'] as List<dynamic>;
      expect(injections.single, containsPair('cue', 'juices_run_clear'));
    });

    test('is a separate key from the compatibility log', () {
      expect(SafetyFlagLog.storageKey, 'safety_flag_log_v1');
      expect(SafetyFlagLog.storageKey, isNot('compatibility_flag_log_v1'));
      expect(SafetyFlagLog.maxEntries, 50);
    });

    test('is newest first and bounded', () async {
      await SafetyFlagLog.clear();
      for (var i = 0; i < 3; i++) {
        await SafetyFlagLog.record(
          surface: 'surface_$i',
          report: const SafetyReport.clean(),
          retriesUsed: 0,
          servedWithFindings: false,
        );
      }
      final entries = await SafetyFlagLog.read();
      expect(entries.map((e) => e['surface']), ['surface_2', 'surface_1', 'surface_0']);
    });
  });

  test('a failed safety retry never costs the recipe we already had', () async {
    const mincePink = '''
{"title":"Mince",
 "ingredients":[{"name":"beef mince","amount":400,"unit":"g","cooking_times_key":"beef_mince_loose"}],
 "steps":[{"title":"Brown the beef mince","duration_minutes":8,"heat":"medium",
   "ingredients_added":["beef mince"],"bullets":["stir now and then"]}]}''';

    final result = await run([mincePink, null]);

    expect(result.recipe, isNotNull);
    expect(result.recipe!.title, 'Mince');
    expect(result.servedWithSafetyFindings, isTrue);
  });
}
