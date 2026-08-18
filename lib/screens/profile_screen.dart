import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const Color sageBackground = Color(0xFFC5D3C1);
  static const Color deepForest = Color(0xFF1E3A2B);
  static const Color terracotta = Color(0xFFD96B43);
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
  Set<String> _comfortableTechniqueIds = const <String>{};

  static const List<({String label, String code})> _languageOptions = <({String label, String code})>[
    (label: 'English', code: 'en'),
    (label: 'Deutsch', code: 'de'),
    (label: 'Français', code: 'fr'),
    (label: 'Italiano', code: 'it'),
  ];

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

  /// Confidence regresses — Confidence Climb lets the user say so
  /// (docs/decisions_2026-08-17.md item 7 / CLAUDE.md Package E3).
  Future<void> _unmarkComfortable(String techniqueId) async {
    setState(() => _comfortableTechniqueIds = _comfortableTechniqueIds.difference({techniqueId}));
    await _confidenceClimbService.markNotComfortable(techniqueId);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final profileController = context.read<UserProfileController>();
    final current = profileController.profile;

    final displayName = _nameController.text.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name so Chef Harris knows what to call you.')),
      );
      _nameFocus.requestFocus();
      return;
    }

    setState(() => _saving = true);
    try {
      final next = current.copyWith(
        displayName: displayName,
        language: _language,
        diet: _diet,
        allergies: _allergies.toList(growable: false),
        kitchenConfidence: _confidence,
        householdServings: _servings,
      );
      final persisted = await profileController.updateProfile(next);
      if (!mounted) return;

      if (!persisted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save profile. Please try again.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile saved!'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pop();
      });
    } catch (e) {
      debugPrint('ProfileScreen.save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save profile. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAnonymous = Supabase.instance.client.auth.currentUser?.isAnonymous ?? true;
    final userEmail = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      backgroundColor: ProfileScreen.sageBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profile & Settings'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            ProfileSectionCard(
              title: 'Display name',
              subtitle: 'What should Chef Harris call you?',
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'e.g., Alex',
                ),
              ),
            ),
            const SizedBox(height: 14),
            ProfileSectionCard(
              title: 'Language',
              subtitle: 'Choose the app language (more coming soon).',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _languageOptions.map((opt) {
                  final selected = _language == opt.code;
                  return FilterChip(
                    selected: selected,
                    showCheckmark: false,
                    label: Text(opt.label),
                    selectedColor: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.12),
                    side: BorderSide(
                      color: (selected ? AppDesignTokens.ctaTerracotta : scheme.outline).withValues(alpha: 0.18),
                      width: selected ? 1.2 : 1.0,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? AppDesignTokens.ctaTerracotta : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (v) {
                      if (!v) return;
                      setState(() => _language = opt.code);
                    },
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 14),
            ProfileSectionCard(
              title: 'Dietary baseline',
              subtitle: 'Helps Chef Harris tailor suggestions to your local pantry.',
              child: Column(
                children: [
                  DietOptionTile(
                    title: 'Omnivore',
                    subtitle: 'Anything goes — balanced and practical.',
                    value: UserDiet.omnivore,
                    groupValue: _diet,
                    onChanged: (v) => setState(() => _diet = v),
                  ),
                  const SizedBox(height: 10),
                  DietOptionTile(
                    title: 'Vegetarian',
                    subtitle: 'No meat. Dairy/eggs are okay.',
                    value: UserDiet.vegetarian,
                    groupValue: _diet,
                    onChanged: (v) => setState(() => _diet = v),
                  ),
                  const SizedBox(height: 10),
                  DietOptionTile(
                    title: 'Pescatarian',
                    subtitle: 'Vegetarian + fish/seafood.',
                    value: UserDiet.pescatarian,
                    groupValue: _diet,
                    onChanged: (v) => setState(() => _diet = v),
                  ),
                  const SizedBox(height: 10),
                  DietOptionTile(
                    title: 'Vegan',
                    subtitle: 'No animal products.',
                    value: UserDiet.vegan,
                    groupValue: _diet,
                    onChanged: (v) => setState(() => _diet = v),
                  ),
                  const SizedBox(height: 10),
                  DietOptionTile(
                    title: 'Flexitarian',
                    subtitle: 'Mostly plants, occasionally meat/fish.',
                    value: UserDiet.flexitarian,
                    groupValue: _diet,
                    onChanged: (v) => setState(() => _diet = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ProfileSectionCard(
  title: 'Allergen safeguards',
              subtitle: 'Select any allergens or intolerances to avoid.',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _allergenOptions.map((label) {
                  final selected = _allergies.contains(label);
                  return FilterChip(
                    selected: selected,
                    showCheckmark: false,
                    label: Text(label),
                    selectedColor: AppDesignTokens.ctaTerracotta,
                    side: BorderSide(
                      color: (selected ? AppDesignTokens.ctaTerracotta : scheme.outline).withValues(alpha: 0.18),
                      width: selected ? 1.2 : 1.0,
                    ),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _allergies.add(label);
                        } else {
                          _allergies.remove(label);
                        }
                      });
                    },
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 14),
            ProfileSectionCard(
              title: 'Skill & servings',
              subtitle: 'Tune instructions to your style and household size.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConfidenceOptionRow(
                    value: KitchenConfidence.beginner,
                    groupValue: _confidence,
                    title: 'Beginner',
                    subtitle: 'More guidance, less jargon.',
                    onChanged: (v) => setState(() => _confidence = v),
                  ),
                  const SizedBox(height: 10),
                  ConfidenceOptionRow(
                    value: KitchenConfidence.fastEfficient,
                    groupValue: _confidence,
                    title: 'Fast & Efficient',
                    subtitle: 'Direct steps, minimal fuss.',
                    onChanged: (v) => setState(() => _confidence = v),
                  ),
                  const SizedBox(height: 10),
                  ConfidenceOptionRow(
                    value: KitchenConfidence.confident,
                    groupValue: _confidence,
                    title: 'Confident Cook',
                    subtitle: 'Shorter instructions, more freedom.',
                    onChanged: (v) => setState(() => _confidence = v),
                  ),
                  if (_comfortableTechniqueIds.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Comfortable with',
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to say you\'re not quite there yet — confidence can dip back down.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in _comfortableTechniqueIds)
                          InputChip(
                            label: Text(resolveDrawerEntry(id)?.title ?? id),
                            onDeleted: () => _unmarkComfortable(id),
                            deleteIcon: const Icon(Icons.replay_rounded, size: 16),
                            backgroundColor: AppDesignTokens.deepForest.withValues(alpha: 0.08),
                            side: BorderSide(color: AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                            labelStyle: const TextStyle(color: AppDesignTokens.deepForest, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
                      border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Servings', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(
                                'Scale ingredients automatically (1–4+ people).',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ServingsStepper(
                          value: _servings,
                          onChanged: (v) => setState(() => _servings = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ProfileSectionCard(
              title: 'Account',
              subtitle: isAnonymous
                  ? 'Optional: keep your data safe across devices.'
                  : 'Your account is secured and can be restored on new devices.',
              child: isAnonymous
                  ? _AnonymousAccountPromptCard(
                      onSecurePressed: () async {
                        await AppBottomSheet.show<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          backgroundColor: AppDesignTokens.surfaceCream,
                          builder: (_) => const _SecureAccountSheet(),
                        );
                        if (!mounted) return;
                        // Refresh this screen’s UI after a successful link.
                        setState(() {});
                      },
                    )
                  : _SecuredAccountStatusCard(email: userEmail),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: Icon(Icons.save_rounded, color: scheme.onTertiary),
              label: Text('💾 Save Profile', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.tertiary,
                foregroundColor: scheme.onTertiary,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White, rounded card that pops off the sage canvas.
class ProfileSectionCard extends StatelessWidget {
  const ProfileSectionCard({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
        boxShadow: ProfileScreen.cardShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
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
              Icon(Icons.lock_outline_rounded, color: ProfileScreen.deepForest),
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
                backgroundColor: ProfileScreen.deepForest,
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
          Icon(Icons.verified_rounded, color: ProfileScreen.deepForest),
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
        SnackBar(
          content: const Text('Account secured — check your email to confirm the change.'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                    backgroundColor: ProfileScreen.deepForest,
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

class DietOptionTile extends StatelessWidget {
  const DietOptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final UserDiet value;
  final UserDiet groupValue;
  final ValueChanged<UserDiet> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = value == groupValue;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
            border: Border.all(color: selected ? ProfileScreen.deepForest.withValues(alpha: 0.45) : scheme.outline.withValues(alpha: 0.14)),
            boxShadow: ProfileScreen.cardShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? ProfileScreen.deepForest : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.25)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfidenceOptionRow extends StatelessWidget {
  const ConfidenceOptionRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final KitchenConfidence value;
  final KitchenConfidence groupValue;
  final String title;
  final String subtitle;
  final ValueChanged<KitchenConfidence> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = value == groupValue;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(ProfileScreen.cardRadius),
            border: Border.all(color: selected ? ProfileScreen.terracotta.withValues(alpha: 0.55) : scheme.outline.withValues(alpha: 0.14)),
            boxShadow: ProfileScreen.cardShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? ProfileScreen.terracotta : scheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.25)),
                  ],
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
