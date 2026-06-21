import 'package:go_router/go_router.dart';

import 'features/about/about_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/day_view/day_view_screen.dart';
import 'features/debrief/debrief_screen.dart';
import 'features/history/history_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/routine/routine_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    // ── Shell routes (persistent bottom nav) ──────────────────────────────
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/day-view',
          builder: (context, state) => DayViewScreen(
            initialDate: state.extra as DateTime?,
          ),
        ),
        GoRoute(
          path: '/routine',
          builder: (context, state) => const RoutineScreen(),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
      ],
    ),
    // ── Full-page routes (pushed over shell) ──────────────────────────────
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const AboutScreen(),
    ),
    GoRoute(
      path: '/debrief',
      builder: (context, state) => const DebriefScreen(),
    ),
    GoRoute(
      path: '/categories',
      builder: (context, state) => const CategoriesScreen(),
    ),
  ],
);
