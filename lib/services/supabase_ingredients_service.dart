import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/models/ingredient.dart';

class SupabaseIngredientsService {
  SupabaseClient get _db => Supabase.instance.client;

  /// Fetch ingredients from the `ingredients` table.
  ///
  /// Expected columns (recommended):
  /// - id (uuid/text)
  /// - name (text)
  /// - category (text, nullable)
  /// - badge (text, nullable)
  /// - prep_tip (text, nullable)  // preferred
  /// - pinch_tip (text, nullable) // legacy/supported
  /// - created_at (timestamptz)
  /// - updated_at (timestamptz)
  Future<List<Ingredient>> fetchIngredients({
    String? query,
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var req = _db.from('ingredients').select();

      final q = query?.trim();
      if (q != null && q.isNotEmpty) {
        // Basic, portable search. For better UX later:
        // - add pg_trgm + ILIKE, or
        // - use a dedicated search function.
        req = req.ilike('name', '%$q%');
      }

      final c = category?.trim();
      if (c != null && c.isNotEmpty) {
        // Case-insensitive category match.
        // Using ILIKE without wildcards behaves like: lower(category) = lower(c)
        // which is what we want for category pills.
        req = req.ilike('category', c);
      }

      final rows = await req.order('name', ascending: true).range(offset, offset + limit - 1);
      if (rows is! List) return const [];

      final List<Ingredient> out = [];
      for (final r in rows) {
        try {
          if (r is Map<String, dynamic>) out.add(Ingredient.fromJson(r));
        } catch (e) {
          debugPrint('Skipping invalid ingredient row: $e');
        }
      }
      return out;
    } catch (e) {
      debugPrint('Failed to fetch ingredients: $e');
      return const [];
    }
  }

  Future<Ingredient?> fetchIngredientById(String id) async {
    try {
      final row = await _db.from('ingredients').select().eq('id', id).maybeSingle();
      if (row == null || row is! Map<String, dynamic>) return null;
      return Ingredient.fromJson(row);
    } catch (e) {
      debugPrint('Failed to fetch ingredient by id=$id: $e');
      return null;
    }
  }
}
