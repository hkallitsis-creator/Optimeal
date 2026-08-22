import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/config/app_environment.dart';
import 'package:optimeal/screens/onboarding_screen.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  // Colours come from AppDesignTokens — this screen used to carry its own
  // pair of statics, an exact duplicate of `deepForest` and a terracotta
  // (`0xFFD96B43`) that had drifted from the CTA. Folded into the palette by
  // the v1.2 sweep, 2026-08-22.
  static const double cardRadius = 16.0;
  static const List<BoxShadow> cardShadow = AppDesignTokens.cardShadow;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  String _language = 'en';
  UserDiet _diet = UserDiet.omnivore;
  KitchenConfidence _confidence = KitchenConfidence.beginner;
  final Set<String> _allergies = <String>{};
  int _servings = 1;
  bool _saving = false;

  final _confidenceClimbService = ConfidenceClimbService();

  /// Debounce for the inline name field and the chip rows.
  ///
  /// The screen used to end in a "Save Profile" button that also popped the
  /// route. Selections now persist as they are made, so there is no save
  /// button and nothing to forget to press — and the screen's one terracotta
  /// CTA can be "Secure my account", which is the only action here that is
  /// actually a decision.
  Timer? _autoSaveTimer;

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _save(silent: true);
    });
  }
  Set<String> _comfortableTechniqueIds = const <String>{};

  // The Language card is DELETED. Deutsch/Français/Italiano were offered and
  // none of them is shipped — a stale promise, the same class of thing the
  // onboarding rewrite cut. `_language` stays on the model and in the store
  // (no migration to drop it); it simply has no UI until localization exists.

  static const List<String> _allergenOptions = <String>[
    'Gluten',
    'Lactose/Dairy',
    'Tree Nuts',
    'Peanuts',
    'Fish',
    'Crustaceans',
    'Molluscs',
    'Soy',
    'Sesame',
    'Celery',
    'Mustard',
    'Sulfites/Alcohol',
    'Lupin',
    'Egg',
  ];

  @override
  void initState() {
    super.initState();
    final profile = context.read<UserProfileController>().profile;

    _nameController.text = profile.displayName;
    _language = profile.language;
    _diet = profile.diet;
    _confidence = profile.kitchenConfidence;
    _allergies
      ..clear()
      ..addAll(profile.allergies.map((e) => e.trim()).where((e) => e.isNotEmpty));
    _servings = profile.householdServings.clamp(1, 4);
    _loadComfortableTechniques();
  }

  Future<void> _loadComfortableTechniques() async {
    final ids = await _confidenceClimbService.loadComfortableTechniqueIds();
    if (!mounted) return;
    setState(() => _comfortableTechniqueIds = ids);
  }

  // _unmarkComfortable was deleted with the redesign. The Confidence Climb
  // is READ-ONLY here by signed decision: rows are filled solely by the
  // post-cook confidence question, and there is no self-declaration path in
  // either direction. The Climb is earned, not set.

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save({bool silent = false}) async {
    if (_saving) return;
    final profileController = context.read<UserProfileController>();
    final current = profileController.profile;

    // An empty name is no longer an error worth interrupting for: the field
    // is inline and saves as you type, so a half-typed name would otherwise
    // fire a snackbar on every keystroke. It simply is not persisted empty.
    final displayName = _nameController.text.trim();
    if (displayName.isEmpty && !silent) {
      _nameFocus.requestFocus();
      return;
    }

    setState(() => _saving = true);
    try {
      final next = current.copyWith(
        displayName: displayName.isEmpty ? current.displayName : displayName,
        language: _language,
        diet: _diet,
        allergies: _allergies.toList(growable: false),
        kitchenConfidence: _confidence,
        householdServings: _servings,
      );
      final persisted = await profileController.updateProfile(next);
      if (!mounted) return;

      if (!persisted) {
        // Autosave failures stay quiet: the screen saves on every chip tap,
        // and a snackbar per tap would be worse than the failure.
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Could not save profile. Please try again.')),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('ProfileScreen.save failed: $e');
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save profile. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Dev affordance: put the user back at slide 1.
  ///
  /// The reset itself lives on [OnboardingScreen.resetForReplay] — it knows
  /// about onboarding's own completion flags, and keeping it there means it
  /// can be tested without pumping this screen, which needs a live Supabase
  /// instance.
  /// Unchanged auth flow — only the button that opens it was restyled.
  Future<void> _openSecureAccountSheet() async {
    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceIvory,
      builder: (_) => const _SecureAccountSheet(),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _replayOnboarding() async {
    await OnboardingScreen.resetForReplay(
        context.read<UserProfileController>());
    if (!mounted) return;
    context.go(AppRoutes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnonymous =
        Supabase.instance.client.auth.currentUser?.isAnonymous ?? true;
    final userEmail = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // SIGNED-CONTENT PLACEHOLDER
        title: const Text('Profile'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            // ── Name: one quiet row, no card headline, no explainer ────────
            _QuietRow(
              // SIGNED-CONTENT PLACEHOLDER
              label: 'Name',
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                textAlign: TextAlign.end,
                textInputAction: TextInputAction.done,
                onChanged: (_) => _scheduleAutoSave(),
                onSubmitted: (_) => _save(silent: true),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  // SIGNED-CONTENT PLACEHOLDER
                  hintText: 'Chef',
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── EATING ─────────────────────────────────────────────────────
            _ProfileCard(
              // SIGNED-CONTENT PLACEHOLDER
              label: 'EATING',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in UserDiet.values)
                        SelectionChip(
                          label: _dietLabel(d),
                          selected: _diet == d,
                          onTap: () {
                            setState(() => _diet = d);
                            _scheduleAutoSave();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // SIGNED-CONTENT PLACEHOLDER
                  const _CardLabel('AVOID'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in _allergenOptions)
                        SelectionChip(
                          label: a,
                          selected: _allergies.contains(a),
                          showRemoveGlyph: true,
                          onTap: () {
                            setState(() {
                              if (!_allergies.remove(a)) _allergies.add(a);
                            });
                            _scheduleAutoSave();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── GUIDANCE ───────────────────────────────────────────────────
            _ProfileCard(
              // SIGNED-CONTENT PLACEHOLDER
              label: 'GUIDANCE',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in KitchenConfidence.values)
                    GuidanceRow(
                      label: _confidenceLabel(c),
                      selected: _confidence == c,
                      onTap: () {
                        setState(() => _confidence = c);
                        _scheduleAutoSave();
                      },
                    ),
                  const SizedBox(height: 12),
                  Divider(
                      height: 1,
                      color: AppDesignTokens.textCharcoal
                          .withValues(alpha: 0.10)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          // SIGNED-CONTENT PLACEHOLDER. Household DEFAULT
                          // semantics, never a live scaler: it prefills the
                          // Fridge Clearer portion segment and new recipes'
                          // basePortions. The live adjuster lives on the
                          // recipe overview and only there.
                          'Usually cooking for',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textCharcoal,
                          ),
                        ),
                      ),
                      _ServingsStepper(
                        value: _servings,
                        onChanged: (v) {
                          setState(() => _servings = v);
                          _scheduleAutoSave();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── COMFORTABLE TECHNIQUES — read-only, earned ─────────────────
            _ProfileCard(
              // SIGNED-CONTENT PLACEHOLDER
              label: 'COMFORTABLE TECHNIQUES',
              child: _ComfortableTechniques(ids: _comfortableTechniqueIds),
            ),

            const SizedBox(height: 14),

            // ── Account ────────────────────────────────────────────────────
            if (isAnonymous)
              _AnonymousAccountPromptCard(
                  onSecurePressed: _openSecureAccountSheet)
            else
              _SecuredAccountStatusCard(email: userEmail),

            if (kIsDevEnvironment) ...[
              const SizedBox(height: 18),
              _DevSection(onReplayOnboarding: _replayOnboarding),
            ],
          ],
        ),
      ),
    );
  }

  static String _dietLabel(UserDiet d) => switch (d) {
        UserDiet.omnivore => 'Omnivore',
        UserDiet.vegetarian => 'Vegetarian',
        UserDiet.pescatarian => 'Pescatarian',
        UserDiet.vegan => 'Vegan',
        UserDiet.flexitarian => 'Flexitarian',
      };

  /// Names are SIGNED as-is; the old explainer paragraphs are folded into the
  /// row as the one line after the separator.
  static String _confidenceLabel(KitchenConfidence c) => switch (c) {
        // SIGNED-CONTENT PLACEHOLDER (descriptions only — names are signed)
        KitchenConfidence.beginner => 'Beginner · more guidance, less jargon',
        KitchenConfidence.fastEfficient =>
          'Fast & efficient · direct steps, minimal fuss',
        KitchenConfidence.confident =>
          'Confident cook · technique names, no hand-holding',
      };
}

class _AnonymousAccountPromptCard extends StatelessWidget {
  const _AnonymousAccountPromptCard({required this.onSecurePressed});

  final VoidCallback onSecurePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: AppDesignTokens.deepForest),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your data is currently stored only on this device.',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'If you reinstall the app or switch phones, your profile, pantry, and cooking history can’t be recovered. Securing your account lets you sign in later and keep your progress.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: onSecurePressed,
              icon: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
              label: Text(
                'Secure My Account',
                style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                // The screen's ONE terracotta CTA. This was dark-forest —
                // a colour that is not a button fill anywhere in the kit and
                // now exists nowhere in lib/ as one (palette guard enforces).
                backgroundColor: AppDesignTokens.ctaTerracotta,
                foregroundColor: Colors.white,
                splashFactory: NoSplash.splashFactory,
                overlayColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecuredAccountStatusCard extends StatelessWidget {
  const _SecuredAccountStatusCard({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppDesignTokens.deepForest),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account secured',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  email == null || email!.trim().isEmpty ? 'Signed in' : 'Account secured: ${email!.trim()}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecureAccountSheet extends StatefulWidget {
  const _SecureAccountSheet();

  @override
  State<_SecureAccountSheet> createState() => _SecureAccountSheetState();
}

class _SecureAccountSheetState extends State<_SecureAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String input) {
    final text = input.trim();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(text);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ),
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account secured — check your email to confirm the change.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );

      context.pop();
    } on AuthException catch (e) {
      debugPrint('SecureAccountSheet.updateUser AuthException: ${e.message}');
      if (!mounted) return;

      final msg = e.message.toLowerCase();
      final isAlreadyRegistered = msg.contains('already registered') ||
          msg.contains('already been registered') ||
          msg.contains('already exists') ||
          msg.contains('user already') ||
          msg.contains('email address is already') ||
          msg.contains('email already');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAlreadyRegistered
                ? 'That email already has an account. Linking won’t merge data from that other account — choose a different email, or contact support if you need your existing data migrated.'
                : 'Could not secure your account. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    } catch (e, st) {
      debugPrint('SecureAccountSheet.updateUser failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not secure your account. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 10,
          bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Secure your account', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                'Add an email + password so you can restore your progress on a new device.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) return 'Please enter an email.';
                  if (!_looksLikeEmail(v)) return 'Please enter a valid email address.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Password'),
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  final v = value ?? '';
                  if (v.isEmpty) return 'Please enter a password.';
                  if (v.length < 8) return 'Password must be at least 8 characters.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    // The screen's ONE terracotta CTA. This was dark-forest —
                // a colour that is not a button fill anywhere in the kit and
                // now exists nowhere in lib/ as one (palette guard enforces).
                backgroundColor: AppDesignTokens.ctaTerracotta,
                    foregroundColor: Colors.white,
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _saving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Securing…',
                              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                            ),
                          ],
                        )
                      : Text(
                          'Secure My Account',
                          style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: _saving ? null : () => context.pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.22)),
                  ),
                  child: Text('Not now', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServingsStepper extends StatelessWidget {
  const _ServingsStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final canDown = value > 1;
    final canUp = value < 4;
    final label = value >= 4 ? '4+' : value.toString();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove_rounded,
            enabled: canDown,
            onTap: () => onChanged((value - 1).clamp(1, 4)),
          ),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary)),
          const SizedBox(width: 10),
          _StepperButton(
            icon: Icons.add_rounded,
            enabled: canUp,
            onTap: () => onChanged((value + 1).clamp(1, 4)),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.enabled, required this.onTap});

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
      iconSize: 18,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          enabled ? scheme.primary.withValues(alpha: 0.10) : scheme.surface,
        ),
        foregroundColor: WidgetStatePropertyAll(
          enabled ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
      ),
    );
  }
}

/// Dev-only row that sends the user back through onboarding.
class _ReplayOnboardingRow extends StatelessWidget {
  const _ReplayOnboardingRow({required this.onReplay});

  final Future<void> Function() onReplay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppDesignTokens.quietRowSurface,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
      child: InkWell(
        onTap: onReplay,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.replay_rounded,
                  size: 20,
                  color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Replay onboarding',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppDesignTokens.textCharcoal.withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One quiet row: a label and an inline control. No card headline, no
/// explainer paragraph — the old screen had one on every card.
class _QuietRow extends StatelessWidget {
  const _QuietRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.textCharcoal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A section card: one quiet uppercase label, then content. No subtitle
/// paragraph — every one of those was cut.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(label),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: AppDesignTokens.deepForest.withValues(alpha: 0.70),
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
      ),
    );
  }
}

/// **The one selection style on this screen.** Champagne fill when selected,
/// quiet surface with a hairline when not.
///
/// This replaced three different styles that used to coexist here: Material
/// radio circles, a terracotta check glyph, and a border-only selected state.
/// Selection is never communicated by a border alone and never by an icon
/// alone — kit rule.
class SelectionChip extends StatelessWidget {
  const SelectionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showRemoveGlyph = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Allergen chips carry a ✕ when selected, because deselecting one is a
  /// meaningful action rather than an idle toggle.
  final bool showRemoveGlyph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? AppDesignTokens.champagneTint
          : AppDesignTokens.quietRowSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? null
                : Border.all(
                    color: AppDesignTokens.textCharcoal
                        .withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? AppDesignTokens.terracottaOnLight
                      : AppDesignTokens.textCharcoal.withValues(alpha: 0.80),
                ),
              ),
              if (selected && showRemoveGlyph) ...[
                const SizedBox(width: 6),
                const Icon(Icons.close_rounded,
                    size: 14, color: AppDesignTokens.terracottaOnLight),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One guidance option. Single-select, champagne fill when chosen — **no
/// radio circle**; the old screen used Material radios here.
class GuidanceRow extends StatelessWidget {
  const GuidanceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppDesignTokens.champagneTint
            : AppDesignTokens.quietRowSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? null
                  : Border.all(
                      color: AppDesignTokens.textCharcoal
                          .withValues(alpha: 0.12)),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? AppDesignTokens.terracottaOnLight
                    : AppDesignTokens.textCharcoal.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Confidence Climb, shown but never set here.
///
/// **READ-ONLY, signed.** Rows are filled solely by the post-cook confidence
/// question; there is no self-declaration path and no un-marking path, and
/// there are deliberately no tap handlers on any row. The Climb is earned.
///
/// Gold is used for the "automatic" state and nowhere else on this screen —
/// it is the earned family, and this is the one earned thing on the surface.
class _ComfortableTechniques extends StatelessWidget {
  const _ComfortableTechniques({required this.ids});

  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (ids.isEmpty) {
      return Text(
        // SIGNED-CONTENT PLACEHOLDER
        'Nothing here yet — techniques land here once cooking them feels automatic.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppDesignTokens.textCharcoal.withValues(alpha: 0.65),
          height: 1.35,
        ),
      );
    }

    final entries = resolveDrawerEntries(ids.toList(growable: false))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    size: 18, color: AppDesignTokens.goldEarnedOnLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.goldEarnedOnLight,
                    ),
                  ),
                ),
                Text(
                  // SIGNED-CONTENT PLACEHOLDER
                  'automatic',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppDesignTokens.goldEarnedOnLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dev-only affordances, in a dashed-ghost container so they never read as
/// part of the product. Folds away entirely in a prod build — `kIsDevEnvironment`
/// is a compile-time constant, same as the DEV badge.
class _DevSection extends StatelessWidget {
  const _DevSection({required this.onReplayOnboarding});

  final Future<void> Function() onReplayOnboarding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppDesignTokens.textCharcoal.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DEV',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.55),
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            _ReplayOnboardingRow(onReplay: onReplayOnboarding),
            const SizedBox(height: 6),
            Text(
              'Environment: ${AppEnvironmentConfig.environment.name} · '
              '${AppEnvironmentConfig.supabase.url.split('//').last.split('.').first}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 6;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
