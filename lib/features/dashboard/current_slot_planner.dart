/// Pure "which routine slot covers the current hour" logic for the Dashboard
/// "Right now" strip.
///
/// Kept free of Flutter/Drift imports so it is directly unit-testable. Callers
/// map their DB `RoutineSlot` rows onto [PlanSlotInput] records before calling
/// in — same record-typedef approach as `routine_overlay_planner.dart`.
library;

/// One routine slot, reduced to what the current-hour pick needs.
typedef PlanSlotInput = ({
  int id,
  int startHour,
  int durationHours,
  int dayOfWeek, // 1=Mon … 7=Sun; 0=applies every day
  bool isActive,
  String label,
  int? categoryId,
});

/// The slot chosen for the current hour, carrying what the widget renders.
typedef PlannedSlot = ({int id, String label, int? categoryId});

/// Returns the routine slot covering [now]'s hour, or null when none applies.
///
/// Applicable = `isActive && (dayOfWeek == now.weekday || dayOfWeek == 0)` —
/// the same rule Day View and the DAO use (NOT the Debrief filter, which omits
/// the isActive check). A slot covers hour `h` when
/// `startHour <= h < startHour + durationHours`; the coverage window is clamped
/// to hour 23 so a slot never wraps into the next day.
///
/// Collision: when several applicable slots cover the hour, the one with the
/// lowest [startHour] wins; ties are broken by lowest [id], so the pick is
/// stable across rebuilds regardless of the input list's order.
PlannedSlot? slotForHour(
  List<PlanSlotInput> slots, {
  required DateTime now,
}) {
  final hour = now.hour;
  final weekday = now.weekday;

  PlanSlotInput? best;
  for (final s in slots) {
    if (!s.isActive) continue;
    if (s.dayOfWeek != weekday && s.dayOfWeek != 0) continue;

    // Coverage, clamped so a slot never wraps past hour 23 into the next day.
    final endHour = (s.startHour + s.durationHours).clamp(0, 24);
    if (hour < s.startHour || hour >= endHour) continue;

    // Lowest startHour wins; tiebreak on lowest id for stability.
    if (best == null ||
        s.startHour < best.startHour ||
        (s.startHour == best.startHour && s.id < best.id)) {
      best = s;
    }
  }

  if (best == null) return null;
  return (id: best.id, label: best.label, categoryId: best.categoryId);
}

/// Resolves a slot's display name: free-text [label] → [categoryName] →
/// "Unlabelled". Mirrors the inline chain in `routine_screen.dart` so the
/// Dashboard strip and the routine editor name a slot the same way.
String resolveSlotName(String label, String? categoryName) {
  if (label.isNotEmpty) return label;
  return categoryName ?? 'Unlabelled';
}
