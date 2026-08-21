import 'package:chronoplan/core/usage_stats/carve_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the guarantees documented on [planCarve] for one planned outcome.
void expectInvariants({
  required DateTime entryStart,
  required DateTime hourStart,
  required CarvePlan plan,
}) {
  final hourEnd = hourStart.add(const Duration(minutes: 60));
  final entryMinutes = plan.newEntryEnd.difference(entryStart).inMinutes;

  expect(entryMinutes, greaterThanOrEqualTo(1),
      reason: 'the logged entry must keep at least 1 minute');

  var total = entryMinutes;
  for (var i = 0; i < plan.screenBlocks.length; i++) {
    final (start, end) = plan.screenBlocks[i];

    expect(end.isAfter(start), isTrue, reason: 'block $i has end <= start');
    expect(start.isBefore(hourStart), isFalse,
        reason: 'block $i starts before the hour');
    expect(end.isAfter(hourEnd), isFalse,
        reason: 'block $i ends after the hour');

    // No overlap with the (possibly trimmed) entry.
    expect(start.isBefore(plan.newEntryEnd) && end.isAfter(entryStart), isFalse,
        reason: 'block $i overlaps the logged entry');

    // No overlap with any other block.
    for (var j = i + 1; j < plan.screenBlocks.length; j++) {
      final (otherStart, otherEnd) = plan.screenBlocks[j];
      expect(start.isBefore(otherEnd) && end.isAfter(otherStart), isFalse,
          reason: 'blocks $i and $j overlap');
    }

    total += end.difference(start).inMinutes;
  }

  expect(total, lessThanOrEqualTo(60),
      reason: 'the hour must never total more than 60 minutes');
}

void main() {
  final hourStart = DateTime(2026, 7, 14, 15, 0);
  DateTime at(int minute) => hourStart.add(Duration(minutes: minute));

  test('head-aligned short entry, screen fits in the tail → no trim, one block',
      () {
    // 15:00–15:20 logged, 30m of screen time; 40m of tail is plenty.
    final plan = planCarve(
      entryStart: at(0),
      entryEnd: at(20),
      hourStart: hourStart,
      screenMinutes: 30,
    );

    expect(plan.newEntryEnd, at(20), reason: 'the entry must not be trimmed');
    expect(plan.screenBlocks, [(at(20), at(50))]);
    expectInvariants(entryStart: at(0), hourStart: hourStart, plan: plan);
  });

  test('full-hour entry (U=60) + S=35 → entry trimmed to 25, one 35m tail block',
      () {
    final plan = planCarve(
      entryStart: at(0),
      entryEnd: at(60),
      hourStart: hourStart,
      screenMinutes: 35,
    );

    expect(plan.newEntryEnd, at(25));
    expect(plan.newEntryEnd.difference(at(0)).inMinutes, 25);
    expect(plan.screenBlocks, [(at(25), at(60))]);
    expectInvariants(entryStart: at(0), hourStart: hourStart, plan: plan);
  });

  test('mid-hour entry, S bigger than the tail but <= empty → no trim, 2 blocks',
      () {
    // 15:20–15:40 logged: head 20m, tail 20m, empty 40m. S=30 fits without trim.
    final plan = planCarve(
      entryStart: at(20),
      entryEnd: at(40),
      hourStart: hourStart,
      screenMinutes: 30,
    );

    expect(plan.newEntryEnd, at(40), reason: 'the entry must not be trimmed');
    expect(plan.screenBlocks, [
      (at(40), at(60)), // tail filled first, from its start
      (at(10), at(20)), // then the head, ending at entryStart
    ]);
    expectInvariants(entryStart: at(20), hourStart: hourStart, plan: plan);
  });

  test('overflow (U+S>60) with head>0 → trim from the end, entry keeps >= 1 min',
      () {
    // 15:10–15:50 logged (U=40): head 10m, tail 10m, empty 20m. S=50 → trim 30.
    final plan = planCarve(
      entryStart: at(10),
      entryEnd: at(50),
      hourStart: hourStart,
      screenMinutes: 50,
    );

    expect(plan.newEntryEnd, at(20), reason: 'trimmed 30m from the end only');
    expect(plan.newEntryEnd.difference(at(10)).inMinutes, 10);
    expect(plan.screenBlocks, [
      (at(20), at(60)), // freed tail: 10m original + 30m trimmed
      (at(0), at(10)), // head gap
    ]);
    expectInvariants(entryStart: at(10), hourStart: hourStart, plan: plan);
  });

  test('degenerate S=60 with a logged entry → entry keeps exactly 1 min', () {
    final plan = planCarve(
      entryStart: at(0),
      entryEnd: at(60),
      hourStart: hourStart,
      screenMinutes: 60,
    );

    expect(plan.newEntryEnd, at(1));
    expect(plan.newEntryEnd.difference(at(0)).inMinutes, 1);
    expect(plan.screenBlocks, [(at(1), at(60))]);
    expect(plan.screenBlocks.first.$2.difference(plan.screenBlocks.first.$1).inMinutes, 59,
        reason: 'S is reduced to the space actually freed');
    expectInvariants(entryStart: at(0), hourStart: hourStart, plan: plan);
  });

  test('S=60 against a short mid-hour entry still leaves the entry 1 min', () {
    // 15:25–15:35 logged (U=10): head 25m, tail 25m, empty 50m.
    // S=60 → trim 10 wanted, capped to 9 so the entry keeps 1 min; S becomes 59.
    final plan = planCarve(
      entryStart: at(25),
      entryEnd: at(35),
      hourStart: hourStart,
      screenMinutes: 60,
    );

    expect(plan.newEntryEnd, at(26));
    expect(plan.screenBlocks, [
      (at(26), at(60)), // 34m tail
      (at(0), at(25)), // 25m head
    ]);
    expectInvariants(entryStart: at(25), hourStart: hourStart, plan: plan);
  });

  test('the entry start is never moved', () {
    for (final headMinutes in [0, 5, 20, 45]) {
      for (final screenMinutes in [1, 10, 35, 60]) {
        final start = at(headMinutes);
        final end = at(headMinutes + 10 <= 60 ? headMinutes + 10 : 60);
        if (!end.isAfter(start)) continue;

        final plan = planCarve(
          entryStart: start,
          entryEnd: end,
          hourStart: hourStart,
          screenMinutes: screenMinutes,
        );

        expect(plan.newEntryEnd.isAfter(start), isTrue);
        expect(plan.newEntryEnd.isAfter(end), isFalse,
            reason: 'the entry is only ever trimmed, never extended');
        expectInvariants(entryStart: start, hourStart: hourStart, plan: plan);
      }
    }
  });
}
