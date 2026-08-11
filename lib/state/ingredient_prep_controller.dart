import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared, app-wide state for ingredients the user has already prepped/owns.
///
/// This is intentionally lightweight:
/// - Local persistence via SharedPreferences
/// - Normalized by lowercased, trimmed label
/// - ChangeNotifier so Cook Mode + Weekly Planner can stay in sync live
class IngredientPrepController extends ChangeNotifier {
  static const String _prefsKey = 'prepped_ingredients_v1';

  final Set<String> _prepped = <String>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  UnmodifiableListView<String> get preppedKeys => UnmodifiableListView(_prepped.toList(growable: false));

  static String normalizeKey(String raw) => raw.trim().toLowerCase();

  bool isPrepped(String ingredientLabel) {
    final key = normalizeKey(ingredientLabel);
    if (key.isEmpty) return false;
    return _prepped.contains(key);
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        _loaded = true;
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _prepped
          ..clear()
          ..addAll(decoded.map((e) => normalizeKey(e.toString())).where((e) => e.isNotEmpty));
      }
    } catch (e) {
      debugPrint('IngredientPrepController.load failed: $e');
      _prepped.clear();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> togglePrepped(String ingredientLabel) async {
    final key = normalizeKey(ingredientLabel);
    if (key.isEmpty) return;

    if (_prepped.contains(key)) {
      _prepped.remove(key);
    } else {
      _prepped.add(key);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setPrepped(String ingredientLabel, {required bool value}) async {
    final key = normalizeKey(ingredientLabel);
    if (key.isEmpty) return;

    final changed = value ? _prepped.add(key) : _prepped.remove(key);
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_prepped.toList(growable: false)));
    } catch (e) {
      debugPrint('IngredientPrepController.persist failed: $e');
    }
  }
}
