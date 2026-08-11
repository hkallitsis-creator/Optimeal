import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Feature keys used as `api_usage_daily.feature` values. Keep these in
/// sync with the callers that increment/check them.
class UsageFeature {
  static const chefHarrisChat = 'chef_harris_chat';
  static const fridgeClearerGeneration = 'fridge_clearer_generation';
  static const customAiRecipeCreator = 'custom_ai_recipe_creator';
}

/// Shared usage-counter service backed by the `api_usage_daily` Supabase
/// table. One mechanism for two purposes: AI-cost rate limiting AND
/// paywall usage-cap gating both read/write through here — see CLAUDE.md
/// "Monetization / paywall tier structure".
///
/// Requires the api_usage_daily migration
/// (supabase/migrations/20260810120000_create_api_usage_daily.sql) to be
/// applied manually via the Supabase Dashboard SQL editor first.
class UsageCapService {
  UsageCapService._();
  static final UsageCapService instance = UsageCapService._();

  SupabaseClient get _db => Supabase.instance.client;

  String _formatDate(DateTime d) {
    final utc = DateTime(d.year, d.month, d.day);
    return utc.toIso8601String().split('T').first;
  }

  /// Increments today's usage count for [feature] by one. Fails open (logs
  /// and returns without throwing) on error, since a transient network/DB
  /// issue should never block the underlying AI call from firing.
  Future<void> increment(String feature) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return;
      await _db.rpc('increment_api_usage', params: {'p_feature': feature});
    } catch (e) {
      debugPrint('UsageCapService.increment($feature) failed (continuing): $e');
    }
  }

  /// Sum of [feature]'s usage count across all rows on/after [sinceDate]
  /// (date-only comparison, inclusive). Pass null for lifetime usage.
  /// Fails open — returns 0 on error rather than blocking the caller, so a
  /// transient failure here never locks a user out of a feature they're
  /// otherwise entitled to.
  Future<int> getUsageCount(String feature, {DateTime? sinceDate}) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return 0;

      var query = _db.from('api_usage_daily').select('count').eq('user_id', user.id).eq('feature', feature);
      if (sinceDate != null) {
        query = query.gte('usage_date', _formatDate(sinceDate));
      }
      final rows = await query;
      return (rows as List).fold<int>(0, (sum, row) => sum + (((row as Map)['count'] as num?)?.toInt() ?? 0));
    } catch (e) {
      debugPrint('UsageCapService.getUsageCount($feature) failed (returning 0): $e');
      return 0;
    }
  }

  /// Convenience: today's count for [feature] — use for daily caps.
  Future<int> getTodayCount(String feature) => getUsageCount(feature, sinceDate: DateTime.now());

  /// Convenience: count over the trailing 7 days (inclusive of today) for
  /// [feature] — use for weekly caps.
  Future<int> getRollingWeekCount(String feature) => getUsageCount(feature, sinceDate: DateTime.now().subtract(const Duration(days: 6)));

  /// Convenience: all-time count for [feature] — use for lifetime caps.
  Future<int> getLifetimeCount(String feature) => getUsageCount(feature);
}
