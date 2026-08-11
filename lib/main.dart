import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'theme.dart';
import 'nav.dart';
import 'package:optimeal/services/user_profile_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';

/// Main entry point for the application
///
/// This sets up:
/// - Provider state management (ThemeProvider, CounterProvider)
/// - go_router navigation
/// - Material 3 theming with light/dark modes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NOTE:
  // - In Dreamflow, please also connect Supabase via the Supabase panel.
  // - These credentials are safe to embed client-side (anon/publishable key).
  //   Still, for production you may prefer environment-based config.
  const supabaseUrl = 'https://xwugnhzlnfgmczkbbcbh.supabase.co';
  const supabaseAnonKey = 'sb_publishable_fflcK-rDIAE4-wyuHLdjLw_IVrB7Rzn';

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Ensure there is always a valid session (auth.uid()) for RLS-protected writes,
  // even when the user never explicitly signs up.
  //
  // IMPORTANT: This must never block app startup if it fails.
  try {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  } catch (e, st) {
    debugPrint('Anonymous Supabase sign-in failed (continuing startup): $e');
    debugPrint('$st');
  }

  // No-op until real RevenueCat keys exist (see entitlement_service.dart) —
  // must never block app startup, same reasoning as anonymous sign-in above.
  try {
    await EntitlementService.instance.configure();
  } catch (e, st) {
    debugPrint('EntitlementService.configure failed (continuing startup): $e');
    debugPrint('$st');
  }

  final profileController = UserProfileController(UserProfileService());
  await profileController.load();

  final ingredientPrepController = IngredientPrepController();
  await ingredientPrepController.load();

  runApp(MyApp(profileController: profileController, ingredientPrepController: ingredientPrepController));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.profileController, required this.ingredientPrepController});

  final UserProfileController profileController;
  final IngredientPrepController ingredientPrepController;

  ThemeData _buildUnifiedTheme() {
    final scheme = ColorScheme.light(
      primary: LightModeColors.lightPrimary,
      onPrimary: LightModeColors.lightOnPrimary,
      secondary: LightModeColors.lightSecondary,
      onSecondary: LightModeColors.lightOnSecondary,
      tertiary: LightModeColors.lightTertiary,
      onTertiary: LightModeColors.lightOnTertiary,
      error: LightModeColors.lightError,
      onError: LightModeColors.lightOnError,
      surface: LightModeColors.lightSurface,
      onSurface: LightModeColors.lightOnSurface,
      outline: LightModeColors.lightOutline,
    );

    // Poppins text theme applied app-wide.
    // Note: we also apply the scheme's colors so text stays consistent.
    final textTheme = GoogleFonts.poppinsTextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: LightModeColors.lightBackground,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LightModeColors.lightPrimary,
          foregroundColor: LightModeColors.lightOnPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      cardTheme: const CardThemeData(
        color: LightModeColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: LightModeColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profileController),
        ChangeNotifierProvider.value(value: ingredientPrepController),
      ],
      child: MaterialApp.router(
        title: AppBrand.appName,
        debugShowCheckedModeBanner: false,
        theme: _buildUnifiedTheme(),
        themeMode: ThemeMode.light,
        routerConfig: AppRouter.createRouter(profileController),
      ),
    );
  }
}
