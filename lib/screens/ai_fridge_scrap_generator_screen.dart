import 'package:flutter/material.dart';

import 'package:optimeal/screens/fridge_clearer_screen.dart';

/// Backwards-compat wrapper.
///
/// Routes now render [FridgeClearerScreen] directly, but we keep this class so
/// any older imports/builders won’t break.
class AiFridgeScrapGeneratorScreen extends StatelessWidget {
  const AiFridgeScrapGeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) => const FridgeClearerScreen();
}
