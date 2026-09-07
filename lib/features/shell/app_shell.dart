import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/intention_tasks_provider.dart';
import '../log_entry/log_entry_sheet.dart';

/// Floating nav pill dimensions. Screens under the shell must clear this.
class NavBarMetrics {
  const NavBarMetrics._();
  static const double height = 64;
  static const double bottomMargin = 12;
  static const double horizontalMargin = 16;
  static const double radius = 32;

  /// Breathing room between the last item and the pill.
  static const double contentGap = 16;

  /// Bottom padding a scrollable under the shell needs so its last row
  /// is not hidden by the floating pill.
  static double clearance(BuildContext context) =>
      height + bottomMargin + contentGap + MediaQuery.of(context).padding.bottom;
}

/// Persists for the whole app session (created once at the ShellRoute,
/// never popped — full-page routes like /debrief are pushed on top of it,
/// not in place of it), which is why the across-midnight lifecycle observer
/// lives here rather than on any individual screen.
class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _routes = ['/', '/day-view', '/routine', '/history'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Crossed midnight while backgrounded (resident, not killed): flip the
    // one shared day key so every task consumer switches to the new day's
    // providers together, instead of each drifting to "today" independently.
    final newDay = normalizeDay(DateTime.now());
    if (ref.read(currentDayProvider) != newDay) {
      ref.read(currentDayProvider.notifier).state = newDay;
    }
  }

  int _locationIndex(String location) {
    final idx = _routes.indexOf(location);
    return idx < 0 ? 0 : idx;
  }

  void _onTabTap(BuildContext context, int index) {
    context.go(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _locationIndex(location);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: widget.child,
      bottomNavigationBar: _GlassNavBar(
        currentIndex: currentIndex,
        onTap: (i) => _onTabTap(context, i),
        onAddTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const LogEntrySheet(),
        ),
      ),
    );
  }
}

// ── Glassmorphic nav bar ──────────────────────────────────────────────────────

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  final VoidCallback onAddTap;

  const _GlassNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final accent = AppColors.accentForHour(DateTime.now().hour);

    return Padding(
      padding: EdgeInsets.only(
        left: NavBarMetrics.horizontalMargin,
        right: NavBarMetrics.horizontalMargin,
        bottom: NavBarMetrics.bottomMargin + bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NavBarMetrics.radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: NavBarMetrics.height,
            decoration: BoxDecoration(
              // The pill now sits over the gradient on all sides, so labels need
              // a slightly stronger surface than the old flush bar (~12% white).
              color: const Color(0x1FFFFFFF),
              border: Border.all(color: AppColors.glassBorder, width: 0.5),
              borderRadius: BorderRadius.circular(NavBarMetrics.radius),
            ),
            child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                index: 0,
                current: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.view_day_outlined,
                activeIcon: Icons.view_day_rounded,
                label: 'Day',
                index: 1,
                current: currentIndex,
                onTap: onTap,
              ),
              // Centre add button
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: onAddTap,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.18),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(Icons.add_rounded,
                          color: AppColors.onAccentForHour(DateTime.now().hour),
                          size: 28),
                    ),
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.calendar_today_outlined,
                activeIcon: Icons.calendar_today_rounded,
                label: 'Routine',
                index: 2,
                current: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                label: 'History',
                index: 3,
                current: currentIndex,
                onTap: onTap,
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int current;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    final accent = AppColors.accentForHour(DateTime.now().hour);

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                active ? activeIcon : icon,
                key: ValueKey(active),
                color: active ? accent : AppColors.textMuted,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: active ? accent : AppColors.textMuted,
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
