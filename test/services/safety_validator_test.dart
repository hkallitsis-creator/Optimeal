import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/data/safety_ingredient_names.dart';
import 'package:optimeal/data/sensory_cue_vocabulary.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/safety_validator.dart';

/// Tests for the deterministic layer of the safety validator.
///
/// Every rule gets a positive and a negative case. The negatives matter more
/// than usual here: a safety rule that fires on a correct recipe trains the
/// model to write defensive noise, and a rule that fires on everything is
/// indistinguishable from a rule that fires on nothing.

CookModeStepPayload _step(
  String title, {
  String heat = 'medium',
  int minutes = 5,
  List<String> bullets = const [],
  List<String>? adds,
  String cue = SensoryCueVocabulary.noCueKey,
}) =>
    CookModeStepPayload(
      title: title,
      heat: heat,
      durationMinutes: minutes,
      bullets: bullets,
      ingredientsAdded: adds,
      sensoryCue: cue,
    );

CookModeRecipePayload _recipe({
  String title = 'Test dish',
  List<String> ingredients = const [],
  String? description,
  required List<CookModeStepPayload> steps,
}) =>
    CookModeRecipePayload(
      title: title,
      ingredients: ingredients,
      steps: steps,
      description: description,
    );

List<SafetyFinding> _findings(CookModeRecipePayload r, SafetyRuleId rule) =>
    validateRecipeSafety(r).findings.where((f) => f.rule == rule).toList();

void main() {
  group('H1 — poultry and pork doneness', () {
    test('a chicken step without the signed cue is detected', () {
      final r = _recipe(
        ingredients: ['chicken breast'],
        steps: [
          _step('Sear the chicken breast', adds: ['chicken breast']),
        ],
      );
      final f = _findings(r, SafetyRuleId.h1);
      expect(f, hasLength(1));
      expect(f.single.enforcement, SafetyEnforcement.inject);
      expect(f.single.stepIndex, 0);
    });

    test('a step that already declares the cue is not flagged', () {
      final r = _recipe(
        steps: [
          _step('Sear the chicken breast', cue: 'juices_run_clear'),
        ],
      );
      expect(_findings(r, SafetyRuleId.h1), isEmpty);
    });

    test('a vegetable recipe is never flagged', () {
      final r = _recipe(steps: [_step('Saute the courgette and spinach')]);
      expect(_findings(r, SafetyRuleId.h1), isEmpty);
    });

    test('cured ready-to-eat pork does not qualify', () {
      final r = _recipe(
        ingredients: ['pancetta', 'guanciale', 'prosciutto'],
        steps: [_step('Render the pancetta until crisp')],
      );
      expect(_findings(r, SafetyRuleId.h1), isEmpty,
          reason: 'a lardon has no thickest part to cut into');
    });

    test('an off-heat step is not a cooking step', () {
      final r = _recipe(
        steps: [
          _step('Slice the cooked chicken to serve', heat: 'off_heat'),
        ],
      );
      expect(_findings(r, SafetyRuleId.h1), isEmpty);
    });

    test('the cue lands on the last on-heat step handling the protein', () {
      final r = _recipe(
        steps: [
          _step('Brown the chicken thighs', adds: ['chicken thigh']),
          _step('Add the stock'),
          _step('Simmer the chicken thighs until done', adds: ['chicken thigh']),
          _step('Scatter parsley', heat: 'off_heat'),
        ],
      );
      expect(donenessStepsFor(r).keys, [2]);
    });

    test('one animal gets one cue, however many names it is called by', () {
      // Found on real dev output: the model wrote "chicken thighs" in one step
      // and "the chicken" in the next, and the cue landed twice — the second
      // time on a step titled "Add potatoes".
      final r = _recipe(
        steps: [
          _step('Sear chicken thighs', adds: ['chicken thigh']),
          _step('Add potatoes', bullets: ['tuck them around the chicken']),
          _step('Scatter parsley', heat: 'off_heat'),
        ],
      );
      expect(donenessStepsFor(r), hasLength(1));
      expect(donenessStepsFor(r).keys.single, 1);
    });

    test('an oven step counts as cooking even when declared off_heat', () {
      // The model routinely declares oven steps as off_heat — the heat field
      // describes the hob. Without this, H1 skips the step where a roast
      // actually finishes.
      final r = _recipe(
        steps: [
          _step('Sear the chicken thighs', adds: ['chicken thigh']),
          _step('Roast the chicken in the oven', heat: 'off_heat', minutes: 25),
        ],
      );
      expect(donenessStepsFor(r).keys.single, 1);
      expect(applySafetyInjections(r).recipe.steps[1].sensoryCue, 'juices_run_clear');
    });

    test('an off-heat plating step never takes the anchor from a real one', () {
      // Found on real dev output: a two-minute "Finish with Lemon" step whose
      // bullets said "spoon the juices over the roast chicken" contained oven
      // language as a noun, and being last it stole the anchor from the
      // twenty-five minute "Roast Chicken and Potatoes" step.
      final r = _recipe(
        steps: [
          _step('Sear chicken thighs', heat: 'medium_high', minutes: 8),
          _step('Roast chicken and potatoes', heat: 'medium', minutes: 25),
          _step('Finish with lemon',
              heat: 'off_heat',
              minutes: 2,
              bullets: ['spoon the juices over the roast chicken']),
        ],
      );
      expect(donenessStepsFor(r).keys.single, 1);
      expect(applySafetyInjections(r).recipe.steps[1].sensoryCue, 'juices_run_clear');
      expect(applySafetyInjections(r).recipe.steps[2].sensoryCue,
          SensoryCueVocabulary.noCueKey);
    });

    test('an on-heat finishing step is still a valid anchor', () {
      // The exclusion above must not swallow "Finish cooking the pork chops"
      // on medium heat, which is exactly where a doneness cue belongs.
      final r = _recipe(
        steps: [
          _step('Sear the pork chops', heat: 'medium_high', minutes: 8),
          _step('Finish cooking the pork chops', heat: 'medium', minutes: 5),
        ],
      );
      expect(donenessStepsFor(r).keys.single, 1);
    });

    test('two different proteins each get their own verification step', () {
      final r = _recipe(
        steps: [
          _step('Sear the pork loin', adds: ['pork loin']),
          _step('Grill the chicken breast', adds: ['chicken breast']),
        ],
      );
      expect(donenessStepsFor(r).keys.toSet(), {0, 1});
    });
  });

  group('H1 injection — the guarantee', () {
    test('injects the signed cue onto the qualifying step', () {
      final r = _recipe(steps: [_step('Pan-fry the chicken breast')]);
      final out = applySafetyInjections(r);

      expect(out.recipe.steps.single.sensoryCue, 'juices_run_clear');
      expect(out.injections, hasLength(1));
      expect(out.injections.single.rule, SafetyRuleId.h1);
      expect(out.injections.single.replacedCueKey, SensoryCueVocabulary.noCueKey);
      expect(out.injections.single.displacedAnotherCue, isFalse);
    });

    test('is idempotent — an already-correct step is untouched', () {
      final r = _recipe(
        steps: [_step('Pan-fry the chicken breast', cue: 'juices_run_clear')],
      );
      final out = applySafetyInjections(r);

      expect(out.injections, isEmpty, reason: 'nothing to do, nothing recorded');
      expect(out.recipe.steps.single.sensoryCue, 'juices_run_clear');

      // Running it twice more changes nothing.
      final again = applySafetyInjections(applySafetyInjections(out.recipe).recipe);
      expect(again.injections, isEmpty);
      expect(again.recipe.steps.single.sensoryCue, 'juices_run_clear');
    });

    test('displacing a preference cue is recorded, not silent', () {
      final r = _recipe(
        steps: [_step('Pan-fry the chicken breast', cue: 'edges_pulling_away')],
      );
      final out = applySafetyInjections(r);

      expect(out.recipe.steps.single.sensoryCue, 'juices_run_clear');
      expect(out.injections.single.replacedCueKey, 'edges_pulling_away');
      expect(out.injections.single.displacedAnotherCue, isTrue);
    });

    test('leaves every other field of the step and recipe alone', () {
      final r = _recipe(
        title: 'Chicken traybake',
        ingredients: ['chicken thigh', 'potato'],
        steps: [
          _step('Roast the chicken thigh',
              heat: 'medium_high', minutes: 35, bullets: ['skin side up'], adds: ['chicken thigh']),
        ],
      );
      final out = applySafetyInjections(r);
      final s = out.recipe.steps.single;

      expect(out.recipe.title, 'Chicken traybake');
      expect(out.recipe.ingredients, ['chicken thigh', 'potato']);
      expect(s.title, 'Roast the chicken thigh');
      expect(s.heat, 'medium_high');
      expect(s.durationMinutes, 35);
      expect(s.bullets, ['skin side up']);
      expect(s.ingredientsAdded, ['chicken thigh']);
    });

    test('a recipe with no qualifying protein is returned unchanged', () {
      final r = _recipe(steps: [_step('Saute the mushrooms')]);
      final out = applySafetyInjections(r);
      expect(identical(out.recipe, r), isTrue);
      expect(out.injections, isEmpty);
    });
  });

  group('H2 — comminuted meat cooked through', () {
    test('pink language on a mince step is detected', () {
      final r = _recipe(
        steps: [
          _step('Fry the beef mince', bullets: ['leave it slightly pink in the middle']),
        ],
      );
      final f = _findings(r, SafetyRuleId.h2);
      expect(f, isNotEmpty);
      expect(f.first.enforcement, SafetyEnforcement.correctAndRegenerate);
    });

    test('a missing cooked-through instruction is detected once, not per step', () {
      final r = _recipe(
        steps: [
          _step('Brown the beef mince'),
          _step('Stir the mince into the sauce'),
          _step('Simmer the mince gently'),
        ],
      );
      expect(_findings(r, SafetyRuleId.h2), hasLength(1));
    });

    test('a stated cooked-through instruction clears the rule', () {
      final r = _recipe(
        steps: [
          _step('Brown the beef mince', bullets: ['cook it through, no pink left']),
        ],
      );
      expect(_findings(r, SafetyRuleId.h2), isEmpty);
    });

    test('the imperative verb "mince" is not the ingredient', () {
      // Found on real dev output: "Mince the garlic" in a cabbage recipe
      // matched the comminuted-meat vocabulary and burned both H2 retries.
      final r = _recipe(
        title: 'Kimchi-style spiced cabbage',
        ingredients: ['napa cabbage', 'garlic', 'spring onion'],
        steps: [
          _step('Prepare ingredients', heat: 'off_heat', bullets: ['Mince the garlic']),
          _step('Add cabbage', minutes: 6),
        ],
      );
      expect(_findings(r, SafetyRuleId.h2), isEmpty);
      expect(mentionsComminutedMeat('mince the garlic finely'), isFalse);
      expect(mentionsComminutedMeat('finely mince a shallot'), isFalse);
    });

    test('the noun "mince" still matches', () {
      expect(mentionsComminutedMeat('500 g mince'), isTrue);
      expect(mentionsComminutedMeat('add the mince and brown it'), isTrue);
    });

    test('whole-muscle beef is not this rule', () {
      final r = _recipe(
        steps: [_step('Sear the steak', bullets: ['medium-rare is right here'])],
      );
      expect(_findings(r, SafetyRuleId.h2), isEmpty,
          reason: 'whole-muscle beef doneness is preference, per the signed reasoning');
    });
  });

  group('H3 — temperature floor', () {
    test('poultry below 74 is detected', () {
      final r = _recipe(
        steps: [
          _step('Roast the chicken breast',
              bullets: ['until the internal temperature reaches 70°C']),
        ],
      );
      final f = _findings(r, SafetyRuleId.h3);
      expect(f, hasLength(1));
      expect(f.single.detail, contains('74'));
    });

    test('poultry at or above 74 is clean', () {
      final r = _recipe(
        steps: [
          _step('Roast the chicken breast',
              bullets: ['until the internal temperature reaches 75°C']),
        ],
      );
      expect(_findings(r, SafetyRuleId.h3), isEmpty);
    });

    test('an oven temperature is not read as a core temperature', () {
      final r = _recipe(
        steps: [_step('Roast the chicken breast at 180°C for 30 minutes', minutes: 30)],
      );
      expect(_findings(r, SafetyRuleId.h3), isEmpty,
          reason: 'no core-temperature language, so the number is not a core reading');
    });

    test('minced and whole-muscle pork resolve to different signed minimums', () {
      final mince = _recipe(
        steps: [
          _step('Cook the pork mince',
              bullets: ['until the internal temperature reaches 65°C, cooked through']),
        ],
      );
      final chop = _recipe(
        steps: [
          _step('Cook the pork chop',
              bullets: ['until the internal temperature reaches 65°C, then rest for 3 minutes']),
        ],
      );

      final mincedFindings = _findings(mince, SafetyRuleId.h3);
      expect(mincedFindings, hasLength(1),
          reason: '65 is below the signed 71 for comminuted meat');
      expect(mincedFindings.single.detail, contains('71'));

      expect(_findings(chop, SafetyRuleId.h3), isEmpty,
          reason: '65 clears the signed 63 for whole-muscle pork, and the rest is stated');
    });

    test('pork at temperature but with no rest is not the signed condition', () {
      final r = _recipe(
        steps: [
          _step('Cook the pork loin',
              bullets: ['until the internal temperature reaches 63°C, then serve']),
        ],
      );
      final f = _findings(r, SafetyRuleId.h3);
      expect(f, hasLength(1));
      expect(f.single.detail, contains('rest'));
      expect(f.single.detail, contains('3-minute'));
    });

    test('poultry mince takes the higher of its two signed minimums', () {
      final classes = proteinClassesIn('chicken mince');
      expect(classes, containsAll([ProteinClass.poultry, ProteinClass.mincedOrSausage]));
      expect(governingProteinClass(classes), ProteinClass.poultry);
      expect(governingProteinClass(classes)!.minimumCelsius, 74);
    });

    test('fish below 63 is detected', () {
      final r = _recipe(
        steps: [
          _step('Bake the salmon', bullets: ['until the core temperature reaches 55°C']),
        ],
      );
      expect(_findings(r, SafetyRuleId.h3), hasLength(1));
    });
  });

  group('H4 — marinade that touched raw meat', () {
    test('serving the reserved marinade unboiled is detected', () {
      final r = _recipe(
        ingredients: ['chicken thigh', 'soy marinade'],
        steps: [
          _step('Marinate the chicken thigh', heat: 'off_heat'),
          _step('Grill the chicken thigh'),
          _step('Drizzle the reserved marinade over to serve', heat: 'off_heat'),
        ],
      );
      expect(_findings(r, SafetyRuleId.h4), hasLength(1));
    });

    test('boiling the marinade first clears the rule', () {
      final r = _recipe(
        ingredients: ['chicken thigh', 'soy marinade'],
        steps: [
          _step('Marinate the chicken thigh', heat: 'off_heat'),
          _step('Bring the reserved marinade to a boil, then drizzle over to serve'),
        ],
      );
      expect(_findings(r, SafetyRuleId.h4), isEmpty);
    });

    test('a marinade with no meat in the recipe is not this rule', () {
      final r = _recipe(
        ingredients: ['halloumi', 'herb marinade'],
        steps: [_step('Drizzle the reserved marinade over to serve', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h4), isEmpty);
    });
  });

  group('H5 — cooked rice and grains', () {
    test('leaving cooked rice at room temperature is detected', () {
      final r = _recipe(
        steps: [_step('Leave the rice at room temperature until needed', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h5), hasLength(1));
    });

    test('chilling it promptly clears the rule', () {
      final r = _recipe(
        steps: [_step('Spread the rice out to cool, then chill in the fridge', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h5), isEmpty);
    });

    test('leftover rice reheated without a piping-hot instruction is detected', () {
      final r = _recipe(
        steps: [_step('Stir-fry the leftover rice for two minutes', minutes: 2)],
      );
      expect(_findings(r, SafetyRuleId.h5), hasLength(1));
    });

    test('leftover-ness is read from the recipe, not just the sentence', () {
      // Found on real dev output: the ingredient list said "leftover cooked
      // rice" and every step then said only "rice".
      final r = _recipe(
        title: 'Quick egg fried rice',
        ingredients: ['leftover cooked rice', 'eggs', 'peas'],
        steps: [
          _step('Heat the pan and oil', minutes: 2),
          _step('Add rice and peas', minutes: 5),
        ],
      );
      final f = _findings(r, SafetyRuleId.h5);
      expect(f, hasLength(1), reason: 'one flag per recipe, not one per step');
      expect(f.single.subject, 'leftover rice');
    });

    test('a piping-hot instruction clears it', () {
      final r = _recipe(
        steps: [
          _step('Stir-fry the leftover rice until piping hot all the way through', minutes: 4),
        ],
      );
      expect(_findings(r, SafetyRuleId.h5), isEmpty);
    });
  });

  group('H6 — danger zone, signed limit 2 hours', () {
    test('the signed limit is 120 minutes and appears once', () {
      expect(kDangerZoneLimitMinutes, 120);
    });

    test('holding perishable food beyond the limit is detected', () {
      final r = _recipe(
        ingredients: ['chicken breast'],
        steps: [_step('Leave the cooked chicken to sit for 4 hours', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h6), hasLength(1));
    });

    test('a normal rest is not flagged', () {
      final r = _recipe(
        ingredients: ['chicken breast'],
        steps: [_step('Leave the chicken to rest for 10 minutes', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h6), isEmpty);
    });

    test('overnight out of the fridge is detected', () {
      final r = _recipe(
        ingredients: ['pork loin'],
        steps: [_step('Leave the pork to sit overnight', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h6), hasLength(1));
    });

    test('overnight in the fridge is fine', () {
      final r = _recipe(
        ingredients: ['pork loin'],
        steps: [_step('Leave the pork to marinate overnight in the fridge', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h6), isEmpty);
    });
  });

  group('H7 — no partial cooking of protein', () {
    test('par-cooking chicken to finish later is detected', () {
      final r = _recipe(
        steps: [_step('Par-cook the chicken breast and finish later')],
      );
      expect(_findings(r, SafetyRuleId.h7), hasLength(1));
    });

    test('par-cooking vegetables is fine', () {
      final r = _recipe(steps: [_step('Par-cook the potatoes and set aside')]);
      expect(_findings(r, SafetyRuleId.h7), isEmpty);
    });
  });

  group('H8 — raw egg preparations', () {
    test('a named raw-egg dish without a safeguard is detected', () {
      final r = _recipe(
        title: 'Quick tiramisu',
        ingredients: ['eggs', 'mascarpone'],
        steps: [_step('Whisk the eggs and mascarpone', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h8), hasLength(1));
    });

    test('pasteurised eggs clear the rule', () {
      final r = _recipe(
        title: 'Quick tiramisu',
        ingredients: ['pasteurised eggs', 'mascarpone'],
        steps: [_step('Whisk the pasteurised eggs and mascarpone', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h8), isEmpty);
    });

    test('an egg that is actually cooked is not this rule', () {
      final r = _recipe(
        ingredients: ['eggs'],
        steps: [_step('Fry the eggs until the white is set')],
      );
      expect(_findings(r, SafetyRuleId.h8), isEmpty);
    });
  });

  group('H9 — raw fish fit for raw consumption', () {
    test('ceviche without a sourcing instruction is detected', () {
      final r = _recipe(
        title: 'Sea bass ceviche',
        ingredients: ['sea bass', 'lime'],
        steps: [_step('Cure the sea bass in lime juice', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h9), hasLength(1));
    });

    test('a previously-frozen instruction clears it', () {
      final r = _recipe(
        title: 'Sea bass ceviche',
        ingredients: ['sushi-grade sea bass', 'lime'],
        steps: [_step('Cure the sushi-grade sea bass in lime juice', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h9), isEmpty);
    });

    test('beef tartare is not a fish rule', () {
      final r = _recipe(
        title: 'Steak tartare',
        ingredients: ['beef fillet'],
        steps: [_step('Chop the beef finely', heat: 'off_heat')],
      );
      expect(_findings(r, SafetyRuleId.h9), isEmpty);
    });
  });

  group('H10 — stuffed and rolled', () {
    test('stuffed poultry rides the H1 injection path', () {
      final r = _recipe(
        steps: [_step('Roast the stuffed chicken breast')],
      );
      final f = _findings(r, SafetyRuleId.h10);
      expect(f, hasLength(1));
      expect(f.single.enforcement, SafetyEnforcement.inject);
      expect(applySafetyInjections(r).recipe.steps.single.sensoryCue, 'juices_run_clear');
    });

    test('stuffed non-poultry meat is log-only, with no invented wording', () {
      final r = _recipe(
        steps: [_step('Roll and tie the stuffed beef roulade')],
      );
      final f = _findings(r, SafetyRuleId.h10);
      expect(f, hasLength(1));
      expect(f.single.enforcement, SafetyEnforcement.logOnly);
      expect(f.single.isCorrectable, isFalse);
    });

    test('an unstuffed chicken breast is not this rule', () {
      final r = _recipe(steps: [_step('Pan-fry the chicken breast')]);
      expect(_findings(r, SafetyRuleId.h10), isEmpty);
    });
  });

  group('H11 — leftovers reheated piping hot', () {
    test('a gentle reheat is detected', () {
      final r = _recipe(
        ingredients: ['cooked chicken'],
        steps: [_step('Reheat the leftovers gently until warm')],
      );
      expect(_findings(r, SafetyRuleId.h11), hasLength(1));
    });

    test('piping hot throughout clears it', () {
      final r = _recipe(
        ingredients: ['cooked chicken'],
        steps: [_step('Reheat the leftovers until piping hot all the way through')],
      );
      expect(_findings(r, SafetyRuleId.h11), isEmpty);
    });
  });

  group('H12 — fermentation, detection and logging only', () {
    test('kimchi is detected and is log-only', () {
      final r = _recipe(
        title: 'Quick kimchi',
        steps: [_step('Leave the kimchi to ferment for three days', heat: 'off_heat')],
      );
      final f = _findings(r, SafetyRuleId.h12);
      expect(f, hasLength(1));
      expect(f.single.enforcement, SafetyEnforcement.logOnly);
      expect(f.single.isCorrectable, isFalse,
          reason: 'the signed entry defines no on-flag action, so nothing is corrected');
    });

    test('every named bread carve-out term is exempt', () {
      for (final term in kFermentationBreadCarveOutDraft) {
        final r = _recipe(
          title: 'Bread test',
          steps: [_step('Let the $term ferment overnight', heat: 'off_heat')],
        );
        expect(_findings(r, SafetyRuleId.h12), isEmpty,
            reason: '"$term" is on the bread carve-out list');
      }
    });

    test('an ordinary recipe is not flagged', () {
      final r = _recipe(steps: [_step('Saute the onion')]);
      expect(_findings(r, SafetyRuleId.h12), isEmpty);
    });
  });

  group('the someday list stays out of the validator', () {
    test('there are exactly twelve rule ids, H1 to H12', () {
      expect(SafetyRuleId.values, hasLength(12));
      expect(SafetyRuleId.values.map((r) => r.label).toList(), [
        'H1', 'H2', 'H3', 'H4', 'H5', 'H6',
        'H7', 'H8', 'H9', 'H10', 'H11', 'H12',
      ]);
    });

    test('no source file mentions an inactive hazard', () {
      // S1 shellfish, S2 raw flour and dough, S3 sprouts. The registry is
      // explicit: "These three must not reach the validator." A half-built
      // rule would show up here as a source-level mention long before it
      // showed up as a finding.
      const forbidden = [
        'shellfish',
        'mussel',
        'clam',
        'oyster',
        'raw flour',
        'raw dough',
        'sprout',
      ];
      // Comments are stripped first. Both files deliberately *name* the
      // someday list in prose to explain why it is absent, and that prose is
      // the opposite of the failure being guarded against. What must stay
      // clean is executable code: a trigger list, a rule id, a match term.
      for (final path in [
        'lib/services/safety_validator.dart',
        'lib/data/safety_ingredient_names.dart',
      ]) {
        final code = File(path)
            .readAsLinesSync()
            .map((line) {
              final trimmed = line.trimLeft();
              if (trimmed.startsWith('//')) return '';
              final inline = line.indexOf('//');
              return inline == -1 ? line : line.substring(0, inline);
            })
            .join('\n')
            .toLowerCase();

        for (final word in forbidden) {
          expect(code.contains(word), isFalse,
              reason: '$path has executable code mentioning the INACTIVE '
                  'hazard term "$word"');
        }
      }
    });

    test('a shellfish recipe produces no findings of its own', () {
      final r = _recipe(
        title: 'Mussels in white wine',
        ingredients: ['mussels', 'white wine'],
        steps: [_step('Steam the mussels until they open', minutes: 6)],
      );
      expect(validateRecipeSafety(r).findings, isEmpty);
    });
  });

  group('the closed name list', () {
    test('covers whole-muscle, minced and dish-name forms', () {
      expect(mentionsPoultryOrPork('diced chicken thigh'), isTrue);
      expect(mentionsPoultryOrPork('chicken thighs'), isTrue, reason: 'plural');
      expect(mentionsPoultryOrPork('ground turkey'), isTrue);
      expect(mentionsPoultryOrPork('two pork chops'), isTrue);
      expect(mentionsPoultryOrPork('a tray of bratwurst'), isTrue);
      expect(mentionsComminutedMeat('spaghetti bolognese'), isTrue,
          reason: 'dish-name form');
      expect(mentionsComminutedMeat('lamb kofta'), isTrue);
      expect(mentionsComminutedMeat('beef burgers'), isTrue);
    });

    test('matching is whole-word, so it does not fire on substrings', () {
      expect(matchSafetyNames('cooked until soft'), isEmpty,
          reason: '"cod" must not match inside "cooked"');
      expect(matchSafetyNames('a handful of chives'), isEmpty);
      expect(mentionsPoultryOrPork('porkless vegan stew'), isFalse);
    });

    test('cured ready-to-eat entries are pork but do not qualify for H1', () {
      final bacon = kCuredReadyToEatDraft.firstWhere((n) => n.term == 'bacon');
      expect(bacon.pork, isTrue);
      expect(bacon.curedReadyToEat, isTrue);
      expect(bacon.qualifiesForDonenessRule, isFalse);
    });

    test('the signed H3 temperatures are the only numbers in the class table', () {
      expect(ProteinClass.poultry.minimumCelsius, 74);
      expect(ProteinClass.mincedOrSausage.minimumCelsius, 71);
      expect(ProteinClass.porkWholeMuscle.minimumCelsius, 63);
      expect(ProteinClass.fish.minimumCelsius, 63);
      expect(ProteinClass.porkWholeMuscle.requiresStatedRest, isTrue);
      expect(ProteinClass.porkWholeMuscle.restMinutes, 3);
      expect(ProteinClass.poultry.requiresStatedRest, isFalse);
    });
  });

  group('report shape', () {
    test('a finding serialises flat, with no nested objects', () {
      final r = _recipe(steps: [_step('Sear the chicken breast')]);
      final json = validateRecipeSafety(r).toJson();

      expect(json['findings'], isA<List<dynamic>>());
      expect(json['steps_checked'], 1);
      final first = (json['findings'] as List).first as Map<String, dynamic>;
      expect(first['rule'], 'H1');
      expect(first['enforcement'], 'inject');
      expect(first.values.every((v) => v is String || v is num || v is bool), isTrue);
    });

    test('an injection serialises with its replaced cue', () {
      final r = _recipe(
        steps: [_step('Sear the chicken breast', cue: 'edges_pulling_away')],
      );
      final out = applySafetyInjections(r);
      final json = out.injections.single.toJson();

      expect(json['rule'], 'H1');
      expect(json['cue'], 'juices_run_clear');
      expect(json['replaced_cue'], 'edges_pulling_away');
      expect(json['displaced_another_cue'], isTrue);
    });

    test('the correction note carries only correctable findings', () {
      final r = _recipe(
        title: 'Kimchi and mince',
        steps: [
          _step('Brown the beef mince'),
          _step('Leave the kimchi to ferment', heat: 'off_heat'),
        ],
      );
      final report = validateRecipeSafety(r);
      final note = report.buildCorrectionNote();

      expect(report.findings.any((f) => f.rule == SafetyRuleId.h12), isTrue);
      expect(note, contains('[H2]'));
      expect(note, isNot(contains('[H12]')),
          reason: 'a log-only rule never reaches the model');
      expect(note, contains('FOOD SAFETY CORRECTION REQUIRED'));
    });

    test('a clean report builds no note', () {
      final r = _recipe(steps: [_step('Saute the courgette')]);
      final report = validateRecipeSafety(r);
      expect(report.isClean, isTrue);
      expect(report.buildCorrectionNote(), isEmpty);
      expect(report.hasCorrectable, isFalse);
    });
  });

  group('whole-word matching (the prefix bug)', () {
    // _hasAny matched on a word PREFIX until 2026-08-23, so "rarely" tripped
    // H2's "rare" and "pinkish" tripped "pink". Both are false positives that
    // spend a correction retry and teach the model to write defensively.
    test('"rarely" does not fire the rare-doneness trigger', () {
      final r = _recipe(
        steps: [
          _step('Brown the beef mince',
              bullets: ['this rarely takes longer than eight minutes', 'cooked through']),
        ],
      );
      expect(_findings(r, SafetyRuleId.h2), isEmpty);
    });

    test('"pinkish" does not fire the pink trigger', () {
      final r = _recipe(
        steps: [
          _step('Brown the beef mince',
              bullets: ['the shallots turn pinkish at the edges', 'cooked through']),
        ],
      );
      expect(_findings(r, SafetyRuleId.h2), isEmpty);
    });

    test('"serve rare" still fires', () {
      final r = _recipe(
        steps: [_step('Cook the beef mince', bullets: ['serve rare'])],
      );
      expect(_findings(r, SafetyRuleId.h2), isNotEmpty);
    });

    test('"cook until no longer pink" clears the rule', () {
      final r = _recipe(
        steps: [_step('Cook the beef mince', bullets: ['cook until no longer pink'])],
      );
      expect(_findings(r, SafetyRuleId.h2), isEmpty);
    });

    test('"Mince the garlic" stays a non-match (regression)', () {
      expect(mentionsComminutedMeat('mince the garlic'), isFalse);
      expect(mentionsComminutedMeat('500 g mince'), isTrue);
    });

    test('inflected exclusion words still match, so exclusions keep working', () {
      // "chill" lives in an EXCLUSION list. If whole-word matching stopped it
      // covering "chilled"/"chilling", H5 and H6 would start firing on
      // correctly-refrigerated recipes.
      final r = _recipe(
        steps: [
          _step('Cool the rice quickly, then keep it chilled', heat: 'off_heat'),
        ],
      );
      expect(_findings(r, SafetyRuleId.h5), isEmpty);
    });
  });

  group('compound and veggie exclusions', () {
    test('chicken stock is not chicken', () {
      final r = _recipe(
        title: 'Mushroom risotto',
        ingredients: ['arborio rice', 'chicken stock', 'mushrooms'],
        steps: [
          _step('Toast the rice', minutes: 2),
          _step('Add the chicken stock a ladle at a time', minutes: 18),
        ],
      );
      expect(_findings(r, SafetyRuleId.h1), isEmpty);
      expect(applySafetyInjections(r).injections, isEmpty);
    });

    test('real chicken plus chicken stock still gets exactly one injection', () {
      final r = _recipe(
        ingredients: ['chicken thighs', 'chicken stock'],
        steps: [
          _step('Sear the chicken thighs', minutes: 8),
          _step('Add the chicken stock and simmer the chicken thighs', minutes: 20),
        ],
      );
      final out = applySafetyInjections(r);
      expect(out.injections, hasLength(1));
      expect(out.injections.single.stepIndex, 1,
          reason: 'the last step that actually cooks the chicken');
    });

    test('fish sauce is not fish', () {
      expect(matchSafetyNames('a splash of fish sauce').where((n) => n.fish), isEmpty);
      expect(matchSafetyNames('a fillet of fish').where((n) => n.fish), isNotEmpty);
    });

    test('other compound forms are excluded', () {
      for (final s in [
        'chicken broth',
        'chicken bouillon',
        'beef gravy',
        'duck fat',
        'chicken seasoning',
        'pork powder',
        'chicken-flavoured crisps',
      ]) {
        expect(mentionsPoultryOrPork(s), isFalse, reason: s);
      }
    });

    test('veggie products are not comminuted meat', () {
      for (final s in [
        'bean burger',
        'vegan sausage',
        'lentil patty',
        'mushroom meatball',
        'vegan black bean burger',
        'plant-based burger',
      ]) {
        expect(mentionsComminutedMeat(s), isFalse, reason: s);
      }
    });

    test('a bean burger raises no H2, a beef burger does', () {
      final veggie = _recipe(
        title: 'Bean burgers',
        ingredients: ['black beans', 'breadcrumbs'],
        steps: [_step('Fry the bean burgers', minutes: 8)],
      );
      expect(_findings(veggie, SafetyRuleId.h2), isEmpty);

      final beef = _recipe(
        title: 'Beef burgers',
        ingredients: ['beef mince'],
        steps: [_step('Fry the beef burgers', minutes: 8)],
      );
      expect(_findings(beef, SafetyRuleId.h2), isNotEmpty);
    });
  });

  group('name list ratification (2026-08-23)', () {
    test('no term is listed twice', () {
      final seen = <String>{};
      final dupes = <String>[];
      for (final n in kSafetyIngredientNamesDraft) {
        if (!seen.add(n.term)) dupes.add(n.term);
      }
      expect(dupes, isEmpty, reason: 'duplicate vocabulary terms: $dupes');
    });

    test('the Swiss and German additions resolve as signed', () {
      expect(mentionsPoultryOrPork('poulet'), isTrue);
      expect(mentionsPoultryOrPork('pouletbrust'), isTrue);
      expect(mentionsPoultryOrPork('güggeli'), isTrue);
      expect(mentionsPoultryOrPork('cordon bleu'), isTrue);
      expect(mentionsPoultryOrPork('geschnetzeltes'), isTrue);
      expect(mentionsComminutedMeat('hackbraten'), isTrue);
      expect(mentionsComminutedMeat('fleischkäse'), isTrue);

      // Unqualified Schnitzel is signed to the poultry 74 °C floor.
      expect(governingProteinClass(proteinClassesIn('schnitzel')),
          ProteinClass.poultry);
    });

    test('duck whole muscle is exempt from H1', () {
      for (final term in [
        'duck breast',
        'magret',
        'duck leg',
        'duck thigh',
        'whole duck',
        'duck confit',
      ]) {
        expect(mentionsPoultryOrPork(term), isFalse,
            reason: '"$term" is signed exempt — served pink is safe');
      }

      final r = _recipe(
        title: 'Seared duck breast',
        ingredients: ['duck breast'],
        steps: [
          _step('Sear the duck breast skin side down', minutes: 8),
          _step('Rest and serve pink', heat: 'off_heat', minutes: 5),
        ],
      );
      expect(_findings(r, SafetyRuleId.h1), isEmpty);
      expect(_findings(r, SafetyRuleId.h2), isEmpty);
      expect(applySafetyInjections(r).injections, isEmpty,
          reason: 'no cue injection anywhere on a duck recipe');
    });

    test('duck whole muscle is exempt from H3 as well (23 Aug ruling)', () {
      final duck = _recipe(
        title: 'Seared duck breast',
        ingredients: ['duck breast'],
        steps: [
          _step('Sear the duck breast',
              minutes: 8,
              bullets: ['until the internal temperature reaches 57°C']),
        ],
      );
      expect(_findings(duck, SafetyRuleId.h3), isEmpty,
          reason: 'doneness on duck is technique, not hazard');

      // The control: the same sentence on chicken still flags at 74.
      final chicken = _recipe(
        title: 'Seared chicken breast',
        ingredients: ['chicken breast'],
        steps: [
          _step('Sear the chicken breast',
              minutes: 8,
              bullets: ['until the internal temperature reaches 57°C']),
        ],
      );
      final f = _findings(chicken, SafetyRuleId.h3);
      expect(f, hasLength(1));
      expect(f.single.detail, contains('74'));
    });

    test('duck carries no protein class, chicken carries poultry', () {
      expect(proteinClassesIn('duck breast'), isEmpty);
      expect(proteinClassesIn('magret'), isEmpty);
      expect(proteinClassesIn('duck confit'), isEmpty);
      expect(proteinClassesIn('chicken breast'), contains(ProteinClass.poultry));

      // Duck mince keeps BOTH classes and therefore the poultry 74 °C floor,
      // exactly like chicken mince. The exemption is for whole muscle only,
      // and mincing is the thing that changes the hazard — surface becomes
      // interior. Consistent with the signed poultry-mince tie-break.
      expect(proteinClassesIn('duck mince'),
          containsAll([ProteinClass.poultry, ProteinClass.mincedOrSausage]));
      expect(governingProteinClass(proteinClassesIn('duck mince'))!.minimumCelsius,
          74);
    });

    test('duck mince is still comminuted, so still H2', () {
      expect(mentionsComminutedMeat('duck mince'), isTrue);
      final r = _recipe(
        ingredients: ['duck mince'],
        steps: [_step('Brown the duck mince', minutes: 8)],
      );
      expect(_findings(r, SafetyRuleId.h2), isNotEmpty,
          reason: 'comminuted is H2 regardless of species');
    });

    test('the shrimp group sits at the fish floor, and no bivalve does', () {
      for (final term in [
        'shrimp',
        'prawn',
        'king prawn',
        'tiger prawn',
        'crevette',
        'scampi',
        'langoustine',
      ]) {
        final hits = matchSafetyNames(term);
        expect(hits, isNotEmpty, reason: term);
        expect(hits.any((n) => n.fish), isTrue, reason: term);
        expect(governingProteinClass(proteinClassesIn(term))!.minimumCelsius, 63,
            reason: term);
        // Shrimp are not poultry or pork, so H1 never touches them.
        expect(hits.any((n) => n.qualifiesForDonenessRule), isFalse,
            reason: term);
      }

      // S1 bivalves stay INACTIVE.
      for (final term in ['mussel', 'clam', 'oyster', 'scallop']) {
        expect(matchSafetyNames(term), isEmpty,
            reason: '"$term" is S1 and must stay out of the validator');
      }
    });
  });
}
