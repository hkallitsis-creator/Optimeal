import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal, durable record of the most recent Fridge Clearer generation's
/// entered ingredients (device-test round F12/F13). Before this,
/// FridgeClearerScreen's ingredient selection was purely ephemeral UI
/// state — nothing survived once Cook Mode was pushed, so by the time a
/// cook completed there was no way to know what the user had actually
/// entered. Both F12 (the leftover-ingredients nudge) and F13 (the
/// rescued-ingredients provenance rule) independently need exactly this
/// at cook-completion time, so it's one shared, neutral store rather than
/// two services each keeping their own copy.
///
/// Only the single most recent generation is kept — same "one pending at
/// a time" simplification [FridgeNudgeService] already applies to its own
/// scheduling. SharedPreferences-backed, matching this project's existing
/// pattern for small local stores.
class FridgeClearerEntryService {
  static const String _lastEnteredIngredientsKey = 'fridge_clearer_last_entered_ingredients_v1';

  /// Call once, right after a Fridge Clearer recipe generation succeeds.
  Future<void> recordEnteredIngredients(List<String> ingredients) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastEnteredIngredientsKey, jsonEncode(ingredients));
    } catch (e) {
      debugPrint('FridgeClearerEntryService: failed to record entered ingredients: $e');
    }
  }

  /// Reads back the persisted list without clearing it. Empty (not null)
  /// if nothing was ever recorded, already consumed, or the stored value
  /// is malformed — callers treat "nothing entered" and "unknown" the
  /// same way (both mean no ingredient can pass the "entered by the user"
  /// provenance check).
  Future<List<String>> peekEnteredIngredients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastEnteredIngredientsKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList(growable: false);
    } catch (e) {
      debugPrint('FridgeClearerEntryService: failed to read entered ingredients: $e');
      return const [];
    }
  }

  /// Clears the persisted list — call once a cook completion has already
  /// read it via [peekEnteredIngredients], so a later, unrelated
  /// completion doesn't accidentally reuse a stale list.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastEnteredIngredientsKey);
    } catch (e) {
      debugPrint('FridgeClearerEntryService: failed to clear entered ingredients: $e');
    }
  }
}
