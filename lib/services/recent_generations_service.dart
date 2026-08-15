/// In-memory, app-session-lifetime record of dish titles generated across
/// AI recipe surfaces (Fridge Clearer, home dashboard's Chef Harris
/// Suggestion, Custom AI Recipe Creator). Weekly Planner's Deal Meal path
/// used this too until its removal (CLAUDE.md Roadmap items 18/19).
///
/// Deliberately separate from [CookSessionStorageService]'s persisted
/// cook history: that service only records a dish once the user actually
/// opens Cook Mode with it, so back-to-back "Try Another"/"Generate" calls
/// within one sitting were invisible to recipe-variety exclusion (see
/// CLAUDE.md roadmap item 13 — this was the root cause of five consecutive
/// Fridge Clearer generations all landing on the same dish). This service
/// closes that gap without conflating the two different lifetimes/semantics
/// (persisted+cooked vs. in-memory+generated).
///
/// A singleton (not per-screen state) so it survives navigating away and
/// back, and is shared across every surface that generates recipes — the
/// exact requirement that ruled out storing this in a screen's State.
/// Intentionally not persisted to disk: it resets on a full app restart,
/// which is fine since its job is only to catch immediate repeats within
/// one running session, not to be a second, competing history store.
class RecentGenerationsService {
  RecentGenerationsService._();
  static final RecentGenerationsService instance = RecentGenerationsService._();

  static const int _maxTracked = 20;

  final List<String> _titles = [];

  /// Records a freshly generated dish title. Case-insensitive dedupe (moves
  /// an existing match to the front rather than duplicating it), capped at
  /// [_maxTracked] most recent.
  void record(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _titles.removeWhere((t) => t.toLowerCase() == trimmed.toLowerCase());
    _titles.insert(0, trimmed);
    if (_titles.length > _maxTracked) {
      _titles.removeRange(_maxTracked, _titles.length);
    }
  }

  /// Most recent titles first.
  List<String> recent() => List.unmodifiable(_titles);
}
