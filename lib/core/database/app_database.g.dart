// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 50),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _colorValueMeta =
      const VerificationMeta('colorValue');
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
      'color_value', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isSystemMeta =
      const VerificationMeta('isSystem');
  @override
  late final GeneratedColumn<bool> isSystem = GeneratedColumn<bool>(
      'is_system', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_system" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, colorValue, isArchived, isSystem, createdAt, userId, syncId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
          _colorValueMeta,
          colorValue.isAcceptableOrUnknown(
              data['color_value']!, _colorValueMeta));
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('is_system')) {
      context.handle(_isSystemMeta,
          isSystem.isAcceptableOrUnknown(data['is_system']!, _isSystemMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      colorValue: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}color_value'])!,
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      isSystem: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_system'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;
  final int colorValue;
  final bool isArchived;
  final bool isSystem;
  final DateTime createdAt;
  final String? userId;
  final String? syncId;
  const Category(
      {required this.id,
      required this.name,
      required this.colorValue,
      required this.isArchived,
      required this.isSystem,
      required this.createdAt,
      this.userId,
      this.syncId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_system'] = Variable<bool>(isSystem);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: Value(colorValue),
      isArchived: Value(isArchived),
      isSystem: Value(isSystem),
      createdAt: Value(createdAt),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isSystem: serializer.fromJson<bool>(json['isSystem']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      userId: serializer.fromJson<String?>(json['userId']),
      syncId: serializer.fromJson<String?>(json['syncId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isSystem': serializer.toJson<bool>(isSystem),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'userId': serializer.toJson<String?>(userId),
      'syncId': serializer.toJson<String?>(syncId),
    };
  }

  Category copyWith(
          {int? id,
          String? name,
          int? colorValue,
          bool? isArchived,
          bool? isSystem,
          DateTime? createdAt,
          Value<String?> userId = const Value.absent(),
          Value<String?> syncId = const Value.absent()}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        isArchived: isArchived ?? this.isArchived,
        isSystem: isSystem ?? this.isSystem,
        createdAt: createdAt ?? this.createdAt,
        userId: userId.present ? userId.value : this.userId,
        syncId: syncId.present ? syncId.value : this.syncId,
      );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorValue:
          data.colorValue.present ? data.colorValue.value : this.colorValue,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      isSystem: data.isSystem.present ? data.isSystem.value : this.isSystem,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      userId: data.userId.present ? data.userId.value : this.userId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isArchived: $isArchived, ')
          ..write('isSystem: $isSystem, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, colorValue, isArchived, isSystem, createdAt, userId, syncId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.isArchived == this.isArchived &&
          other.isSystem == this.isSystem &&
          other.createdAt == this.createdAt &&
          other.userId == this.userId &&
          other.syncId == this.syncId);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<bool> isArchived;
  final Value<bool> isSystem;
  final Value<DateTime> createdAt;
  final Value<String?> userId;
  final Value<String?> syncId;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int colorValue,
    this.isArchived = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  })  : name = Value(name),
        colorValue = Value(colorValue);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<bool>? isArchived,
    Expression<bool>? isSystem,
    Expression<DateTime>? createdAt,
    Expression<String>? userId,
    Expression<String>? syncId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (isArchived != null) 'is_archived': isArchived,
      if (isSystem != null) 'is_system': isSystem,
      if (createdAt != null) 'created_at': createdAt,
      if (userId != null) 'user_id': userId,
      if (syncId != null) 'sync_id': syncId,
    });
  }

  CategoriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<int>? colorValue,
      Value<bool>? isArchived,
      Value<bool>? isSystem,
      Value<DateTime>? createdAt,
      Value<String?>? userId,
      Value<String?>? syncId}) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      isArchived: isArchived ?? this.isArchived,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      syncId: syncId ?? this.syncId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isSystem.present) {
      map['is_system'] = Variable<bool>(isSystem.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isArchived: $isArchived, ')
          ..write('isSystem: $isSystem, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }
}

class $LogEntriesTable extends LogEntries
    with TableInfo<$LogEntriesTable, LogEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LogEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _startTimeMeta =
      const VerificationMeta('startTime');
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
      'start_time', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endTimeMeta =
      const VerificationMeta('endTime');
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
      'end_time', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isRealTimeMeta =
      const VerificationMeta('isRealTime');
  @override
  late final GeneratedColumn<bool> isRealTime = GeneratedColumn<bool>(
      'is_real_time', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_real_time" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isAiParsedMeta =
      const VerificationMeta('isAiParsed');
  @override
  late final GeneratedColumn<bool> isAiParsed = GeneratedColumn<bool>(
      'is_ai_parsed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_ai_parsed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        description,
        categoryId,
        startTime,
        endTime,
        isRealTime,
        isAiParsed,
        createdAt,
        userId,
        syncId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'log_entries';
  @override
  VerificationContext validateIntegrity(Insertable<LogEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('start_time')) {
      context.handle(_startTimeMeta,
          startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta));
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(_endTimeMeta,
          endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta));
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('is_real_time')) {
      context.handle(
          _isRealTimeMeta,
          isRealTime.isAcceptableOrUnknown(
              data['is_real_time']!, _isRealTimeMeta));
    }
    if (data.containsKey('is_ai_parsed')) {
      context.handle(
          _isAiParsedMeta,
          isAiParsed.isAcceptableOrUnknown(
              data['is_ai_parsed']!, _isAiParsedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LogEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LogEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      startTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}start_time'])!,
      endTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}end_time'])!,
      isRealTime: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_real_time'])!,
      isAiParsed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_ai_parsed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
    );
  }

  @override
  $LogEntriesTable createAlias(String alias) {
    return $LogEntriesTable(attachedDatabase, alias);
  }
}

class LogEntry extends DataClass implements Insertable<LogEntry> {
  final int id;
  final String description;
  final int? categoryId;
  final DateTime startTime;
  final DateTime endTime;
  final bool isRealTime;
  final bool isAiParsed;
  final DateTime createdAt;
  final String? userId;
  final String? syncId;
  const LogEntry(
      {required this.id,
      required this.description,
      this.categoryId,
      required this.startTime,
      required this.endTime,
      required this.isRealTime,
      required this.isAiParsed,
      required this.createdAt,
      this.userId,
      this.syncId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['start_time'] = Variable<DateTime>(startTime);
    map['end_time'] = Variable<DateTime>(endTime);
    map['is_real_time'] = Variable<bool>(isRealTime);
    map['is_ai_parsed'] = Variable<bool>(isAiParsed);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    return map;
  }

  LogEntriesCompanion toCompanion(bool nullToAbsent) {
    return LogEntriesCompanion(
      id: Value(id),
      description: Value(description),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      startTime: Value(startTime),
      endTime: Value(endTime),
      isRealTime: Value(isRealTime),
      isAiParsed: Value(isAiParsed),
      createdAt: Value(createdAt),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
    );
  }

  factory LogEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LogEntry(
      id: serializer.fromJson<int>(json['id']),
      description: serializer.fromJson<String>(json['description']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime>(json['endTime']),
      isRealTime: serializer.fromJson<bool>(json['isRealTime']),
      isAiParsed: serializer.fromJson<bool>(json['isAiParsed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      userId: serializer.fromJson<String?>(json['userId']),
      syncId: serializer.fromJson<String?>(json['syncId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'description': serializer.toJson<String>(description),
      'categoryId': serializer.toJson<int?>(categoryId),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime>(endTime),
      'isRealTime': serializer.toJson<bool>(isRealTime),
      'isAiParsed': serializer.toJson<bool>(isAiParsed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'userId': serializer.toJson<String?>(userId),
      'syncId': serializer.toJson<String?>(syncId),
    };
  }

  LogEntry copyWith(
          {int? id,
          String? description,
          Value<int?> categoryId = const Value.absent(),
          DateTime? startTime,
          DateTime? endTime,
          bool? isRealTime,
          bool? isAiParsed,
          DateTime? createdAt,
          Value<String?> userId = const Value.absent(),
          Value<String?> syncId = const Value.absent()}) =>
      LogEntry(
        id: id ?? this.id,
        description: description ?? this.description,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        isRealTime: isRealTime ?? this.isRealTime,
        isAiParsed: isAiParsed ?? this.isAiParsed,
        createdAt: createdAt ?? this.createdAt,
        userId: userId.present ? userId.value : this.userId,
        syncId: syncId.present ? syncId.value : this.syncId,
      );
  LogEntry copyWithCompanion(LogEntriesCompanion data) {
    return LogEntry(
      id: data.id.present ? data.id.value : this.id,
      description:
          data.description.present ? data.description.value : this.description,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      isRealTime:
          data.isRealTime.present ? data.isRealTime.value : this.isRealTime,
      isAiParsed:
          data.isAiParsed.present ? data.isAiParsed.value : this.isAiParsed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      userId: data.userId.present ? data.userId.value : this.userId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LogEntry(')
          ..write('id: $id, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isRealTime: $isRealTime, ')
          ..write('isAiParsed: $isAiParsed, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, description, categoryId, startTime,
      endTime, isRealTime, isAiParsed, createdAt, userId, syncId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LogEntry &&
          other.id == this.id &&
          other.description == this.description &&
          other.categoryId == this.categoryId &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.isRealTime == this.isRealTime &&
          other.isAiParsed == this.isAiParsed &&
          other.createdAt == this.createdAt &&
          other.userId == this.userId &&
          other.syncId == this.syncId);
}

class LogEntriesCompanion extends UpdateCompanion<LogEntry> {
  final Value<int> id;
  final Value<String> description;
  final Value<int?> categoryId;
  final Value<DateTime> startTime;
  final Value<DateTime> endTime;
  final Value<bool> isRealTime;
  final Value<bool> isAiParsed;
  final Value<DateTime> createdAt;
  final Value<String?> userId;
  final Value<String?> syncId;
  const LogEntriesCompanion({
    this.id = const Value.absent(),
    this.description = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.isRealTime = const Value.absent(),
    this.isAiParsed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  });
  LogEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.description = const Value.absent(),
    this.categoryId = const Value.absent(),
    required DateTime startTime,
    required DateTime endTime,
    this.isRealTime = const Value.absent(),
    this.isAiParsed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  })  : startTime = Value(startTime),
        endTime = Value(endTime);
  static Insertable<LogEntry> custom({
    Expression<int>? id,
    Expression<String>? description,
    Expression<int>? categoryId,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<bool>? isRealTime,
    Expression<bool>? isAiParsed,
    Expression<DateTime>? createdAt,
    Expression<String>? userId,
    Expression<String>? syncId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (description != null) 'description': description,
      if (categoryId != null) 'category_id': categoryId,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (isRealTime != null) 'is_real_time': isRealTime,
      if (isAiParsed != null) 'is_ai_parsed': isAiParsed,
      if (createdAt != null) 'created_at': createdAt,
      if (userId != null) 'user_id': userId,
      if (syncId != null) 'sync_id': syncId,
    });
  }

  LogEntriesCompanion copyWith(
      {Value<int>? id,
      Value<String>? description,
      Value<int?>? categoryId,
      Value<DateTime>? startTime,
      Value<DateTime>? endTime,
      Value<bool>? isRealTime,
      Value<bool>? isAiParsed,
      Value<DateTime>? createdAt,
      Value<String?>? userId,
      Value<String?>? syncId}) {
    return LogEntriesCompanion(
      id: id ?? this.id,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isRealTime: isRealTime ?? this.isRealTime,
      isAiParsed: isAiParsed ?? this.isAiParsed,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      syncId: syncId ?? this.syncId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (isRealTime.present) {
      map['is_real_time'] = Variable<bool>(isRealTime.value);
    }
    if (isAiParsed.present) {
      map['is_ai_parsed'] = Variable<bool>(isAiParsed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LogEntriesCompanion(')
          ..write('id: $id, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isRealTime: $isRealTime, ')
          ..write('isAiParsed: $isAiParsed, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }
}

class $RoutineSlotsTable extends RoutineSlots
    with TableInfo<$RoutineSlotsTable, RoutineSlot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutineSlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
      'category_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _dayOfWeekMeta =
      const VerificationMeta('dayOfWeek');
  @override
  late final GeneratedColumn<int> dayOfWeek = GeneratedColumn<int>(
      'day_of_week', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _startHourMeta =
      const VerificationMeta('startHour');
  @override
  late final GeneratedColumn<int> startHour = GeneratedColumn<int>(
      'start_hour', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _durationHoursMeta =
      const VerificationMeta('durationHours');
  @override
  late final GeneratedColumn<int> durationHours = GeneratedColumn<int>(
      'duration_hours', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        categoryId,
        label,
        dayOfWeek,
        startHour,
        durationHours,
        isActive,
        createdAt,
        userId,
        syncId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routine_slots';
  @override
  VerificationContext validateIntegrity(Insertable<RoutineSlot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    }
    if (data.containsKey('day_of_week')) {
      context.handle(
          _dayOfWeekMeta,
          dayOfWeek.isAcceptableOrUnknown(
              data['day_of_week']!, _dayOfWeekMeta));
    } else if (isInserting) {
      context.missing(_dayOfWeekMeta);
    }
    if (data.containsKey('start_hour')) {
      context.handle(_startHourMeta,
          startHour.isAcceptableOrUnknown(data['start_hour']!, _startHourMeta));
    } else if (isInserting) {
      context.missing(_startHourMeta);
    }
    if (data.containsKey('duration_hours')) {
      context.handle(
          _durationHoursMeta,
          durationHours.isAcceptableOrUnknown(
              data['duration_hours']!, _durationHoursMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoutineSlot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoutineSlot(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}category_id']),
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      dayOfWeek: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}day_of_week'])!,
      startHour: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_hour'])!,
      durationHours: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_hours'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
    );
  }

  @override
  $RoutineSlotsTable createAlias(String alias) {
    return $RoutineSlotsTable(attachedDatabase, alias);
  }
}

class RoutineSlot extends DataClass implements Insertable<RoutineSlot> {
  final int id;
  final int? categoryId;
  final String label;
  final int dayOfWeek;
  final int startHour;
  final int durationHours;
  final bool isActive;
  final DateTime createdAt;
  final String? userId;
  final String? syncId;
  const RoutineSlot(
      {required this.id,
      this.categoryId,
      required this.label,
      required this.dayOfWeek,
      required this.startHour,
      required this.durationHours,
      required this.isActive,
      required this.createdAt,
      this.userId,
      this.syncId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['label'] = Variable<String>(label);
    map['day_of_week'] = Variable<int>(dayOfWeek);
    map['start_hour'] = Variable<int>(startHour);
    map['duration_hours'] = Variable<int>(durationHours);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    return map;
  }

  RoutineSlotsCompanion toCompanion(bool nullToAbsent) {
    return RoutineSlotsCompanion(
      id: Value(id),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      label: Value(label),
      dayOfWeek: Value(dayOfWeek),
      startHour: Value(startHour),
      durationHours: Value(durationHours),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
    );
  }

  factory RoutineSlot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoutineSlot(
      id: serializer.fromJson<int>(json['id']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      label: serializer.fromJson<String>(json['label']),
      dayOfWeek: serializer.fromJson<int>(json['dayOfWeek']),
      startHour: serializer.fromJson<int>(json['startHour']),
      durationHours: serializer.fromJson<int>(json['durationHours']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      userId: serializer.fromJson<String?>(json['userId']),
      syncId: serializer.fromJson<String?>(json['syncId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'categoryId': serializer.toJson<int?>(categoryId),
      'label': serializer.toJson<String>(label),
      'dayOfWeek': serializer.toJson<int>(dayOfWeek),
      'startHour': serializer.toJson<int>(startHour),
      'durationHours': serializer.toJson<int>(durationHours),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'userId': serializer.toJson<String?>(userId),
      'syncId': serializer.toJson<String?>(syncId),
    };
  }

  RoutineSlot copyWith(
          {int? id,
          Value<int?> categoryId = const Value.absent(),
          String? label,
          int? dayOfWeek,
          int? startHour,
          int? durationHours,
          bool? isActive,
          DateTime? createdAt,
          Value<String?> userId = const Value.absent(),
          Value<String?> syncId = const Value.absent()}) =>
      RoutineSlot(
        id: id ?? this.id,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        label: label ?? this.label,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startHour: startHour ?? this.startHour,
        durationHours: durationHours ?? this.durationHours,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        userId: userId.present ? userId.value : this.userId,
        syncId: syncId.present ? syncId.value : this.syncId,
      );
  RoutineSlot copyWithCompanion(RoutineSlotsCompanion data) {
    return RoutineSlot(
      id: data.id.present ? data.id.value : this.id,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      label: data.label.present ? data.label.value : this.label,
      dayOfWeek: data.dayOfWeek.present ? data.dayOfWeek.value : this.dayOfWeek,
      startHour: data.startHour.present ? data.startHour.value : this.startHour,
      durationHours: data.durationHours.present
          ? data.durationHours.value
          : this.durationHours,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      userId: data.userId.present ? data.userId.value : this.userId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoutineSlot(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('label: $label, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('startHour: $startHour, ')
          ..write('durationHours: $durationHours, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, categoryId, label, dayOfWeek, startHour,
      durationHours, isActive, createdAt, userId, syncId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutineSlot &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.label == this.label &&
          other.dayOfWeek == this.dayOfWeek &&
          other.startHour == this.startHour &&
          other.durationHours == this.durationHours &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.userId == this.userId &&
          other.syncId == this.syncId);
}

class RoutineSlotsCompanion extends UpdateCompanion<RoutineSlot> {
  final Value<int> id;
  final Value<int?> categoryId;
  final Value<String> label;
  final Value<int> dayOfWeek;
  final Value<int> startHour;
  final Value<int> durationHours;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<String?> userId;
  final Value<String?> syncId;
  const RoutineSlotsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.label = const Value.absent(),
    this.dayOfWeek = const Value.absent(),
    this.startHour = const Value.absent(),
    this.durationHours = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  });
  RoutineSlotsCompanion.insert({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.label = const Value.absent(),
    required int dayOfWeek,
    required int startHour,
    this.durationHours = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  })  : dayOfWeek = Value(dayOfWeek),
        startHour = Value(startHour);
  static Insertable<RoutineSlot> custom({
    Expression<int>? id,
    Expression<int>? categoryId,
    Expression<String>? label,
    Expression<int>? dayOfWeek,
    Expression<int>? startHour,
    Expression<int>? durationHours,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<String>? userId,
    Expression<String>? syncId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (label != null) 'label': label,
      if (dayOfWeek != null) 'day_of_week': dayOfWeek,
      if (startHour != null) 'start_hour': startHour,
      if (durationHours != null) 'duration_hours': durationHours,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (userId != null) 'user_id': userId,
      if (syncId != null) 'sync_id': syncId,
    });
  }

  RoutineSlotsCompanion copyWith(
      {Value<int>? id,
      Value<int?>? categoryId,
      Value<String>? label,
      Value<int>? dayOfWeek,
      Value<int>? startHour,
      Value<int>? durationHours,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<String?>? userId,
      Value<String?>? syncId}) {
    return RoutineSlotsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      label: label ?? this.label,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startHour: startHour ?? this.startHour,
      durationHours: durationHours ?? this.durationHours,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      syncId: syncId ?? this.syncId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (dayOfWeek.present) {
      map['day_of_week'] = Variable<int>(dayOfWeek.value);
    }
    if (startHour.present) {
      map['start_hour'] = Variable<int>(startHour.value);
    }
    if (durationHours.present) {
      map['duration_hours'] = Variable<int>(durationHours.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutineSlotsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('label: $label, ')
          ..write('dayOfWeek: $dayOfWeek, ')
          ..write('startHour: $startHour, ')
          ..write('durationHours: $durationHours, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }
}

class $DailyIntentionsTable extends DailyIntentions
    with TableInfo<$DailyIntentionsTable, DailyIntention> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyIntentionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _intentionMeta =
      const VerificationMeta('intention');
  @override
  late final GeneratedColumn<String> intention = GeneratedColumn<String>(
      'intention', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
      'date', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _wasReflectedMeta =
      const VerificationMeta('wasReflected');
  @override
  late final GeneratedColumn<bool> wasReflected = GeneratedColumn<bool>(
      'was_reflected', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("was_reflected" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _verdictPositiveMeta =
      const VerificationMeta('verdictPositive');
  @override
  late final GeneratedColumn<bool> verdictPositive = GeneratedColumn<bool>(
      'verdict_positive', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("verdict_positive" IN (0, 1))'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
      'sync_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        intention,
        date,
        wasReflected,
        verdictPositive,
        createdAt,
        userId,
        syncId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_intentions';
  @override
  VerificationContext validateIntegrity(Insertable<DailyIntention> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('intention')) {
      context.handle(_intentionMeta,
          intention.isAcceptableOrUnknown(data['intention']!, _intentionMeta));
    } else if (isInserting) {
      context.missing(_intentionMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('was_reflected')) {
      context.handle(
          _wasReflectedMeta,
          wasReflected.isAcceptableOrUnknown(
              data['was_reflected']!, _wasReflectedMeta));
    }
    if (data.containsKey('verdict_positive')) {
      context.handle(
          _verdictPositiveMeta,
          verdictPositive.isAcceptableOrUnknown(
              data['verdict_positive']!, _verdictPositiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(_syncIdMeta,
          syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyIntention map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyIntention(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      intention: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}intention'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date'])!,
      wasReflected: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}was_reflected'])!,
      verdictPositive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}verdict_positive']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      syncId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_id']),
    );
  }

  @override
  $DailyIntentionsTable createAlias(String alias) {
    return $DailyIntentionsTable(attachedDatabase, alias);
  }
}

class DailyIntention extends DataClass implements Insertable<DailyIntention> {
  final int id;
  final String intention;
  final DateTime date;
  final bool wasReflected;
  final bool? verdictPositive;
  final DateTime createdAt;
  final String? userId;
  final String? syncId;
  const DailyIntention(
      {required this.id,
      required this.intention,
      required this.date,
      required this.wasReflected,
      this.verdictPositive,
      required this.createdAt,
      this.userId,
      this.syncId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['intention'] = Variable<String>(intention);
    map['date'] = Variable<DateTime>(date);
    map['was_reflected'] = Variable<bool>(wasReflected);
    if (!nullToAbsent || verdictPositive != null) {
      map['verdict_positive'] = Variable<bool>(verdictPositive);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || syncId != null) {
      map['sync_id'] = Variable<String>(syncId);
    }
    return map;
  }

  DailyIntentionsCompanion toCompanion(bool nullToAbsent) {
    return DailyIntentionsCompanion(
      id: Value(id),
      intention: Value(intention),
      date: Value(date),
      wasReflected: Value(wasReflected),
      verdictPositive: verdictPositive == null && nullToAbsent
          ? const Value.absent()
          : Value(verdictPositive),
      createdAt: Value(createdAt),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      syncId:
          syncId == null && nullToAbsent ? const Value.absent() : Value(syncId),
    );
  }

  factory DailyIntention.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyIntention(
      id: serializer.fromJson<int>(json['id']),
      intention: serializer.fromJson<String>(json['intention']),
      date: serializer.fromJson<DateTime>(json['date']),
      wasReflected: serializer.fromJson<bool>(json['wasReflected']),
      verdictPositive: serializer.fromJson<bool?>(json['verdictPositive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      userId: serializer.fromJson<String?>(json['userId']),
      syncId: serializer.fromJson<String?>(json['syncId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'intention': serializer.toJson<String>(intention),
      'date': serializer.toJson<DateTime>(date),
      'wasReflected': serializer.toJson<bool>(wasReflected),
      'verdictPositive': serializer.toJson<bool?>(verdictPositive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'userId': serializer.toJson<String?>(userId),
      'syncId': serializer.toJson<String?>(syncId),
    };
  }

  DailyIntention copyWith(
          {int? id,
          String? intention,
          DateTime? date,
          bool? wasReflected,
          Value<bool?> verdictPositive = const Value.absent(),
          DateTime? createdAt,
          Value<String?> userId = const Value.absent(),
          Value<String?> syncId = const Value.absent()}) =>
      DailyIntention(
        id: id ?? this.id,
        intention: intention ?? this.intention,
        date: date ?? this.date,
        wasReflected: wasReflected ?? this.wasReflected,
        verdictPositive: verdictPositive.present
            ? verdictPositive.value
            : this.verdictPositive,
        createdAt: createdAt ?? this.createdAt,
        userId: userId.present ? userId.value : this.userId,
        syncId: syncId.present ? syncId.value : this.syncId,
      );
  DailyIntention copyWithCompanion(DailyIntentionsCompanion data) {
    return DailyIntention(
      id: data.id.present ? data.id.value : this.id,
      intention: data.intention.present ? data.intention.value : this.intention,
      date: data.date.present ? data.date.value : this.date,
      wasReflected: data.wasReflected.present
          ? data.wasReflected.value
          : this.wasReflected,
      verdictPositive: data.verdictPositive.present
          ? data.verdictPositive.value
          : this.verdictPositive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      userId: data.userId.present ? data.userId.value : this.userId,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyIntention(')
          ..write('id: $id, ')
          ..write('intention: $intention, ')
          ..write('date: $date, ')
          ..write('wasReflected: $wasReflected, ')
          ..write('verdictPositive: $verdictPositive, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, intention, date, wasReflected,
      verdictPositive, createdAt, userId, syncId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyIntention &&
          other.id == this.id &&
          other.intention == this.intention &&
          other.date == this.date &&
          other.wasReflected == this.wasReflected &&
          other.verdictPositive == this.verdictPositive &&
          other.createdAt == this.createdAt &&
          other.userId == this.userId &&
          other.syncId == this.syncId);
}

class DailyIntentionsCompanion extends UpdateCompanion<DailyIntention> {
  final Value<int> id;
  final Value<String> intention;
  final Value<DateTime> date;
  final Value<bool> wasReflected;
  final Value<bool?> verdictPositive;
  final Value<DateTime> createdAt;
  final Value<String?> userId;
  final Value<String?> syncId;
  const DailyIntentionsCompanion({
    this.id = const Value.absent(),
    this.intention = const Value.absent(),
    this.date = const Value.absent(),
    this.wasReflected = const Value.absent(),
    this.verdictPositive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  });
  DailyIntentionsCompanion.insert({
    this.id = const Value.absent(),
    required String intention,
    required DateTime date,
    this.wasReflected = const Value.absent(),
    this.verdictPositive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.userId = const Value.absent(),
    this.syncId = const Value.absent(),
  })  : intention = Value(intention),
        date = Value(date);
  static Insertable<DailyIntention> custom({
    Expression<int>? id,
    Expression<String>? intention,
    Expression<DateTime>? date,
    Expression<bool>? wasReflected,
    Expression<bool>? verdictPositive,
    Expression<DateTime>? createdAt,
    Expression<String>? userId,
    Expression<String>? syncId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (intention != null) 'intention': intention,
      if (date != null) 'date': date,
      if (wasReflected != null) 'was_reflected': wasReflected,
      if (verdictPositive != null) 'verdict_positive': verdictPositive,
      if (createdAt != null) 'created_at': createdAt,
      if (userId != null) 'user_id': userId,
      if (syncId != null) 'sync_id': syncId,
    });
  }

  DailyIntentionsCompanion copyWith(
      {Value<int>? id,
      Value<String>? intention,
      Value<DateTime>? date,
      Value<bool>? wasReflected,
      Value<bool?>? verdictPositive,
      Value<DateTime>? createdAt,
      Value<String?>? userId,
      Value<String?>? syncId}) {
    return DailyIntentionsCompanion(
      id: id ?? this.id,
      intention: intention ?? this.intention,
      date: date ?? this.date,
      wasReflected: wasReflected ?? this.wasReflected,
      verdictPositive: verdictPositive ?? this.verdictPositive,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      syncId: syncId ?? this.syncId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (intention.present) {
      map['intention'] = Variable<String>(intention.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (wasReflected.present) {
      map['was_reflected'] = Variable<bool>(wasReflected.value);
    }
    if (verdictPositive.present) {
      map['verdict_positive'] = Variable<bool>(verdictPositive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyIntentionsCompanion(')
          ..write('id: $id, ')
          ..write('intention: $intention, ')
          ..write('date: $date, ')
          ..write('wasReflected: $wasReflected, ')
          ..write('verdictPositive: $verdictPositive, ')
          ..write('createdAt: $createdAt, ')
          ..write('userId: $userId, ')
          ..write('syncId: $syncId')
          ..write(')'))
        .toString();
  }
}

class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, UserSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _reminderModeMeta =
      const VerificationMeta('reminderMode');
  @override
  late final GeneratedColumn<String> reminderMode = GeneratedColumn<String>(
      'reminder_mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('gentle'));
  static const VerificationMeta _strictIntervalMinutesMeta =
      const VerificationMeta('strictIntervalMinutes');
  @override
  late final GeneratedColumn<int> strictIntervalMinutes = GeneratedColumn<int>(
      'strict_interval_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(60));
  static const VerificationMeta _gentleReminderTimesMeta =
      const VerificationMeta('gentleReminderTimes');
  @override
  late final GeneratedColumn<String> gentleReminderTimes =
      GeneratedColumn<String>('gentle_reminder_times', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('["09:00","13:00","18:00","21:00"]'));
  static const VerificationMeta _sleepModeActiveMeta =
      const VerificationMeta('sleepModeActive');
  @override
  late final GeneratedColumn<bool> sleepModeActive = GeneratedColumn<bool>(
      'sleep_mode_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sleep_mode_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sleepModeStartedAtMeta =
      const VerificationMeta('sleepModeStartedAt');
  @override
  late final GeneratedColumn<DateTime> sleepModeStartedAt =
      GeneratedColumn<DateTime>('sleep_mode_started_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastSleepPromptDateMeta =
      const VerificationMeta('lastSleepPromptDate');
  @override
  late final GeneratedColumn<DateTime> lastSleepPromptDate =
      GeneratedColumn<DateTime>('last_sleep_prompt_date', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _aiPersonaMeta =
      const VerificationMeta('aiPersona');
  @override
  late final GeneratedColumn<String> aiPersona = GeneratedColumn<String>(
      'ai_persona', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('friendly'));
  static const VerificationMeta _appOpenCountMeta =
      const VerificationMeta('appOpenCount');
  @override
  late final GeneratedColumn<int> appOpenCount = GeneratedColumn<int>(
      'app_open_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _usageStatsPermissionAskedMeta =
      const VerificationMeta('usageStatsPermissionAsked');
  @override
  late final GeneratedColumn<bool> usageStatsPermissionAsked =
      GeneratedColumn<bool>('usage_stats_permission_asked', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("usage_stats_permission_asked" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _lastIntentionPromptDateMeta =
      const VerificationMeta('lastIntentionPromptDate');
  @override
  late final GeneratedColumn<DateTime> lastIntentionPromptDate =
      GeneratedColumn<DateTime>('last_intention_prompt_date', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _supabaseUserIdMeta =
      const VerificationMeta('supabaseUserId');
  @override
  late final GeneratedColumn<String> supabaseUserId = GeneratedColumn<String>(
      'supabase_user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<String> lastSyncedAt = GeneratedColumn<String>(
      'last_synced_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        reminderMode,
        strictIntervalMinutes,
        gentleReminderTimes,
        sleepModeActive,
        sleepModeStartedAt,
        lastSleepPromptDate,
        aiPersona,
        appOpenCount,
        usageStatsPermissionAsked,
        lastIntentionPromptDate,
        supabaseUserId,
        lastSyncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_settings';
  @override
  VerificationContext validateIntegrity(Insertable<UserSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('reminder_mode')) {
      context.handle(
          _reminderModeMeta,
          reminderMode.isAcceptableOrUnknown(
              data['reminder_mode']!, _reminderModeMeta));
    }
    if (data.containsKey('strict_interval_minutes')) {
      context.handle(
          _strictIntervalMinutesMeta,
          strictIntervalMinutes.isAcceptableOrUnknown(
              data['strict_interval_minutes']!, _strictIntervalMinutesMeta));
    }
    if (data.containsKey('gentle_reminder_times')) {
      context.handle(
          _gentleReminderTimesMeta,
          gentleReminderTimes.isAcceptableOrUnknown(
              data['gentle_reminder_times']!, _gentleReminderTimesMeta));
    }
    if (data.containsKey('sleep_mode_active')) {
      context.handle(
          _sleepModeActiveMeta,
          sleepModeActive.isAcceptableOrUnknown(
              data['sleep_mode_active']!, _sleepModeActiveMeta));
    }
    if (data.containsKey('sleep_mode_started_at')) {
      context.handle(
          _sleepModeStartedAtMeta,
          sleepModeStartedAt.isAcceptableOrUnknown(
              data['sleep_mode_started_at']!, _sleepModeStartedAtMeta));
    }
    if (data.containsKey('last_sleep_prompt_date')) {
      context.handle(
          _lastSleepPromptDateMeta,
          lastSleepPromptDate.isAcceptableOrUnknown(
              data['last_sleep_prompt_date']!, _lastSleepPromptDateMeta));
    }
    if (data.containsKey('ai_persona')) {
      context.handle(_aiPersonaMeta,
          aiPersona.isAcceptableOrUnknown(data['ai_persona']!, _aiPersonaMeta));
    }
    if (data.containsKey('app_open_count')) {
      context.handle(
          _appOpenCountMeta,
          appOpenCount.isAcceptableOrUnknown(
              data['app_open_count']!, _appOpenCountMeta));
    }
    if (data.containsKey('usage_stats_permission_asked')) {
      context.handle(
          _usageStatsPermissionAskedMeta,
          usageStatsPermissionAsked.isAcceptableOrUnknown(
              data['usage_stats_permission_asked']!,
              _usageStatsPermissionAskedMeta));
    }
    if (data.containsKey('last_intention_prompt_date')) {
      context.handle(
          _lastIntentionPromptDateMeta,
          lastIntentionPromptDate.isAcceptableOrUnknown(
              data['last_intention_prompt_date']!,
              _lastIntentionPromptDateMeta));
    }
    if (data.containsKey('supabase_user_id')) {
      context.handle(
          _supabaseUserIdMeta,
          supabaseUserId.isAcceptableOrUnknown(
              data['supabase_user_id']!, _supabaseUserIdMeta));
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      reminderMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reminder_mode'])!,
      strictIntervalMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}strict_interval_minutes'])!,
      gentleReminderTimes: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}gentle_reminder_times'])!,
      sleepModeActive: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}sleep_mode_active'])!,
      sleepModeStartedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}sleep_mode_started_at']),
      lastSleepPromptDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_sleep_prompt_date']),
      aiPersona: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ai_persona'])!,
      appOpenCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}app_open_count'])!,
      usageStatsPermissionAsked: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}usage_stats_permission_asked'])!,
      lastIntentionPromptDate: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_intention_prompt_date']),
      supabaseUserId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}supabase_user_id']),
      lastSyncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_synced_at']),
    );
  }

  @override
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
  }
}

class UserSetting extends DataClass implements Insertable<UserSetting> {
  final int id;
  final String reminderMode;
  final int strictIntervalMinutes;
  final String gentleReminderTimes;
  final bool sleepModeActive;
  final DateTime? sleepModeStartedAt;
  final DateTime? lastSleepPromptDate;
  final String aiPersona;
  final int appOpenCount;
  final bool usageStatsPermissionAsked;
  final DateTime? lastIntentionPromptDate;
  final String? supabaseUserId;
  final String? lastSyncedAt;
  const UserSetting(
      {required this.id,
      required this.reminderMode,
      required this.strictIntervalMinutes,
      required this.gentleReminderTimes,
      required this.sleepModeActive,
      this.sleepModeStartedAt,
      this.lastSleepPromptDate,
      required this.aiPersona,
      required this.appOpenCount,
      required this.usageStatsPermissionAsked,
      this.lastIntentionPromptDate,
      this.supabaseUserId,
      this.lastSyncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['reminder_mode'] = Variable<String>(reminderMode);
    map['strict_interval_minutes'] = Variable<int>(strictIntervalMinutes);
    map['gentle_reminder_times'] = Variable<String>(gentleReminderTimes);
    map['sleep_mode_active'] = Variable<bool>(sleepModeActive);
    if (!nullToAbsent || sleepModeStartedAt != null) {
      map['sleep_mode_started_at'] = Variable<DateTime>(sleepModeStartedAt);
    }
    if (!nullToAbsent || lastSleepPromptDate != null) {
      map['last_sleep_prompt_date'] = Variable<DateTime>(lastSleepPromptDate);
    }
    map['ai_persona'] = Variable<String>(aiPersona);
    map['app_open_count'] = Variable<int>(appOpenCount);
    map['usage_stats_permission_asked'] =
        Variable<bool>(usageStatsPermissionAsked);
    if (!nullToAbsent || lastIntentionPromptDate != null) {
      map['last_intention_prompt_date'] =
          Variable<DateTime>(lastIntentionPromptDate);
    }
    if (!nullToAbsent || supabaseUserId != null) {
      map['supabase_user_id'] = Variable<String>(supabaseUserId);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<String>(lastSyncedAt);
    }
    return map;
  }

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(
      id: Value(id),
      reminderMode: Value(reminderMode),
      strictIntervalMinutes: Value(strictIntervalMinutes),
      gentleReminderTimes: Value(gentleReminderTimes),
      sleepModeActive: Value(sleepModeActive),
      sleepModeStartedAt: sleepModeStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sleepModeStartedAt),
      lastSleepPromptDate: lastSleepPromptDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSleepPromptDate),
      aiPersona: Value(aiPersona),
      appOpenCount: Value(appOpenCount),
      usageStatsPermissionAsked: Value(usageStatsPermissionAsked),
      lastIntentionPromptDate: lastIntentionPromptDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastIntentionPromptDate),
      supabaseUserId: supabaseUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(supabaseUserId),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
    );
  }

  factory UserSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserSetting(
      id: serializer.fromJson<int>(json['id']),
      reminderMode: serializer.fromJson<String>(json['reminderMode']),
      strictIntervalMinutes:
          serializer.fromJson<int>(json['strictIntervalMinutes']),
      gentleReminderTimes:
          serializer.fromJson<String>(json['gentleReminderTimes']),
      sleepModeActive: serializer.fromJson<bool>(json['sleepModeActive']),
      sleepModeStartedAt:
          serializer.fromJson<DateTime?>(json['sleepModeStartedAt']),
      lastSleepPromptDate:
          serializer.fromJson<DateTime?>(json['lastSleepPromptDate']),
      aiPersona: serializer.fromJson<String>(json['aiPersona']),
      appOpenCount: serializer.fromJson<int>(json['appOpenCount']),
      usageStatsPermissionAsked:
          serializer.fromJson<bool>(json['usageStatsPermissionAsked']),
      lastIntentionPromptDate:
          serializer.fromJson<DateTime?>(json['lastIntentionPromptDate']),
      supabaseUserId: serializer.fromJson<String?>(json['supabaseUserId']),
      lastSyncedAt: serializer.fromJson<String?>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'reminderMode': serializer.toJson<String>(reminderMode),
      'strictIntervalMinutes': serializer.toJson<int>(strictIntervalMinutes),
      'gentleReminderTimes': serializer.toJson<String>(gentleReminderTimes),
      'sleepModeActive': serializer.toJson<bool>(sleepModeActive),
      'sleepModeStartedAt': serializer.toJson<DateTime?>(sleepModeStartedAt),
      'lastSleepPromptDate': serializer.toJson<DateTime?>(lastSleepPromptDate),
      'aiPersona': serializer.toJson<String>(aiPersona),
      'appOpenCount': serializer.toJson<int>(appOpenCount),
      'usageStatsPermissionAsked':
          serializer.toJson<bool>(usageStatsPermissionAsked),
      'lastIntentionPromptDate':
          serializer.toJson<DateTime?>(lastIntentionPromptDate),
      'supabaseUserId': serializer.toJson<String?>(supabaseUserId),
      'lastSyncedAt': serializer.toJson<String?>(lastSyncedAt),
    };
  }

  UserSetting copyWith(
          {int? id,
          String? reminderMode,
          int? strictIntervalMinutes,
          String? gentleReminderTimes,
          bool? sleepModeActive,
          Value<DateTime?> sleepModeStartedAt = const Value.absent(),
          Value<DateTime?> lastSleepPromptDate = const Value.absent(),
          String? aiPersona,
          int? appOpenCount,
          bool? usageStatsPermissionAsked,
          Value<DateTime?> lastIntentionPromptDate = const Value.absent(),
          Value<String?> supabaseUserId = const Value.absent(),
          Value<String?> lastSyncedAt = const Value.absent()}) =>
      UserSetting(
        id: id ?? this.id,
        reminderMode: reminderMode ?? this.reminderMode,
        strictIntervalMinutes:
            strictIntervalMinutes ?? this.strictIntervalMinutes,
        gentleReminderTimes: gentleReminderTimes ?? this.gentleReminderTimes,
        sleepModeActive: sleepModeActive ?? this.sleepModeActive,
        sleepModeStartedAt: sleepModeStartedAt.present
            ? sleepModeStartedAt.value
            : this.sleepModeStartedAt,
        lastSleepPromptDate: lastSleepPromptDate.present
            ? lastSleepPromptDate.value
            : this.lastSleepPromptDate,
        aiPersona: aiPersona ?? this.aiPersona,
        appOpenCount: appOpenCount ?? this.appOpenCount,
        usageStatsPermissionAsked:
            usageStatsPermissionAsked ?? this.usageStatsPermissionAsked,
        lastIntentionPromptDate: lastIntentionPromptDate.present
            ? lastIntentionPromptDate.value
            : this.lastIntentionPromptDate,
        supabaseUserId:
            supabaseUserId.present ? supabaseUserId.value : this.supabaseUserId,
        lastSyncedAt:
            lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
      );
  UserSetting copyWithCompanion(UserSettingsCompanion data) {
    return UserSetting(
      id: data.id.present ? data.id.value : this.id,
      reminderMode: data.reminderMode.present
          ? data.reminderMode.value
          : this.reminderMode,
      strictIntervalMinutes: data.strictIntervalMinutes.present
          ? data.strictIntervalMinutes.value
          : this.strictIntervalMinutes,
      gentleReminderTimes: data.gentleReminderTimes.present
          ? data.gentleReminderTimes.value
          : this.gentleReminderTimes,
      sleepModeActive: data.sleepModeActive.present
          ? data.sleepModeActive.value
          : this.sleepModeActive,
      sleepModeStartedAt: data.sleepModeStartedAt.present
          ? data.sleepModeStartedAt.value
          : this.sleepModeStartedAt,
      lastSleepPromptDate: data.lastSleepPromptDate.present
          ? data.lastSleepPromptDate.value
          : this.lastSleepPromptDate,
      aiPersona: data.aiPersona.present ? data.aiPersona.value : this.aiPersona,
      appOpenCount: data.appOpenCount.present
          ? data.appOpenCount.value
          : this.appOpenCount,
      usageStatsPermissionAsked: data.usageStatsPermissionAsked.present
          ? data.usageStatsPermissionAsked.value
          : this.usageStatsPermissionAsked,
      lastIntentionPromptDate: data.lastIntentionPromptDate.present
          ? data.lastIntentionPromptDate.value
          : this.lastIntentionPromptDate,
      supabaseUserId: data.supabaseUserId.present
          ? data.supabaseUserId.value
          : this.supabaseUserId,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserSetting(')
          ..write('id: $id, ')
          ..write('reminderMode: $reminderMode, ')
          ..write('strictIntervalMinutes: $strictIntervalMinutes, ')
          ..write('gentleReminderTimes: $gentleReminderTimes, ')
          ..write('sleepModeActive: $sleepModeActive, ')
          ..write('sleepModeStartedAt: $sleepModeStartedAt, ')
          ..write('lastSleepPromptDate: $lastSleepPromptDate, ')
          ..write('aiPersona: $aiPersona, ')
          ..write('appOpenCount: $appOpenCount, ')
          ..write('usageStatsPermissionAsked: $usageStatsPermissionAsked, ')
          ..write('lastIntentionPromptDate: $lastIntentionPromptDate, ')
          ..write('supabaseUserId: $supabaseUserId, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      reminderMode,
      strictIntervalMinutes,
      gentleReminderTimes,
      sleepModeActive,
      sleepModeStartedAt,
      lastSleepPromptDate,
      aiPersona,
      appOpenCount,
      usageStatsPermissionAsked,
      lastIntentionPromptDate,
      supabaseUserId,
      lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserSetting &&
          other.id == this.id &&
          other.reminderMode == this.reminderMode &&
          other.strictIntervalMinutes == this.strictIntervalMinutes &&
          other.gentleReminderTimes == this.gentleReminderTimes &&
          other.sleepModeActive == this.sleepModeActive &&
          other.sleepModeStartedAt == this.sleepModeStartedAt &&
          other.lastSleepPromptDate == this.lastSleepPromptDate &&
          other.aiPersona == this.aiPersona &&
          other.appOpenCount == this.appOpenCount &&
          other.usageStatsPermissionAsked == this.usageStatsPermissionAsked &&
          other.lastIntentionPromptDate == this.lastIntentionPromptDate &&
          other.supabaseUserId == this.supabaseUserId &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class UserSettingsCompanion extends UpdateCompanion<UserSetting> {
  final Value<int> id;
  final Value<String> reminderMode;
  final Value<int> strictIntervalMinutes;
  final Value<String> gentleReminderTimes;
  final Value<bool> sleepModeActive;
  final Value<DateTime?> sleepModeStartedAt;
  final Value<DateTime?> lastSleepPromptDate;
  final Value<String> aiPersona;
  final Value<int> appOpenCount;
  final Value<bool> usageStatsPermissionAsked;
  final Value<DateTime?> lastIntentionPromptDate;
  final Value<String?> supabaseUserId;
  final Value<String?> lastSyncedAt;
  const UserSettingsCompanion({
    this.id = const Value.absent(),
    this.reminderMode = const Value.absent(),
    this.strictIntervalMinutes = const Value.absent(),
    this.gentleReminderTimes = const Value.absent(),
    this.sleepModeActive = const Value.absent(),
    this.sleepModeStartedAt = const Value.absent(),
    this.lastSleepPromptDate = const Value.absent(),
    this.aiPersona = const Value.absent(),
    this.appOpenCount = const Value.absent(),
    this.usageStatsPermissionAsked = const Value.absent(),
    this.lastIntentionPromptDate = const Value.absent(),
    this.supabaseUserId = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
  });
  UserSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.reminderMode = const Value.absent(),
    this.strictIntervalMinutes = const Value.absent(),
    this.gentleReminderTimes = const Value.absent(),
    this.sleepModeActive = const Value.absent(),
    this.sleepModeStartedAt = const Value.absent(),
    this.lastSleepPromptDate = const Value.absent(),
    this.aiPersona = const Value.absent(),
    this.appOpenCount = const Value.absent(),
    this.usageStatsPermissionAsked = const Value.absent(),
    this.lastIntentionPromptDate = const Value.absent(),
    this.supabaseUserId = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
  });
  static Insertable<UserSetting> custom({
    Expression<int>? id,
    Expression<String>? reminderMode,
    Expression<int>? strictIntervalMinutes,
    Expression<String>? gentleReminderTimes,
    Expression<bool>? sleepModeActive,
    Expression<DateTime>? sleepModeStartedAt,
    Expression<DateTime>? lastSleepPromptDate,
    Expression<String>? aiPersona,
    Expression<int>? appOpenCount,
    Expression<bool>? usageStatsPermissionAsked,
    Expression<DateTime>? lastIntentionPromptDate,
    Expression<String>? supabaseUserId,
    Expression<String>? lastSyncedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (reminderMode != null) 'reminder_mode': reminderMode,
      if (strictIntervalMinutes != null)
        'strict_interval_minutes': strictIntervalMinutes,
      if (gentleReminderTimes != null)
        'gentle_reminder_times': gentleReminderTimes,
      if (sleepModeActive != null) 'sleep_mode_active': sleepModeActive,
      if (sleepModeStartedAt != null)
        'sleep_mode_started_at': sleepModeStartedAt,
      if (lastSleepPromptDate != null)
        'last_sleep_prompt_date': lastSleepPromptDate,
      if (aiPersona != null) 'ai_persona': aiPersona,
      if (appOpenCount != null) 'app_open_count': appOpenCount,
      if (usageStatsPermissionAsked != null)
        'usage_stats_permission_asked': usageStatsPermissionAsked,
      if (lastIntentionPromptDate != null)
        'last_intention_prompt_date': lastIntentionPromptDate,
      if (supabaseUserId != null) 'supabase_user_id': supabaseUserId,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
    });
  }

  UserSettingsCompanion copyWith(
      {Value<int>? id,
      Value<String>? reminderMode,
      Value<int>? strictIntervalMinutes,
      Value<String>? gentleReminderTimes,
      Value<bool>? sleepModeActive,
      Value<DateTime?>? sleepModeStartedAt,
      Value<DateTime?>? lastSleepPromptDate,
      Value<String>? aiPersona,
      Value<int>? appOpenCount,
      Value<bool>? usageStatsPermissionAsked,
      Value<DateTime?>? lastIntentionPromptDate,
      Value<String?>? supabaseUserId,
      Value<String?>? lastSyncedAt}) {
    return UserSettingsCompanion(
      id: id ?? this.id,
      reminderMode: reminderMode ?? this.reminderMode,
      strictIntervalMinutes:
          strictIntervalMinutes ?? this.strictIntervalMinutes,
      gentleReminderTimes: gentleReminderTimes ?? this.gentleReminderTimes,
      sleepModeActive: sleepModeActive ?? this.sleepModeActive,
      sleepModeStartedAt: sleepModeStartedAt ?? this.sleepModeStartedAt,
      lastSleepPromptDate: lastSleepPromptDate ?? this.lastSleepPromptDate,
      aiPersona: aiPersona ?? this.aiPersona,
      appOpenCount: appOpenCount ?? this.appOpenCount,
      usageStatsPermissionAsked:
          usageStatsPermissionAsked ?? this.usageStatsPermissionAsked,
      lastIntentionPromptDate:
          lastIntentionPromptDate ?? this.lastIntentionPromptDate,
      supabaseUserId: supabaseUserId ?? this.supabaseUserId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (reminderMode.present) {
      map['reminder_mode'] = Variable<String>(reminderMode.value);
    }
    if (strictIntervalMinutes.present) {
      map['strict_interval_minutes'] =
          Variable<int>(strictIntervalMinutes.value);
    }
    if (gentleReminderTimes.present) {
      map['gentle_reminder_times'] =
          Variable<String>(gentleReminderTimes.value);
    }
    if (sleepModeActive.present) {
      map['sleep_mode_active'] = Variable<bool>(sleepModeActive.value);
    }
    if (sleepModeStartedAt.present) {
      map['sleep_mode_started_at'] =
          Variable<DateTime>(sleepModeStartedAt.value);
    }
    if (lastSleepPromptDate.present) {
      map['last_sleep_prompt_date'] =
          Variable<DateTime>(lastSleepPromptDate.value);
    }
    if (aiPersona.present) {
      map['ai_persona'] = Variable<String>(aiPersona.value);
    }
    if (appOpenCount.present) {
      map['app_open_count'] = Variable<int>(appOpenCount.value);
    }
    if (usageStatsPermissionAsked.present) {
      map['usage_stats_permission_asked'] =
          Variable<bool>(usageStatsPermissionAsked.value);
    }
    if (lastIntentionPromptDate.present) {
      map['last_intention_prompt_date'] =
          Variable<DateTime>(lastIntentionPromptDate.value);
    }
    if (supabaseUserId.present) {
      map['supabase_user_id'] = Variable<String>(supabaseUserId.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<String>(lastSyncedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsCompanion(')
          ..write('id: $id, ')
          ..write('reminderMode: $reminderMode, ')
          ..write('strictIntervalMinutes: $strictIntervalMinutes, ')
          ..write('gentleReminderTimes: $gentleReminderTimes, ')
          ..write('sleepModeActive: $sleepModeActive, ')
          ..write('sleepModeStartedAt: $sleepModeStartedAt, ')
          ..write('lastSleepPromptDate: $lastSleepPromptDate, ')
          ..write('aiPersona: $aiPersona, ')
          ..write('appOpenCount: $appOpenCount, ')
          ..write('usageStatsPermissionAsked: $usageStatsPermissionAsked, ')
          ..write('lastIntentionPromptDate: $lastIntentionPromptDate, ')
          ..write('supabaseUserId: $supabaseUserId, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $LogEntriesTable logEntries = $LogEntriesTable(this);
  late final $RoutineSlotsTable routineSlots = $RoutineSlotsTable(this);
  late final $DailyIntentionsTable dailyIntentions =
      $DailyIntentionsTable(this);
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  late final CategoriesDao categoriesDao = CategoriesDao(this as AppDatabase);
  late final LogEntriesDao logEntriesDao = LogEntriesDao(this as AppDatabase);
  late final RoutineSlotsDao routineSlotsDao =
      RoutineSlotsDao(this as AppDatabase);
  late final IntentionsDao intentionsDao = IntentionsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [categories, logEntries, routineSlots, dailyIntentions, userSettings];
}

typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  required String name,
  required int colorValue,
  Value<bool> isArchived,
  Value<bool> isSystem,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> colorValue,
  Value<bool> isArchived,
  Value<bool> isSystem,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get colorValue => $composableBuilder(
      column: $table.colorValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSystem => $composableBuilder(
      column: $table.isSystem, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get colorValue => $composableBuilder(
      column: $table.colorValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSystem => $composableBuilder(
      column: $table.isSystem, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
      column: $table.colorValue, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => column);

  GeneratedColumn<bool> get isSystem =>
      $composableBuilder(column: $table.isSystem, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);
}

class $$CategoriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()> {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> colorValue = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<bool> isSystem = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              CategoriesCompanion(
            id: id,
            name: name,
            colorValue: colorValue,
            isArchived: isArchived,
            isSystem: isSystem,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            required int colorValue,
            Value<bool> isArchived = const Value.absent(),
            Value<bool> isSystem = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              CategoriesCompanion.insert(
            id: id,
            name: name,
            colorValue: colorValue,
            isArchived: isArchived,
            isSystem: isSystem,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()>;
typedef $$LogEntriesTableCreateCompanionBuilder = LogEntriesCompanion Function({
  Value<int> id,
  Value<String> description,
  Value<int?> categoryId,
  required DateTime startTime,
  required DateTime endTime,
  Value<bool> isRealTime,
  Value<bool> isAiParsed,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});
typedef $$LogEntriesTableUpdateCompanionBuilder = LogEntriesCompanion Function({
  Value<int> id,
  Value<String> description,
  Value<int?> categoryId,
  Value<DateTime> startTime,
  Value<DateTime> endTime,
  Value<bool> isRealTime,
  Value<bool> isAiParsed,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});

class $$LogEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LogEntriesTable> {
  $$LogEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRealTime => $composableBuilder(
      column: $table.isRealTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAiParsed => $composableBuilder(
      column: $table.isAiParsed, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));
}

class $$LogEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LogEntriesTable> {
  $$LogEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRealTime => $composableBuilder(
      column: $table.isRealTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAiParsed => $composableBuilder(
      column: $table.isAiParsed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));
}

class $$LogEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LogEntriesTable> {
  $$LogEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<bool> get isRealTime => $composableBuilder(
      column: $table.isRealTime, builder: (column) => column);

  GeneratedColumn<bool> get isAiParsed => $composableBuilder(
      column: $table.isAiParsed, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);
}

class $$LogEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LogEntriesTable,
    LogEntry,
    $$LogEntriesTableFilterComposer,
    $$LogEntriesTableOrderingComposer,
    $$LogEntriesTableAnnotationComposer,
    $$LogEntriesTableCreateCompanionBuilder,
    $$LogEntriesTableUpdateCompanionBuilder,
    (LogEntry, BaseReferences<_$AppDatabase, $LogEntriesTable, LogEntry>),
    LogEntry,
    PrefetchHooks Function()> {
  $$LogEntriesTableTableManager(_$AppDatabase db, $LogEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LogEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LogEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LogEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<DateTime> startTime = const Value.absent(),
            Value<DateTime> endTime = const Value.absent(),
            Value<bool> isRealTime = const Value.absent(),
            Value<bool> isAiParsed = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              LogEntriesCompanion(
            id: id,
            description: description,
            categoryId: categoryId,
            startTime: startTime,
            endTime: endTime,
            isRealTime: isRealTime,
            isAiParsed: isAiParsed,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            required DateTime startTime,
            required DateTime endTime,
            Value<bool> isRealTime = const Value.absent(),
            Value<bool> isAiParsed = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              LogEntriesCompanion.insert(
            id: id,
            description: description,
            categoryId: categoryId,
            startTime: startTime,
            endTime: endTime,
            isRealTime: isRealTime,
            isAiParsed: isAiParsed,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LogEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LogEntriesTable,
    LogEntry,
    $$LogEntriesTableFilterComposer,
    $$LogEntriesTableOrderingComposer,
    $$LogEntriesTableAnnotationComposer,
    $$LogEntriesTableCreateCompanionBuilder,
    $$LogEntriesTableUpdateCompanionBuilder,
    (LogEntry, BaseReferences<_$AppDatabase, $LogEntriesTable, LogEntry>),
    LogEntry,
    PrefetchHooks Function()>;
typedef $$RoutineSlotsTableCreateCompanionBuilder = RoutineSlotsCompanion
    Function({
  Value<int> id,
  Value<int?> categoryId,
  Value<String> label,
  required int dayOfWeek,
  required int startHour,
  Value<int> durationHours,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});
typedef $$RoutineSlotsTableUpdateCompanionBuilder = RoutineSlotsCompanion
    Function({
  Value<int> id,
  Value<int?> categoryId,
  Value<String> label,
  Value<int> dayOfWeek,
  Value<int> startHour,
  Value<int> durationHours,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});

class $$RoutineSlotsTableFilterComposer
    extends Composer<_$AppDatabase, $RoutineSlotsTable> {
  $$RoutineSlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dayOfWeek => $composableBuilder(
      column: $table.dayOfWeek, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startHour => $composableBuilder(
      column: $table.startHour, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationHours => $composableBuilder(
      column: $table.durationHours, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));
}

class $$RoutineSlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoutineSlotsTable> {
  $$RoutineSlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get label => $composableBuilder(
      column: $table.label, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dayOfWeek => $composableBuilder(
      column: $table.dayOfWeek, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startHour => $composableBuilder(
      column: $table.startHour, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationHours => $composableBuilder(
      column: $table.durationHours,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));
}

class $$RoutineSlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoutineSlotsTable> {
  $$RoutineSlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get dayOfWeek =>
      $composableBuilder(column: $table.dayOfWeek, builder: (column) => column);

  GeneratedColumn<int> get startHour =>
      $composableBuilder(column: $table.startHour, builder: (column) => column);

  GeneratedColumn<int> get durationHours => $composableBuilder(
      column: $table.durationHours, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);
}

class $$RoutineSlotsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RoutineSlotsTable,
    RoutineSlot,
    $$RoutineSlotsTableFilterComposer,
    $$RoutineSlotsTableOrderingComposer,
    $$RoutineSlotsTableAnnotationComposer,
    $$RoutineSlotsTableCreateCompanionBuilder,
    $$RoutineSlotsTableUpdateCompanionBuilder,
    (
      RoutineSlot,
      BaseReferences<_$AppDatabase, $RoutineSlotsTable, RoutineSlot>
    ),
    RoutineSlot,
    PrefetchHooks Function()> {
  $$RoutineSlotsTableTableManager(_$AppDatabase db, $RoutineSlotsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutineSlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutineSlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutineSlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<int> dayOfWeek = const Value.absent(),
            Value<int> startHour = const Value.absent(),
            Value<int> durationHours = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              RoutineSlotsCompanion(
            id: id,
            categoryId: categoryId,
            label: label,
            dayOfWeek: dayOfWeek,
            startHour: startHour,
            durationHours: durationHours,
            isActive: isActive,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> categoryId = const Value.absent(),
            Value<String> label = const Value.absent(),
            required int dayOfWeek,
            required int startHour,
            Value<int> durationHours = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              RoutineSlotsCompanion.insert(
            id: id,
            categoryId: categoryId,
            label: label,
            dayOfWeek: dayOfWeek,
            startHour: startHour,
            durationHours: durationHours,
            isActive: isActive,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RoutineSlotsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RoutineSlotsTable,
    RoutineSlot,
    $$RoutineSlotsTableFilterComposer,
    $$RoutineSlotsTableOrderingComposer,
    $$RoutineSlotsTableAnnotationComposer,
    $$RoutineSlotsTableCreateCompanionBuilder,
    $$RoutineSlotsTableUpdateCompanionBuilder,
    (
      RoutineSlot,
      BaseReferences<_$AppDatabase, $RoutineSlotsTable, RoutineSlot>
    ),
    RoutineSlot,
    PrefetchHooks Function()>;
typedef $$DailyIntentionsTableCreateCompanionBuilder = DailyIntentionsCompanion
    Function({
  Value<int> id,
  required String intention,
  required DateTime date,
  Value<bool> wasReflected,
  Value<bool?> verdictPositive,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});
typedef $$DailyIntentionsTableUpdateCompanionBuilder = DailyIntentionsCompanion
    Function({
  Value<int> id,
  Value<String> intention,
  Value<DateTime> date,
  Value<bool> wasReflected,
  Value<bool?> verdictPositive,
  Value<DateTime> createdAt,
  Value<String?> userId,
  Value<String?> syncId,
});

class $$DailyIntentionsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyIntentionsTable> {
  $$DailyIntentionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get intention => $composableBuilder(
      column: $table.intention, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get wasReflected => $composableBuilder(
      column: $table.wasReflected, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get verdictPositive => $composableBuilder(
      column: $table.verdictPositive,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnFilters(column));
}

class $$DailyIntentionsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyIntentionsTable> {
  $$DailyIntentionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get intention => $composableBuilder(
      column: $table.intention, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get wasReflected => $composableBuilder(
      column: $table.wasReflected,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get verdictPositive => $composableBuilder(
      column: $table.verdictPositive,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncId => $composableBuilder(
      column: $table.syncId, builder: (column) => ColumnOrderings(column));
}

class $$DailyIntentionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyIntentionsTable> {
  $$DailyIntentionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get intention =>
      $composableBuilder(column: $table.intention, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<bool> get wasReflected => $composableBuilder(
      column: $table.wasReflected, builder: (column) => column);

  GeneratedColumn<bool> get verdictPositive => $composableBuilder(
      column: $table.verdictPositive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);
}

class $$DailyIntentionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DailyIntentionsTable,
    DailyIntention,
    $$DailyIntentionsTableFilterComposer,
    $$DailyIntentionsTableOrderingComposer,
    $$DailyIntentionsTableAnnotationComposer,
    $$DailyIntentionsTableCreateCompanionBuilder,
    $$DailyIntentionsTableUpdateCompanionBuilder,
    (
      DailyIntention,
      BaseReferences<_$AppDatabase, $DailyIntentionsTable, DailyIntention>
    ),
    DailyIntention,
    PrefetchHooks Function()> {
  $$DailyIntentionsTableTableManager(
      _$AppDatabase db, $DailyIntentionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyIntentionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyIntentionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyIntentionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> intention = const Value.absent(),
            Value<DateTime> date = const Value.absent(),
            Value<bool> wasReflected = const Value.absent(),
            Value<bool?> verdictPositive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              DailyIntentionsCompanion(
            id: id,
            intention: intention,
            date: date,
            wasReflected: wasReflected,
            verdictPositive: verdictPositive,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String intention,
            required DateTime date,
            Value<bool> wasReflected = const Value.absent(),
            Value<bool?> verdictPositive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> syncId = const Value.absent(),
          }) =>
              DailyIntentionsCompanion.insert(
            id: id,
            intention: intention,
            date: date,
            wasReflected: wasReflected,
            verdictPositive: verdictPositive,
            createdAt: createdAt,
            userId: userId,
            syncId: syncId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DailyIntentionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DailyIntentionsTable,
    DailyIntention,
    $$DailyIntentionsTableFilterComposer,
    $$DailyIntentionsTableOrderingComposer,
    $$DailyIntentionsTableAnnotationComposer,
    $$DailyIntentionsTableCreateCompanionBuilder,
    $$DailyIntentionsTableUpdateCompanionBuilder,
    (
      DailyIntention,
      BaseReferences<_$AppDatabase, $DailyIntentionsTable, DailyIntention>
    ),
    DailyIntention,
    PrefetchHooks Function()>;
typedef $$UserSettingsTableCreateCompanionBuilder = UserSettingsCompanion
    Function({
  Value<int> id,
  Value<String> reminderMode,
  Value<int> strictIntervalMinutes,
  Value<String> gentleReminderTimes,
  Value<bool> sleepModeActive,
  Value<DateTime?> sleepModeStartedAt,
  Value<DateTime?> lastSleepPromptDate,
  Value<String> aiPersona,
  Value<int> appOpenCount,
  Value<bool> usageStatsPermissionAsked,
  Value<DateTime?> lastIntentionPromptDate,
  Value<String?> supabaseUserId,
  Value<String?> lastSyncedAt,
});
typedef $$UserSettingsTableUpdateCompanionBuilder = UserSettingsCompanion
    Function({
  Value<int> id,
  Value<String> reminderMode,
  Value<int> strictIntervalMinutes,
  Value<String> gentleReminderTimes,
  Value<bool> sleepModeActive,
  Value<DateTime?> sleepModeStartedAt,
  Value<DateTime?> lastSleepPromptDate,
  Value<String> aiPersona,
  Value<int> appOpenCount,
  Value<bool> usageStatsPermissionAsked,
  Value<DateTime?> lastIntentionPromptDate,
  Value<String?> supabaseUserId,
  Value<String?> lastSyncedAt,
});

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reminderMode => $composableBuilder(
      column: $table.reminderMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get strictIntervalMinutes => $composableBuilder(
      column: $table.strictIntervalMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get gentleReminderTimes => $composableBuilder(
      column: $table.gentleReminderTimes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get sleepModeActive => $composableBuilder(
      column: $table.sleepModeActive,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get sleepModeStartedAt => $composableBuilder(
      column: $table.sleepModeStartedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSleepPromptDate => $composableBuilder(
      column: $table.lastSleepPromptDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get aiPersona => $composableBuilder(
      column: $table.aiPersona, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get appOpenCount => $composableBuilder(
      column: $table.appOpenCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get usageStatsPermissionAsked => $composableBuilder(
      column: $table.usageStatsPermissionAsked,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastIntentionPromptDate => $composableBuilder(
      column: $table.lastIntentionPromptDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get supabaseUserId => $composableBuilder(
      column: $table.supabaseUserId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));
}

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reminderMode => $composableBuilder(
      column: $table.reminderMode,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get strictIntervalMinutes => $composableBuilder(
      column: $table.strictIntervalMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get gentleReminderTimes => $composableBuilder(
      column: $table.gentleReminderTimes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get sleepModeActive => $composableBuilder(
      column: $table.sleepModeActive,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get sleepModeStartedAt => $composableBuilder(
      column: $table.sleepModeStartedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSleepPromptDate => $composableBuilder(
      column: $table.lastSleepPromptDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get aiPersona => $composableBuilder(
      column: $table.aiPersona, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get appOpenCount => $composableBuilder(
      column: $table.appOpenCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get usageStatsPermissionAsked => $composableBuilder(
      column: $table.usageStatsPermissionAsked,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastIntentionPromptDate => $composableBuilder(
      column: $table.lastIntentionPromptDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get supabaseUserId => $composableBuilder(
      column: $table.supabaseUserId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get reminderMode => $composableBuilder(
      column: $table.reminderMode, builder: (column) => column);

  GeneratedColumn<int> get strictIntervalMinutes => $composableBuilder(
      column: $table.strictIntervalMinutes, builder: (column) => column);

  GeneratedColumn<String> get gentleReminderTimes => $composableBuilder(
      column: $table.gentleReminderTimes, builder: (column) => column);

  GeneratedColumn<bool> get sleepModeActive => $composableBuilder(
      column: $table.sleepModeActive, builder: (column) => column);

  GeneratedColumn<DateTime> get sleepModeStartedAt => $composableBuilder(
      column: $table.sleepModeStartedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSleepPromptDate => $composableBuilder(
      column: $table.lastSleepPromptDate, builder: (column) => column);

  GeneratedColumn<String> get aiPersona =>
      $composableBuilder(column: $table.aiPersona, builder: (column) => column);

  GeneratedColumn<int> get appOpenCount => $composableBuilder(
      column: $table.appOpenCount, builder: (column) => column);

  GeneratedColumn<bool> get usageStatsPermissionAsked => $composableBuilder(
      column: $table.usageStatsPermissionAsked, builder: (column) => column);

  GeneratedColumn<DateTime> get lastIntentionPromptDate => $composableBuilder(
      column: $table.lastIntentionPromptDate, builder: (column) => column);

  GeneratedColumn<String> get supabaseUserId => $composableBuilder(
      column: $table.supabaseUserId, builder: (column) => column);

  GeneratedColumn<String> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);
}

class $$UserSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UserSettingsTable,
    UserSetting,
    $$UserSettingsTableFilterComposer,
    $$UserSettingsTableOrderingComposer,
    $$UserSettingsTableAnnotationComposer,
    $$UserSettingsTableCreateCompanionBuilder,
    $$UserSettingsTableUpdateCompanionBuilder,
    (
      UserSetting,
      BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>
    ),
    UserSetting,
    PrefetchHooks Function()> {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> reminderMode = const Value.absent(),
            Value<int> strictIntervalMinutes = const Value.absent(),
            Value<String> gentleReminderTimes = const Value.absent(),
            Value<bool> sleepModeActive = const Value.absent(),
            Value<DateTime?> sleepModeStartedAt = const Value.absent(),
            Value<DateTime?> lastSleepPromptDate = const Value.absent(),
            Value<String> aiPersona = const Value.absent(),
            Value<int> appOpenCount = const Value.absent(),
            Value<bool> usageStatsPermissionAsked = const Value.absent(),
            Value<DateTime?> lastIntentionPromptDate = const Value.absent(),
            Value<String?> supabaseUserId = const Value.absent(),
            Value<String?> lastSyncedAt = const Value.absent(),
          }) =>
              UserSettingsCompanion(
            id: id,
            reminderMode: reminderMode,
            strictIntervalMinutes: strictIntervalMinutes,
            gentleReminderTimes: gentleReminderTimes,
            sleepModeActive: sleepModeActive,
            sleepModeStartedAt: sleepModeStartedAt,
            lastSleepPromptDate: lastSleepPromptDate,
            aiPersona: aiPersona,
            appOpenCount: appOpenCount,
            usageStatsPermissionAsked: usageStatsPermissionAsked,
            lastIntentionPromptDate: lastIntentionPromptDate,
            supabaseUserId: supabaseUserId,
            lastSyncedAt: lastSyncedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> reminderMode = const Value.absent(),
            Value<int> strictIntervalMinutes = const Value.absent(),
            Value<String> gentleReminderTimes = const Value.absent(),
            Value<bool> sleepModeActive = const Value.absent(),
            Value<DateTime?> sleepModeStartedAt = const Value.absent(),
            Value<DateTime?> lastSleepPromptDate = const Value.absent(),
            Value<String> aiPersona = const Value.absent(),
            Value<int> appOpenCount = const Value.absent(),
            Value<bool> usageStatsPermissionAsked = const Value.absent(),
            Value<DateTime?> lastIntentionPromptDate = const Value.absent(),
            Value<String?> supabaseUserId = const Value.absent(),
            Value<String?> lastSyncedAt = const Value.absent(),
          }) =>
              UserSettingsCompanion.insert(
            id: id,
            reminderMode: reminderMode,
            strictIntervalMinutes: strictIntervalMinutes,
            gentleReminderTimes: gentleReminderTimes,
            sleepModeActive: sleepModeActive,
            sleepModeStartedAt: sleepModeStartedAt,
            lastSleepPromptDate: lastSleepPromptDate,
            aiPersona: aiPersona,
            appOpenCount: appOpenCount,
            usageStatsPermissionAsked: usageStatsPermissionAsked,
            lastIntentionPromptDate: lastIntentionPromptDate,
            supabaseUserId: supabaseUserId,
            lastSyncedAt: lastSyncedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserSettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UserSettingsTable,
    UserSetting,
    $$UserSettingsTableFilterComposer,
    $$UserSettingsTableOrderingComposer,
    $$UserSettingsTableAnnotationComposer,
    $$UserSettingsTableCreateCompanionBuilder,
    $$UserSettingsTableUpdateCompanionBuilder,
    (
      UserSetting,
      BaseReferences<_$AppDatabase, $UserSettingsTable, UserSetting>
    ),
    UserSetting,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$LogEntriesTableTableManager get logEntries =>
      $$LogEntriesTableTableManager(_db, _db.logEntries);
  $$RoutineSlotsTableTableManager get routineSlots =>
      $$RoutineSlotsTableTableManager(_db, _db.routineSlots);
  $$DailyIntentionsTableTableManager get dailyIntentions =>
      $$DailyIntentionsTableTableManager(_db, _db.dailyIntentions);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
}
