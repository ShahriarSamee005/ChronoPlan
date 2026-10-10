// dart format width=80
// GENERATED CODE, DO NOT EDIT BY HAND.
// ignore_for_file: type=lint
import 'package:drift/drift.dart';
import 'package:drift/internal/migrations.dart';
import 'schema_v8.dart' as v8;
import 'schema_v9.dart' as v9;

class GeneratedHelper implements SchemaInstantiationHelper {
  @override
  GeneratedDatabase databaseForVersion(QueryExecutor db, int version) {
    switch (version) {
      case 8:
        return v8.DatabaseAtV8(db);
      case 9:
        return v9.DatabaseAtV9(db);
      default:
        throw MissingSchemaException(version, versions);
    }
  }

  static const versions = const [8, 9];
}
