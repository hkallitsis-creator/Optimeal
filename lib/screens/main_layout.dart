import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/fridge_clearer_screen.dart';
import 'package:optimeal/screens/home_dashboard_screen.dart';
import 'package:optimeal/screens/techniques_media_screen.dart';
import 'package:optimeal/screens/weekly_planner_screen.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

class MainLayout extends StatefulWidget {
  final int currentIndex;
  
  const MainLayout({super.key, this.currentIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;

  final List<Widget> _pages = [
    const HomeDashboardScreen(),
    const FridgeClearerScreen(),
    const WeeklyPlannerScreen(),
    const TechniquesMediaScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Defensive: if an old deep-link or persisted state tries to open a removed
    // tab index, clamp it to the available range.
    _currentIndex = widget.currentIndex.clamp(0, _pages.length - 1);
  }

  @override
  void didUpdateWidget(covariant MainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      setState(() {
        _currentIndex = widget.currentIndex.clamp(0, _pages.length - 1);
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == _currentIndex) {
      // Re-tapping the current tab should still normalize the route so “Home”
      // always returns to the main dashboard location.
      _goToTab(index);
      return;
    }

    setState(() => _currentIndex = index);
    _goToTab(index);
  }

  void _goToTab(int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.home);
        break;
      default:
        context.go(AppRoutes.homeTab(index));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? DarkModeColors.darkSurface : LightModeColors.lightSurface,
          border: Border(
            top: BorderSide(
              color: (isDark ? DarkModeColors.darkOutline : LightModeColors.lightOutline).withValues(alpha: 0.30),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDesignTokens.spaceSM, vertical: AppDesignTokens.spaceXS),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: _buildNavItem(0, Icons.home_rounded, 'Home')),
                Expanded(child: _buildNavItem(1, Icons.kitchen_rounded, 'Fridge')),
                Expanded(child: _buildNavItem(2, Icons.calendar_month_rounded, 'Weekly')),
                Expanded(child: _buildNavItem(3, Icons.play_circle_rounded, 'Techniques & Media')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    
    final selectedColor = AppDesignTokens.ctaTerracotta;
    final unselectedColor = AppDesignTokens.textCharcoal;
    
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizing.minTouchTarget, minWidth: AppSizing.minTouchTarget),
      child: InkWell(
        onTap: () => _onItemTapped(index),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: AppDesignTokens.spaceSM, vertical: AppDesignTokens.spaceXS),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? selectedColor : unselectedColor,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected ? selectedColor : unselectedColor,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
