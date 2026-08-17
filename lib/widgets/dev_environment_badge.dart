import 'package:flutter/material.dart';

/// Small persistent "DEV" badge shown in a corner of the screen. Only ever
/// mounted from [MyApp]'s `MaterialApp.router` builder, gated behind the
/// compile-time-constant `kIsDevEnvironment` — see
/// lib/config/app_environment.dart. That gate, not this widget, is what
/// guarantees it cannot appear in a prod build: the `if (kIsDevEnvironment)`
/// branch around its only call site is stripped by the release compiler
/// when `OPTIMEAL_ENV=prod`, the same way `kDebugMode`-gated code is
/// stripped from release builds.
class DevEnvironmentBadge extends StatelessWidget {
  const DevEnvironmentBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
            ),
            child: const Text(
              'DEV',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
