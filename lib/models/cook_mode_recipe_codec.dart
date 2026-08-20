import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:optimeal/data/diagram_keys.dart';
import 'package:optimeal/data/sensory_cue_vocabulary.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/models/recipe_origin.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// The canonical snake_case (de)serializer for a [CookModeRecipePayload].
///
/// This is the shape a recipe takes whenever it is stored in Postgres as
/// jsonb — `user_meal_plans.recipe_payload` today, `saved_recipes.recipe_payload`
/// as of the saved-recipes build. Lifted verbatim out of
/// `weekly_planner_screen.dart` (where it was `_cookModePayloadToJson` /
/// `_cookModePayloadFromJson`) so both callers share one implementation
/// rather than drifting apart; the decode side keeps all of that original's
/// tolerance — camelCase key fallbacks, per-field defaults, and a null return
/// when there are no usable steps.
///
/// Note this is deliberately NOT the same codec as
/// `CookSessionStorageService`'s private camelCase one. That store already
/// holds real on-device data in its own key shape; unifying them would
/// silently drop every user's saved session and cook history.

Map<String, dynamic> cookModeRecipeToJson(CookModeRecipePayload payload) => {
      'title': payload.title,
      'ingredients': payload.ingredients,
      'kitchen_gear': payload.kitchenGear,
      'steps': payload.steps
          .map((s) => {
                'title': s.title,
                'heat': s.heat,
                'duration_minutes': s.durationMinutes,
                'bullets': s.bullets,
                'ingredients_added': s.ingredientsAdded,
                'sensory_cue': s.sensoryCue,
                'technique_diagram_id': s.techniqueDiagramId,
              })
          .toList(growable: false),
      'description': payload.description,
      'structured_ingredients':
          payload.structuredIngredients?.map((i) => i.toJson()).toList(),
      'base_portions': payload.basePortions,
      'curriculum_lesson_ids': payload.curriculumLessonIds,
      // Provenance — see RecipeOrigin. Written as the bare enum name so a row
      // round-trips through jsonb unchanged. Absent on rows written before this
      // field existed, which decode to a null origin (= not rescue-eligible).
      'origin': payload.origin?.name,
      'origin_entered_ingredients': payload.originEnteredIngredients,
    };

CookModeRecipePayload? cookModeRecipeFromJson(dynamic raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) return null;
    final title = (decoded['title'] ?? '').toString().trim();

    final ingredients = <String>[];
    final ingRaw = decoded['ingredients'];
    if (ingRaw is List) {
      for (final e in ingRaw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) ingredients.add(s);
      }
    }

    final gear = <String>[];
    final gearRaw = decoded['kitchen_gear'] ?? decoded['kitchenGear'];
    if (gearRaw is List) {
      for (final e in gearRaw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) gear.add(s);
      }
    }

    final steps = <CookModeStepPayload>[];
    final stepsRaw = decoded['steps'];
    if (stepsRaw is List) {
      for (final s in stepsRaw) {
        if (s is! Map) continue;
        final stepTitle = (s['title'] ?? '').toString().trim();
        if (stepTitle.isEmpty) continue;
        final duration = int.tryParse(
                '${s['duration_minutes'] ?? s['durationMinutes'] ?? ''}'
                    .trim()) ??
            0;
        final heat = (s['heat'] ?? 'medium').toString().trim();
        final bullets = <String>[];
        final bulletsRaw = s['bullets'];
        if (bulletsRaw is List) {
          for (final b in bulletsRaw) {
            final blt = b.toString().trim();
            if (blt.isNotEmpty) bullets.add(blt);
          }
        }
        if (bullets.isEmpty) bullets.add('Keep going and taste as you go.');
        final ingredientsAddedRaw =
            s['ingredients_added'] ?? s['ingredientsAdded'];
        final ingredientsAdded = ingredientsAddedRaw is List
            ? ingredientsAddedRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : null;
        final sensoryCueRaw = s['sensory_cue'] ?? s['sensoryCue'];
        final sensoryCue = SensoryCueVocabulary.allKeys.contains(sensoryCueRaw)
            ? sensoryCueRaw as String
            : SensoryCueVocabulary.noCueKey;
        final techniqueDiagramIdRaw =
            s['technique_diagram_id'] ?? s['techniqueDiagramId'];
        final techniqueDiagramId =
            allTechniqueDiagramKeys.contains(techniqueDiagramIdRaw)
                ? techniqueDiagramIdRaw as String
                : noTechniqueDiagramKey;
        steps.add(CookModeStepPayload(
          title: stepTitle,
          heat: heat,
          durationMinutes: duration,
          bullets: bullets,
          ingredientsAdded:
              (ingredientsAdded?.isEmpty ?? true) ? null : ingredientsAdded,
          sensoryCue: sensoryCue,
          techniqueDiagramId: techniqueDiagramId,
        ));
      }
    }

    if (steps.isEmpty) return null;

    final structuredRaw =
        decoded['structured_ingredients'] ?? decoded['structuredIngredients'];
    final structuredIngredients = structuredRaw is List
        ? structuredRaw
            .whereType<Map>()
            .map((e) => RecipeIngredient.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : null;

    final curriculumRaw =
        decoded['curriculum_lesson_ids'] ?? decoded['curriculumLessonIds'];
    final curriculumLessonIds = curriculumRaw is List
        ? curriculumRaw.map((e) => e.toString()).toList(growable: false)
        : null;

    final enteredRaw = decoded['origin_entered_ingredients'] ??
        decoded['originEnteredIngredients'];
    final originEnteredIngredients = enteredRaw is List
        ? enteredRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : null;

    return CookModeRecipePayload(
      title: title.isEmpty ? 'Planned meal' : title,
      ingredients: ingredients.isEmpty
          ? const ['Salt', 'Pepper', 'Cooking oil']
          : ingredients,
      steps: steps,
      kitchenGear: gear.isEmpty
          ? const ['1 Pan or Pot', 'Knife', 'Spoon/Spatula']
          : gear,
      description: (decoded['description'] as String?)?.trim(),
      structuredIngredients: (structuredIngredients?.isEmpty ?? true)
          ? null
          : structuredIngredients,
      basePortions: int.tryParse(
          '${decoded['base_portions'] ?? decoded['basePortions'] ?? ''}'
              .trim()),
      curriculumLessonIds: curriculumLessonIds,
      origin: RecipeOrigin.fromName(decoded['origin']),
      originEnteredIngredients: (originEnteredIngredients?.isEmpty ?? true)
          ? null
          : originEnteredIngredients,
    );
  } catch (e) {
    debugPrint('cookModeRecipeFromJson: failed to decode CookMode payload: $e');
    return null;
  }
}
