import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// Identifies which UI surface triggered a [parseChefRecipeJson] call, for
/// logging only — has no effect on parsing behavior.
enum ChefRecipeSurface {
  fridgeClearer,
  customAiRecipeCreator,
  fridgeCountdown,
}

const List<String> _defaultFallbackIngredients = ['Salt', 'Pepper', 'Cooking oil'];
const List<String> _defaultFallbackKitchenGear = ['1 Pan or Pot', 'Knife', 'Spoon/Spatula'];

String _extractJsonObject(String raw) {
  final t = raw.trim();
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return t;
  return t.substring(start, end + 1);
}

String _formatIngredientAmount(double amount) {
  if (amount == amount.roundToDouble()) return amount.toInt().toString();
  return amount.toStringAsFixed(1);
}

List<String> _readCurriculumLessonIds(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final e in raw) {
    final s = e.toString().trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

/// Shared parser for Chef Harris's recipe JSON. Extracted 2026-08-15 from 4
/// independently duplicated `_parseCookModeRecipe` methods (Fridge Clearer,
/// Custom AI Recipe Creator, Fridge Countdown's "Use Tonight", and — until
/// its removal, same day — Weekly Planner's Deal Meal path) — see CLAUDE.md
/// Roadmap item 15, which this is the choke point for: a future
/// safety-validation step will wrap this call. Only 3 surfaces remain live.
///
/// [useGenericFallbacks], [fallbackTitle], and [readDescription] preserve
/// each surface's pre-refactor behavior exactly — see each call site for its
/// value and CLAUDE.md for the reasoning behind each. In particular
/// [readDescription] is deliberately `false` for Fridge Countdown even
/// though its own prompt requests a description — do not flip this without
/// checking CLAUDE.md first (blocked on Confidence Climb live-testing, since
/// description text feeds curriculum keyword matching, which feeds
/// Confidence Climb's rep-counting).
///
/// Marked `async` — today's body is fully synchronous, but a future
/// validation step (model-review call) will need to await inside here
/// without changing every call site's signature again.
Future<CookModeRecipePayload?> parseChefRecipeJson({
  required String raw,
  required int portions,
  required String fallbackTitle,
  required ChefRecipeSurface surface,
  bool useGenericFallbacks = true,
  bool readDescription = false,
}) async {
  try {
    final decoded = jsonDecode(_extractJsonObject(raw));
    if (decoded is! Map<String, dynamic>) return null;

    final curriculumLessonIds = _readCurriculumLessonIds(decoded['curriculum_lesson_ids']);

    final title = (decoded['title'] ?? '').toString().trim();
    final description = readDescription ? (decoded['description'] ?? '').toString().trim() : '';

    final ingredients = <String>[];
    final structuredIngredients = <RecipeIngredient>[];
    final ingRaw = decoded['ingredients'];
    if (ingRaw is List) {
      for (final e in ingRaw) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          final name = (m['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final amount = (m['amount'] is num)
              ? (m['amount'] as num).toDouble()
              : double.tryParse('${m['amount'] ?? ''}'.trim()) ?? 0;
          final unit = (m['unit'] ?? '').toString().trim();
          structuredIngredients.add(RecipeIngredient(name: name, amount: amount, unit: unit.isEmpty ? 'piece' : unit));
          final formatted = amount > 0 ? '${_formatIngredientAmount(amount)}${unit.isEmpty ? '' : ' $unit'} $name'.trim() : name;
          ingredients.add(formatted);
        } else {
          // Back-compat: some cached/older responses may still be plain strings.
          final s = e.toString().trim();
          if (s.isNotEmpty) ingredients.add(s);
        }
      }
    }

    final gear = <String>[];
    final gearRaw = decoded['kitchen_gear'];
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
        final duration = int.tryParse('${s['duration_minutes'] ?? ''}'.trim()) ?? 0;
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
        steps.add(CookModeStepPayload(title: stepTitle, heat: heat, durationMinutes: duration, bullets: bullets));
      }
    }

    if (steps.isEmpty) return null;

    debugPrint(
      'parseChefRecipeJson[$surface]: parsed "${title.isEmpty ? fallbackTitle : title}" '
      '(${ingredients.length} ingredients, ${steps.length} steps)',
    );

    return CookModeRecipePayload(
      title: title.isEmpty ? fallbackTitle : title,
      description: description.isEmpty ? null : description,
      ingredients: (ingredients.isEmpty && useGenericFallbacks) ? _defaultFallbackIngredients : ingredients,
      steps: steps,
      kitchenGear: (gear.isEmpty && useGenericFallbacks) ? _defaultFallbackKitchenGear : gear,
      structuredIngredients: structuredIngredients.isEmpty ? null : structuredIngredients,
      basePortions: portions,
      curriculumLessonIds: curriculumLessonIds,
    );
  } catch (e) {
    debugPrint('parseChefRecipeJson[$surface]: failed to parse JSON: $e');
    return null;
  }
}
