import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';

/// Single shared database instance for the app lifetime.
/// Overridden in main() with the pre-warmed instance so migrations run
/// before the first frame.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
