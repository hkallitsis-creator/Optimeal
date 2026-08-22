/// When a sales sheet is allowed to appear, and where the post-cook nudge
/// waits until it is.
///
/// # The ruling
///
/// **A sales sheet must never interrupt an active cook path — pre-cook
/// through post-cook verdict.** This shipped broken: the post-cook upgrade
/// nudge fired from inside Cook Mode's completion sequence, *before* the
/// verdict sheet, so a celebration-styled sales interstitial landed on top of
/// the cook the user was still finishing.
///
/// The post-cook moment itself is still one of the sanctioned upgrade moments.
/// What changed is where it lands: the nudge is now **scheduled** by Cook Mode
/// and **shown by Home**, once the verdict's exit CTA has actually delivered
/// the user there.
///
/// # Why a process-global rather than a parameter
///
/// The two facts this holds — "a cook is under way" and "a nudge is owed" —
/// are read by widgets that have no relationship to Cook Mode's `State` and
/// cannot be handed a reference to it. `UpgradePromptSheet.show` is called
/// from three unrelated places and must be able to refuse **without** its
/// callers remembering to ask; a guard every caller has to opt into is a
/// guard that the fourth caller forgets. Same reasoning as
/// `AppDataChanges` and `RecentGenerationsService`.
///
/// In memory only, deliberately. A nudge that survived an app restart would
/// be a sales sheet with no earned moment in front of it.
abstract final class UpgradeNudgeGate {
  static bool _cookPathActive = false;
  static String? _pendingToken;
  static String? _lastHandledToken;

  /// True while the user is anywhere between pre-cook and the verdict.
  /// [UpgradePromptSheet.show] refuses outright while this holds.
  static bool get isCookPathActive => _cookPathActive;

  /// Called by Cook Mode as it mounts.
  static void enterCookPath() => _cookPathActive = true;

  /// Called by Cook Mode as it leaves — both on the normal exit-to-Home path
  /// and from `dispose`, so an abandoned cook cannot leave the gate stuck
  /// closed for the rest of the session.
  static void exitCookPath() => _cookPathActive = false;

  /// True when a post-cook nudge is owed and has not been shown yet.
  static bool get hasPendingPostCookNudge => _pendingToken != null;

  /// Cook Mode records that this completion earned a nudge. Nothing is shown
  /// here — Home shows it, after the verdict's CTA has landed.
  ///
  /// [token] identifies the **cook**, not the call, and is minted once per
  /// Cook Mode session. Scheduling the same token twice is a no-op, so at
  /// most one nudge is ever owed per cook however many times the completion
  /// sequence runs — a resumed session, a rebuild, or a retried write cannot
  /// turn one dinner into two sales sheets.
  static void schedulePostCookNudge(String token) {
    if (token == _lastHandledToken) return;
    _pendingToken = token;
  }

  /// Home takes the pending nudge, if there is one. Returns true exactly
  /// once per cook, so neither a rebuild nor a second cook of the same
  /// session can show the sheet twice.
  static bool consumePendingPostCookNudge() {
    final token = _pendingToken;
    if (token == null) return false;
    _pendingToken = null;
    _lastHandledToken = token;
    return true;
  }

  /// Test seam. Not called by app code.
  static void resetForTest() {
    _cookPathActive = false;
    _pendingToken = null;
    _lastHandledToken = null;
  }
}
