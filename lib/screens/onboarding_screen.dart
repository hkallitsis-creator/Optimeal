import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/onboarding_visuals.dart';

/// The four-slide intro every new user sees.
///
/// Redesigned 2026-08-22 against the signed spec card. The **structure** was
/// sound and is kept verbatim: a `PageView` of four slides, one ivory card per
/// slide, dots, one terracotta CTA, Skip top-right hidden on the last slide.
/// What changed is content, visuals and routing — all three were shipping
/// promises the app no longer keeps:
///
/// - Slide 3 advertised "steps, checkboxes, and timing". Checkboxes died with
///   the pre-cook merge.
/// - Slide 4 advertised "Weekly Planner + Shopping List stay in sync. Two-way."
///   The shopping list was cut entirely in August.
/// - Slide 2 quoted a CHF waste statistic that was never sourced.
/// - Slide 1 was invented-persona-era text defending Chef Harris against being
///   "a chatbot pretending to know knife skills" — leading with what he is not.
/// - **Skip was broken outright**: it routed to `/paywall` having set only the
///   local `hasSeenOnboarding` flag and never `profile.onboarded`, so the
///   router's own redirect (`!isOnboarded && !isOnboarding → onboarding`)
///   bounced the user straight back. See [_completeOnboarding].
///
/// Routing is now: **Skip → Home. Finish → Home.** The paywall leaves the
/// onboarding path entirely until pricing is real (`docs/DECISIONS.md` still
/// records 15 CHF as a placeholder). The paywall screen itself is untouched.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String hasSeenOnboardingKey = 'hasSeenOnboarding';

  /// How many slides there are. Read by the dots and the last-slide checks so
  /// adding a fifth slide cannot leave one of them behind.
  static const int slideCount = 4;

  /// Puts a user back at slide 1. Dev affordance only — see the Developer
  /// section of the Profile screen, which is compiled out of release builds.
  ///
  /// Resets **both** halves of "has this user been onboarded", because they
  /// are independent and the router gates on the second one: the local
  /// `hasSeenOnboarding` flag, and `profile.onboarded`. Clearing only the flag
  /// leaves the user exactly where they were — which is the same trap the old
  /// Skip fell into (see [_OnboardingScreenState._completeOnboarding]).
  ///
  /// Deliberately does not touch the `user_profiles` row: this replays an
  /// intro, it does not delete an account.
  static Future<void> resetForReplay(UserProfileController profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(hasSeenOnboardingKey);
    } catch (e) {
      debugPrint('Replay onboarding: failed to clear local flag: $e');
    }
    try {
      await profile.updateProfile(profile.profile.copyWith(onboarded: false));
    } catch (e) {
      debugPrint('Replay onboarding: failed to reset profile flag: $e');
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _persisted = false;

  bool get _isLastSlide => _index >= OnboardingScreen.slideCount - 1;

  Future<void> _upsertUserProfileToSupabase() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    debugPrint('Onboarding write - current user: $currentUserId');
    if (currentUserId == null) {
      debugPrint('No authenticated user session - skipping profile write');
      return;
    }

    try {
      final profile = context.read<UserProfileController>().profile;
      final result =
          await Supabase.instance.client.from('user_profiles').upsert({
        'id': currentUserId,
        'name': profile.displayName,
        'language': profile.language,
        'dietary_preference': profile.diet.name,
        'allergies': profile.allergies,
        // TODO: Map a free-text custom allergy field once the local profile supports it.
        'allergies_custom': null,
        'portion_size': profile.householdServings,
        'skill_level': profile.kitchenConfidence.name,
      }).select();

      debugPrint('Supabase upsert success (user_profiles): $result');
    } catch (error) {
      debugPrint('Supabase upsert failed: $error');
      // Non-fatal: user can still continue.
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _setHasSeenOnboarding() async {
    if (_persisted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.hasSeenOnboardingKey, true);
      _persisted = true;
    } catch (e) {
      debugPrint('Failed to persist hasSeenOnboarding: $e');
      // Non-fatal: user can still continue.
      _persisted = true;
    }
  }

  /// The single completion path, shared by Skip and Finish.
  ///
  /// **Skip must complete exactly as thoroughly as Finish.** All three writes
  /// happen, in this order, on both:
  ///
  /// 1. `hasSeenOnboarding` in SharedPreferences,
  /// 2. `profile.onboarded = true` on the local controller,
  /// 3. the `user_profiles` upsert.
  ///
  /// Step 2 is not optional and is not decorative: the router redirects
  /// `!isOnboarded` back to onboarding from anywhere, so a skip that set only
  /// the local flag left the user pinned to this screen. That is what the old
  /// `_skipToPaywall` did, which is why Skip never worked.
  ///
  /// Order matters for a second reason: the controller's `notifyListeners()`
  /// is the router's `refreshListenable`, so flipping it before the Supabase
  /// write means navigation never waits on the network. The write is
  /// best-effort and never blocks completion.
  Future<void> _completeOnboarding() async {
    await _setHasSeenOnboarding();
    if (!mounted) return;

    try {
      final profileController = context.read<UserProfileController>();
      final current = profileController.profile;
      final next =
          current.copyWith(onboarded: true, createdAt: current.createdAt);
      await profileController.updateProfile(next);
      debugPrint(
          'Local profile updated: onboarded=${profileController.profile.onboarded}');
    } catch (e, st) {
      debugPrint(
          'Failed to update local UserProfileController during onboarding: $e');
      debugPrint('$st');
    }

    try {
      await _upsertUserProfileToSupabase();
    } catch (e, st) {
      debugPrint('Onboarding profile save threw unexpectedly: $e');
      debugPrint('$st');
    }

    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _nextOrFinish() async {
    if (!_isLastSlide) {
      await _pageController.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
      return;
    }
    await _completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (value) async {
                setState(() => _index = value);
                if (value >= OnboardingScreen.slideCount - 1) {
                  await _setHasSeenOnboarding();
                }
              },
              children: const [
                // 1 — Chef Harris. Leads with what he IS. No hardcoded year
                // count, no defensive "not a chatbot" framing.
                _OnboardingSlide(
                  visual: SpoonAndBowlIllustration(),
                  // PLACEHOLDER — final verbatim rides with the persona batch.
                  headline: 'Hi, I\'m Chef Harris.',
                  // PLACEHOLDER
                  subtext:
                      'A real cooking teacher — years of real students, real pans, '
                      'real mistakes fixed. I\'ll teach you the way I teach in person.',
                ),
                // 2 — Fridge Clearer. No CHF statistic: it was never sourced
                // or signed, so it is out until it is both.
                _OnboardingSlide(
                  visual: FridgeIllustration(),
                  // PLACEHOLDER
                  headline: 'The best dinner is already in your fridge.',
                  // PLACEHOLDER
                  subtext:
                      'Tell me what needs using up and I\'ll turn it into dinner. '
                      'Every ingredient you rescue gets counted.',
                ),
                // 3 — Cook Mode. The visual pre-teaches sage = teaching.
                _OnboardingSlide(
                  visual: MiniCuePanelPreview(),
                  // PLACEHOLDER
                  headline: 'One step at a time — and how to tell it\'s working.',
                  // PLACEHOLDER
                  subtext:
                      'Cook Mode shows you one step, then what to look, listen and '
                      'smell for. Cook by your senses, not the clock.',
                ),
                // 4 — Planner + My recipes.
                _OnboardingSlide(
                  visual: MiniWeekStripPreview(),
                  // PLACEHOLDER
                  headline: 'Plan your week. Keep your winners.',
                  // PLACEHOLDER
                  subtext:
                      'Drop a recipe into any day and cook it straight from there. '
                      'Bookmark anything you liked and it\'s waiting in My recipes.',
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: !_isLastSlide
                    ? Padding(
                        key: const ValueKey('skip'),
                        padding: const EdgeInsets.only(
                            right: AppDesignTokens.spaceSM,
                            top: AppDesignTokens.spaceXS),
                        child: TextButton(
                          // Skip completes onboarding exactly as Finish does —
                          // see _completeOnboarding.
                          onPressed: _completeOnboarding,
                          style: TextButton.styleFrom(
                            foregroundColor: AppDesignTokens.textCharcoal,
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: Colors.transparent,
                            textStyle: AppDesignTokens.caption,
                          ),
                          // PLACEHOLDER
                          child: const Text('Skip'),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-skip')),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDesignTokens.spaceLG,
                  AppDesignTokens.spaceMD,
                  AppDesignTokens.spaceLG,
                  AppDesignTokens.spaceLG,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DotsIndicator(activeIndex: _index),
                    const SizedBox(height: AppDesignTokens.spaceMD),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _nextOrFinish,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppDesignTokens.ctaTerracotta,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusButton)),
                          splashFactory: NoSplash.splashFactory,
                          overlayColor: Colors.transparent,
                          textStyle: AppDesignTokens.subheadline
                              .copyWith(color: Colors.white),
                        ),
                        // PLACEHOLDER (both labels)
                        child: Text(_isLastSlide ? 'Let\'s cook' : 'Next'),
                      ),
                    ),
                    const SizedBox(height: AppDesignTokens.spaceSM),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One slide: an ivory card holding a small visual, a headline and a subtext.
///
/// The visual replaced a champagne-tinted icon tile. Slides 1–2 are line
/// illustrations; 3–4 are previews of real UI, so a user meets the sage
/// teaching panel and the planner's day states before they ever reach them.
class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.visual,
    required this.headline,
    required this.subtext,
  });

  final Widget visual;
  final String headline;
  final String subtext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppDesignTokens.spaceLG, 40, AppDesignTokens.spaceLG, 140),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceIvory,
                borderRadius:
                    BorderRadius.circular(AppDesignTokens.radiusCard),
                border: Border.all(
                    color:
                        AppDesignTokens.textCharcoal.withValues(alpha: 0.12),
                    width: 1),
                boxShadow: AppDesignTokens.cardShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppDesignTokens.spaceLG),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    visual,
                    const SizedBox(height: AppDesignTokens.spaceLG),
                    Text(
                      headline,
                      style: AppDesignTokens.headline.copyWith(height: 1.18),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: AppDesignTokens.spaceMD),
                    Text(
                      subtext,
                      style: AppDesignTokens.body.copyWith(
                          height: 1.5,
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.80)),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: AppDesignTokens.spaceSM),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int activeIndex;

  const _DotsIndicator({required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(OnboardingScreen.slideCount, (i) {
        final isActive = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(
              horizontal: AppDesignTokens.spaceXS / 2),
          width: isActive ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? AppDesignTokens.ctaTerracotta
                : AppDesignTokens.textCharcoal.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
