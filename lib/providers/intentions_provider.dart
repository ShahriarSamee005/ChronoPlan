import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import 'database_provider.dart';

final todayIntentionProvider = StreamProvider<DailyIntention?>((ref) {
  return ref.watch(appDatabaseProvider).intentionsDao.watchForDate(DateTime.now());
});
