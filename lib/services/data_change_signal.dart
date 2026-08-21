import 'dart:async';

/// A local "this data just changed" announcement.
///
/// The app's stale-read defect family (session 2026-08-22) all had the same
/// shape: a screen reads something once, a *different* screen writes it, and
/// nothing tells the reader to look again. The old answer was navigation —
/// [RouteAware.didPopNext] on Home — which is structurally unreliable:
/// Flutter's [RouteObserver] only reacts to `didPush`/`didPop`, and a
/// `context.go(...)` that unwinds a page which still has a modal sheet
/// attached is resolved by the Navigator as *complete*, not *pop*. The route
/// underneath is never told anything. Every post-cook exit in this app goes
/// through a sheet CTA, so Home's refresh never fired.
///
/// So the trigger is the write, not the navigation: a writer calls [notify]
/// after the data has actually changed, and every reader that is mounted
/// re-reads. Readers that are not mounted do not need telling — they read on
/// their own `initState`.
///
/// Deliberately not a Supabase realtime subscription and not a state
/// management package: all of this data is single-user and only ever changes
/// because of something this app just did on this device, so a local signal
/// is both sufficient and free. Same reasoning as
/// `SavedRecipesService`'s change stream, which is where this pattern started
/// — it now uses this class too.
class DataChangeSignal {
  DataChangeSignal(this.name);

  /// Debug label only — shows up in nothing user-facing.
  final String name;

  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  /// Fires listeners. Safe to call when nobody is listening, and safe to call
  /// from a `catch`/`finally` — it never throws.
  void notify() {
    if (_controller.isClosed) return;
    _controller.add(null);
  }

  Stream<void> get stream => _controller.stream;

  /// Convenience for the common reader shape: re-run a load function on every
  /// change. Hold the subscription in `State` and cancel it in `dispose`.
  StreamSubscription<void> listen(void Function() onChange) =>
      _controller.stream.listen((_) => onChange());

  Future<void> dispose() => _controller.close();
}

/// The app-wide signals — one per data domain that more than one surface
/// reads.
///
/// Saved recipes deliberately are NOT here: [SavedRecipesService] owns a
/// per-instance [DataChangeSignal] so an injected test service cannot
/// cross-talk with the shared singleton. These two are process-global because
/// the stores behind them (SharedPreferences, `waste_ledger_events`) are
/// global too, and the services that write them are constructed ad hoc all
/// over the app rather than injected.
class AppDataChanges {
  const AppDataChanges._();

  /// Waste Ledger totals changed — a completion was logged, or a queued
  /// write was flushed. Read by Home's rescue strip.
  static final DataChangeSignal ledger = DataChangeSignal('ledger');

  /// The local cook store changed — active session saved/cleared, a cook
  /// recorded into Recently Cooked / cook history. Read by Home's resume
  /// banner and by My recipes' recently-cooked log and derived cook counts.
  static final DataChangeSignal cookLog = DataChangeSignal('cookLog');

  /// `user_meal_plans` changed from OUTSIDE the Weekly Planner — today that
  /// means exactly one writer: a finished cook marking the planner slot it was
  /// launched from as cooked (`PlannerCookAttributionService`).
  ///
  /// This is separate from [cookLog] on purpose, even though the same
  /// completion fires both. [cookLog] announces the local SharedPreferences
  /// cook store; this announces a Postgres table. They also fire at different
  /// moments — `clearActiveSession()` raises [cookLog] at the very top of the
  /// completion sequence, long before the plan row has been written, so a
  /// planner re-read driven by [cookLog] alone would read the row back
  /// uncooked. The planner subscribes to both and coalesces.
  static final DataChangeSignal mealPlan = DataChangeSignal('mealPlan');
}
