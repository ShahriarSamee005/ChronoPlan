import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_gate.dart';

class ChronoPlanApp extends StatelessWidget {
  /// Built in `main()` with the first-frame initial location already resolved
  /// from the seen-onboarding flag.
  final GoRouter router;

  const ChronoPlanApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    return MaterialApp.router(
      title: 'ChronoPlan',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // The splash overlays whatever the router built; it never decides the
      // route. The onboarding-vs-dashboard choice stays in main() before runApp.
      builder: (context, child) =>
          SplashGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
