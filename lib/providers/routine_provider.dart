import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import 'database_provider.dart';

final allRoutineSlotsProvider = StreamProvider<List<RoutineSlot>>((ref) {
  return ref.watch(appDatabaseProvider).routineSlotsDao.watchAll();
});
