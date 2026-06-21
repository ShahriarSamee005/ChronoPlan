import 'package:chronoplan/core/database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).categoriesDao.watchAll();
});

final categoryByIdProvider =
    FutureProvider.family<Category?, int>((ref, id) {
  return ref.watch(appDatabaseProvider).categoriesDao.getById(id);
});
