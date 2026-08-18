import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';

/// A dismissible, monthly-cadence recap card for Home: pure aggregation on
/// data already logged via [LedgerService] and [CookSessionStorageService]
/// — no new capture logic. Deliberately NOT a visible streak counter and
/// deliberately has no framing around missed days or gaps — this is a
/// positive recap ("here's what you accomplished"), not a guilt mechanic.
///
/// See CLAUDE.md Retention Features Backlog item 4.
class YourMonthCard extends StatefulWidget {
  const YourMonthCard({super.key});

  @override
  State<YourMonthCard> createState() => _YourMonthCardState();
}

class _YourMonthCardState extends State<YourMonthCard> {
  final _ledgerService = LedgerService();
  final _sessionStorage = CookSessionStorageService();

  bool _loading = true;
  bool _dismissed = false;
  int _ingredientsRescued = 0;
  int _newTechniquesCount = 0;
  String? _mostCookedTechniqueTitle;

  static String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String _dismissPrefsKey(DateTime d) => 'your_month_dismissed_v1_${_monthKey(d)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_dismissPrefsKey(now)) ?? false;

    final ingredientsRescued = await _ledgerService.getMonthlyIngredientsRescuedCount();
    // Forward-only filter (device-test round F11) — see the matching
    // comment in ConfidenceClimbService.evaluate. Only "new techniques" /
    // "most-cooked" stats are affected; the ingredient-rescue count above
    // is sourced from LedgerService, unrelated to this history store.
    final allHistory = await _sessionStorage.loadCookHistory();
    final history = allHistory
        .where((e) => e.source == CookSessionStorageService.declaredKeySource)
        .toList(growable: false);

    final thisMonthTechniqueIds = <String>{};
    final beforeThisMonthTechniqueIds = <String>{};
    final techniqueCounts = <String, int>{};
    for (final entry in history) {
      final ids = entry.recipe.curriculumLessonIds ?? const <String>[];
      final isThisMonth = entry.cookedAt.year == now.year && entry.cookedAt.month == now.month;
      for (final id in ids) {
        if (isThisMonth) {
          thisMonthTechniqueIds.add(id);
          techniqueCounts[id] = (techniqueCounts[id] ?? 0) + 1;
        } else {
          beforeThisMonthTechniqueIds.add(id);
        }
      }
    }
    final newTechniqueIds = thisMonthTechniqueIds.difference(beforeThisMonthTechniqueIds);

    String? mostCookedTitle;
    if (techniqueCounts.isNotEmpty) {
      final ranked = techniqueCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      mostCookedTitle = resolveDrawerEntry(ranked.first.key)?.title;
    }

    if (!mounted) return;
    setState(() {
      _dismissed = dismissed;
      _ingredientsRescued = ingredientsRescued;
      _newTechniquesCount = newTechniqueIds.length;
      _mostCookedTechniqueTitle = mostCookedTitle;
      _loading = false;
    });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissPrefsKey(DateTime.now()), true);
    if (!mounted) return;
    setState(() => _dismissed = true);
  }

  List<String> _statLines() {
    final lines = <String>[];
    if (_ingredientsRescued > 0) {
      lines.add('$_ingredientsRescued ingredient${_ingredientsRescued == 1 ? '' : 's'} rescued');
    }
    if (_newTechniquesCount > 0) {
      lines.add('$_newTechniquesCount new technique${_newTechniquesCount == 1 ? '' : 's'} picked up');
    }
    if (_mostCookedTechniqueTitle != null) {
      lines.add('most-cooked: $_mostCookedTechniqueTitle');
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _dismissed) return const SizedBox.shrink();
    final stats = _statLines();
    if (stats.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final monthName = _MonthNames.full[DateTime.now().month - 1];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppDesignTokens.deepForest, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your $monthName',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal),
                ),
              ),
              IconButton(
                onPressed: _dismiss,
                icon: Icon(Icons.close_rounded, size: 18, color: scheme.onSurfaceVariant),
                visualDensity: VisualDensity.compact,
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            stats.join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal, fontWeight: FontWeight.w700, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MonthNames {
  static const full = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}
