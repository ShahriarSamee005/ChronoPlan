import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../log_entry/log_entry_sheet.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _routes = ['/', '/day-view', '/routine', '/history'];

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
      body: child,
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

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64 + bottom,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.glassBorder, width: 0.5),
            ),
            color: Color(0x14FFFFFF), // ~8% white
          ),
          padding: EdgeInsets.only(bottom: bottom),
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
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 28),
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
