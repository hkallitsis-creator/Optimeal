import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String hasSeenOnboardingKey = 'hasSeenOnboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _persisted = false;

  Future<void> _upsertUserProfileToSupabase() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    debugPrint('Onboarding write - current user: $currentUserId');
    if (currentUserId == null) {
      debugPrint('No authenticated user session - skipping profile write');
      return;
    }

    try {
      final profile = context.read<UserProfileController>().profile;
      final result = await Supabase.instance.client.from('user_profiles').upsert({
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

  Future<void> _skipToPaywall() async {
    await _setHasSeenOnboarding();
    if (!mounted) return;
    context.go('/paywall');
  }

  Future<void> _nextOrFinish() async {
    if (_index < 3) {
      await _pageController.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      return;
    }

    debugPrint("Onboarding complete - navigating to home");
    await _setHasSeenOnboarding();
    if (!mounted) return;

    // IMPORTANT: Update the local profile controller first so `isOnboarded`
    // flips to true and `notifyListeners()` triggers the GoRouter redirect
    // refreshListenable. This must not be gated by the Supabase write.
    try {
      final profileController = context.read<UserProfileController>();
      final current = profileController.profile;

      // Ensure all onboarding-collected fields are applied alongside onboarded=true.
      // In this screen, those values are already stored on the controller's profile
      // as the user proceeds through onboarding. We preserve them and only flip
      // `onboarded` here.
      final next = current.copyWith(onboarded: true, createdAt: current.createdAt);
      await profileController.updateProfile(next);
      debugPrint('Local profile updated: onboarded=${profileController.profile.onboarded}');
    } catch (e, st) {
      // Non-fatal: we still navigate, but redirect bouncing may persist if this fails.
      debugPrint('Failed to update local UserProfileController during onboarding: $e');
      debugPrint('$st');
    }

    // Backend persistence (non-blocking for navigation). Keep internals unchanged.
    try {
      await _upsertUserProfileToSupabase();
    } catch (e, st) {
      // Non-fatal: onboarding must still complete.
      debugPrint('Onboarding profile save threw unexpectedly: $e');
      debugPrint('$st');
    }

    debugPrint('Navigating to home now');
    if (!mounted) return;
    context.go(AppRoutes.home);
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
                if (value >= 3) await _setHasSeenOnboarding();
              },
              children: const [
                _OnboardingSlide(
                  icon: Icons.restaurant_menu_rounded,
                  headline: "Cooking shouldn't feel like debugging a recipe.",
                  subtext:
                      "I'm Chef Harris — a real culinary educator. I’ll teach technique, timing, and how to not cry over onions. I'm not a chatbot pretending to know knife skills.",
                ),
                _OnboardingSlide(
                  icon: Icons.savings_outlined,
                  headline: "Swiss households waste 600+ CHF a year… in food that never gets eaten.",
                  subtext:
                      "OptiMeal's Fridge Clearer turns ‘what's about to die in my crisper’ into dinner — fast.",
                ),
                _OnboardingSlide(
                  icon: Icons.timer_outlined,
                  headline: "Cook Mode is steps, checkboxes, and timing — not a novel.",
                  subtext:
                      "Structured, timed, checkbox-driven cooking with live timers and heat cues. So you move like a chef, not a panicked squirrel.",
                ),
                _OnboardingSlide(
                  icon: Icons.checklist_rounded,
                  headline: "Weekly Planner keeps every meal mapped out, Monday to Sunday.",
                  subtext:
                      "Drop recipes into any day, then jump straight into Cook Mode when it's time to cook.",
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _index < 3
                    ? Padding(
                        key: const ValueKey('skip'),
                        padding: const EdgeInsets.only(right: AppDesignTokens.spaceSM, top: AppDesignTokens.spaceXS),
                        child: TextButton(
                          onPressed: _skipToPaywall,
                          style: TextButton.styleFrom(
                            foregroundColor: AppDesignTokens.textCharcoal,
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: Colors.transparent,
                            textStyle: AppDesignTokens.caption,
                          ),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
                          splashFactory: NoSplash.splashFactory,
                          overlayColor: Colors.transparent,
                          textStyle: AppDesignTokens.subheadline.copyWith(color: Colors.white),
                        ),
                        child: Text(_index >= 3 ? "Let's Cook" : 'Next'),
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

class _OnboardingSlide extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String subtext;

  const _OnboardingSlide({required this.icon, required this.headline, required this.subtext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceLG, 40, AppDesignTokens.spaceLG, 140),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceIvory,
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
              border: Border.all(color: cs.outline.withValues(alpha: 0.12), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDesignTokens.spaceLG),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.champagneTint,
                      borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
                      border: Border.all(color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.20)),
                    ),
                    child: Icon(icon, color: AppDesignTokens.ctaTerracotta, size: 26),
                  ),
                  const SizedBox(height: AppDesignTokens.spaceLG),
                  Text(
                    headline,
                    style: AppDesignTokens.headline.copyWith(height: 1.18),
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: AppDesignTokens.spaceMD),
                  Text(
                    subtext,
                    style: AppDesignTokens.body.copyWith(height: 1.5, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.80)),
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: AppDesignTokens.spaceSM),
                ],
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
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final isActive = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: AppDesignTokens.spaceXS / 2),
          width: isActive ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppDesignTokens.ctaTerracotta : cs.outline.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
