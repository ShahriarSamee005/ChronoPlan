import 'dart:math';

/// Contextual, rotating quotes shown in reminder notifications.
/// Time-of-day aware; occasionally surfaces a funny remark.
class NotificationQuotes {
  NotificationQuotes._();

  static final _rng = Random();

  static const _morning = [
    'Another chance to be the person you meant to be yesterday.',
    'The day is blank — fill it deliberately.',
    'What would make today a win? Start with that.',
    'Your future self is either thanking you or cringing right now.',
    "Good morning. What's the first hour actually for?",
    'Intentions without tracking are just wishes.',
    "The most productive thing you can do right now is see clearly what you're doing.",
    'One logged hour is worth ten planned ones.',
  ];

  static const _midday = [
    'Half the day down. Is it going where you planned?',
    'Time check: is this hour going where you intended?',
    "Logging isn't judgment — it's clarity.",
    'Your afternoon belongs to the you who planned this morning.',
    'Mid-day check-in. Be honest.',
    'Quick gut check: on track?',
    'Three hours left in the workday. Make them count.',
    "You can't improve what you don't measure.",
  ];

  static const _evening = [
    "The day is wrapping up. Don't let it blur — log it.",
    'Evening check-in: any gaps left to fill?',
    'Almost there. How did today actually go?',
    'This hour is yours. Make sure ChronoPlan knows about it.',
    "The day's almost done. One last honest look.",
    'Before you wind down, log the wind-down.',
    'Good days deserve to be recorded.',
  ];

  static const _night = [
    'Night owl. We see you. Log it anyway.',
    "Either you're productive or you're wired — either way, log it.",
    "The world's asleep. What are you up to?",
    'Late night logging: respect.',
    "Still going? Let's at least capture it.",
    "Past midnight — bold productivity choices.",
  ];

  static const _funny = [
    "Those snacks don't count as 'meal prep' but we won't tell.",
    "Refreshing your feed? We'll call it 'market research.'",
    'The algorithm found you. Escape while you can — then log it.',
    "Technically, procrastinating is 'decision paralysis management.'",
    "Your phone's screen time report would like a word...",
    "Doing nothing? That's called 'strategic rest.' Log it.",
    'Ten minutes became an hour. Classic. Log the hour.',
    "You were 'just checking' something, weren't you.",
  ];

  /// Returns a contextual quote for the given hour.
  /// [recentActivity] is reserved for future AI-aware quotes.
  static String quoteForHour(int hour, {String? recentActivity}) {
    // 1-in-6 chance of a funny remark regardless of time
    if (_rng.nextInt(6) == 0) return _funny[_rng.nextInt(_funny.length)];

    final pool = switch (hour) {
      >= 5 && < 11 => _morning,
      >= 11 && < 17 => _midday,
      >= 17 && < 21 => _evening,
      _ => _night,
    };

    return pool[_rng.nextInt(pool.length)];
  }
}
