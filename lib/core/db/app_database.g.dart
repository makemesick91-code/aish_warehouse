// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BranchesTable extends Branches with TableInfo<$BranchesTable, Branch> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BranchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($BranchesTable.$convertersyncStatus);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    code,
    name,
    address,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'branches';
  @override
  VerificationContext validateIntegrity(
    Insertable<Branch> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Branch map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Branch(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $BranchesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $BranchesTable createAlias(String alias) {
    return $BranchesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class Branch extends DataClass implements Insertable<Branch> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String code;
  final String name;
  final String? address;
  final bool isActive;
  const Branch({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.code,
    required this.name,
    this.address,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $BranchesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  BranchesCompanion toCompanion(bool nullToAbsent) {
    return BranchesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      code: Value(code),
      name: Value(name),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      isActive: Value(isActive),
    );
  }

  factory Branch.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Branch(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      address: serializer.fromJson<String?>(json['address']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'address': serializer.toJson<String?>(address),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Branch copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? code,
    String? name,
    Value<String?> address = const Value.absent(),
    bool? isActive,
  }) => Branch(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    code: code ?? this.code,
    name: name ?? this.name,
    address: address.present ? address.value : this.address,
    isActive: isActive ?? this.isActive,
  );
  Branch copyWithCompanion(BranchesCompanion data) {
    return Branch(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Branch(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    code,
    name,
    address,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Branch &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.code == this.code &&
          other.name == this.name &&
          other.address == this.address &&
          other.isActive == this.isActive);
}

class BranchesCompanion extends UpdateCompanion<Branch> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> code;
  final Value<String> name;
  final Value<String?> address;
  final Value<bool> isActive;
  final Value<int> rowid;
  const BranchesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BranchesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String code,
    required String name,
    this.address = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code),
       name = Value(name);
  static Insertable<Branch> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? address,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BranchesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? code,
    Value<String>? name,
    Value<String?>? address,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return BranchesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      code: code ?? this.code,
      name: name ?? this.name,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $BranchesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BranchesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomsTable extends Rooms with TableInfo<$RoomsTable, Room> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($RoomsTable.$convertersyncStatus);
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    branchId,
    code,
    name,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rooms';
  @override
  VerificationContext validateIntegrity(
    Insertable<Room> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {branchId, code},
  ];
  @override
  Room map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Room(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $RoomsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $RoomsTable createAlias(String alias) {
    return $RoomsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class Room extends DataClass implements Insertable<Room> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String branchId;
  final String code;
  final String name;
  final bool isActive;
  const Room({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.branchId,
    required this.code,
    required this.name,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $RoomsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['branch_id'] = Variable<String>(branchId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  RoomsCompanion toCompanion(bool nullToAbsent) {
    return RoomsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      branchId: Value(branchId),
      code: Value(code),
      name: Value(name),
      isActive: Value(isActive),
    );
  }

  factory Room.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Room(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      branchId: serializer.fromJson<String>(json['branchId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'branchId': serializer.toJson<String>(branchId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Room copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? branchId,
    String? code,
    String? name,
    bool? isActive,
  }) => Room(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    branchId: branchId ?? this.branchId,
    code: code ?? this.code,
    name: name ?? this.name,
    isActive: isActive ?? this.isActive,
  );
  Room copyWithCompanion(RoomsCompanion data) {
    return Room(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Room(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('branchId: $branchId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    branchId,
    code,
    name,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Room &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.branchId == this.branchId &&
          other.code == this.code &&
          other.name == this.name &&
          other.isActive == this.isActive);
}

class RoomsCompanion extends UpdateCompanion<Room> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> branchId;
  final Value<String> code;
  final Value<String> name;
  final Value<bool> isActive;
  final Value<int> rowid;
  const RoomsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.branchId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String branchId,
    required String code,
    required String name,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : branchId = Value(branchId),
       code = Value(code),
       name = Value(name);
  static Insertable<Room> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? branchId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (branchId != null) 'branch_id': branchId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? branchId,
    Value<String>? code,
    Value<String>? name,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return RoomsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      branchId: branchId ?? this.branchId,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $RoomsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('branchId: $branchId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, AppUser> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($UsersTable.$convertersyncStatus);
  static const VerificationMeta _fullNameMeta = const VerificationMeta(
    'fullName',
  );
  @override
  late final GeneratedColumn<String> fullName = GeneratedColumn<String>(
    'full_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 190,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<UserRole, String> role =
      GeneratedColumn<String>(
        'role',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<UserRole>($UsersTable.$converterrole);
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    fullName,
    email,
    role,
    branchId,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppUser> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('full_name')) {
      context.handle(
        _fullNameMeta,
        fullName.isAcceptableOrUnknown(data['full_name']!, _fullNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fullNameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppUser map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppUser(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $UsersTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      fullName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}full_name'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      role: $UsersTable.$converterrole.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}role'],
        )!,
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<UserRole, String> $converterrole =
      const UserRoleConverter();
}

class AppUser extends DataClass implements Insertable<AppUser> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String fullName;
  final String email;
  final UserRole role;

  /// Mandatory for `perawat` and `kepala_cabang`, NULL for warehouse and super
  /// admin. The cross-column rule is enforced in the master data repository
  /// because it depends on the role enum mapping.
  final String? branchId;
  final bool isActive;
  const AppUser({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.fullName,
    required this.email,
    required this.role,
    this.branchId,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $UsersTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['full_name'] = Variable<String>(fullName);
    map['email'] = Variable<String>(email);
    {
      map['role'] = Variable<String>($UsersTable.$converterrole.toSql(role));
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      fullName: Value(fullName),
      email: Value(email),
      role: Value(role),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      isActive: Value(isActive),
    );
  }

  factory AppUser.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppUser(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      fullName: serializer.fromJson<String>(json['fullName']),
      email: serializer.fromJson<String>(json['email']),
      role: serializer.fromJson<UserRole>(json['role']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'fullName': serializer.toJson<String>(fullName),
      'email': serializer.toJson<String>(email),
      'role': serializer.toJson<UserRole>(role),
      'branchId': serializer.toJson<String?>(branchId),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  AppUser copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? fullName,
    String? email,
    UserRole? role,
    Value<String?> branchId = const Value.absent(),
    bool? isActive,
  }) => AppUser(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    role: role ?? this.role,
    branchId: branchId.present ? branchId.value : this.branchId,
    isActive: isActive ?? this.isActive,
  );
  AppUser copyWithCompanion(UsersCompanion data) {
    return AppUser(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      fullName: data.fullName.present ? data.fullName.value : this.fullName,
      email: data.email.present ? data.email.value : this.email,
      role: data.role.present ? data.role.value : this.role,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppUser(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('fullName: $fullName, ')
          ..write('email: $email, ')
          ..write('role: $role, ')
          ..write('branchId: $branchId, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    fullName,
    email,
    role,
    branchId,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppUser &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.fullName == this.fullName &&
          other.email == this.email &&
          other.role == this.role &&
          other.branchId == this.branchId &&
          other.isActive == this.isActive);
}

class UsersCompanion extends UpdateCompanion<AppUser> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> fullName;
  final Value<String> email;
  final Value<UserRole> role;
  final Value<String?> branchId;
  final Value<bool> isActive;
  final Value<int> rowid;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.fullName = const Value.absent(),
    this.email = const Value.absent(),
    this.role = const Value.absent(),
    this.branchId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String fullName,
    required String email,
    required UserRole role,
    this.branchId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : fullName = Value(fullName),
       email = Value(email),
       role = Value(role);
  static Insertable<AppUser> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? fullName,
    Expression<String>? email,
    Expression<String>? role,
    Expression<String>? branchId,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (fullName != null) 'full_name': fullName,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
      if (branchId != null) 'branch_id': branchId,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? fullName,
    Value<String>? email,
    Value<UserRole>? role,
    Value<String?>? branchId,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      branchId: branchId ?? this.branchId,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $UsersTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (fullName.present) {
      map['full_name'] = Variable<String>(fullName.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(
        $UsersTable.$converterrole.toSql(role.value),
      );
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('fullName: $fullName, ')
          ..write('email: $email, ')
          ..write('role: $role, ')
          ..write('branchId: $branchId, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemCategoriesTable extends ItemCategories
    with TableInfo<$ItemCategoriesTable, ItemCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ItemCategoriesTable.$convertersyncStatus);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    name,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ItemCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemCategory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ItemCategoriesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $ItemCategoriesTable createAlias(String alias) {
    return $ItemCategoriesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class ItemCategory extends DataClass implements Insertable<ItemCategory> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String name;
  const ItemCategory({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.name,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ItemCategoriesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['name'] = Variable<String>(name);
    return map;
  }

  ItemCategoriesCompanion toCompanion(bool nullToAbsent) {
    return ItemCategoriesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      name: Value(name),
    );
  }

  factory ItemCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemCategory(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'name': serializer.toJson<String>(name),
    };
  }

  ItemCategory copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? name,
  }) => ItemCategory(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    name: name ?? this.name,
  );
  ItemCategory copyWithCompanion(ItemCategoriesCompanion data) {
    return ItemCategory(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemCategory(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, createdAt, updatedAt, deletedAt, syncStatus, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemCategory &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.name == this.name);
}

class ItemCategoriesCompanion extends UpdateCompanion<ItemCategory> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> name;
  final Value<int> rowid;
  const ItemCategoriesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemCategoriesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String name,
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<ItemCategory> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemCategoriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return ItemCategoriesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ItemCategoriesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemsTable extends Items with TableInfo<$ItemsTable, Item> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ItemsTable.$convertersyncStatus);
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 190,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_categories (id)',
    ),
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minStockRoomMeta = const VerificationMeta(
    'minStockRoom',
  );
  @override
  late final GeneratedColumn<int> minStockRoom = GeneratedColumn<int>(
    'min_stock_room',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _minStockBranchMeta = const VerificationMeta(
    'minStockBranch',
  );
  @override
  late final GeneratedColumn<int> minStockBranch = GeneratedColumn<int>(
    'min_stock_branch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hasExpiryMeta = const VerificationMeta(
    'hasExpiry',
  );
  @override
  late final GeneratedColumn<bool> hasExpiry = GeneratedColumn<bool>(
    'has_expiry',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_expiry" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _expiryAlertDaysMeta = const VerificationMeta(
    'expiryAlertDays',
  );
  @override
  late final GeneratedColumn<int> expiryAlertDays = GeneratedColumn<int>(
    'expiry_alert_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    sku,
    name,
    categoryId,
    unit,
    minStockRoom,
    minStockBranch,
    hasExpiry,
    expiryAlertDays,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items';
  @override
  VerificationContext validateIntegrity(
    Insertable<Item> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('min_stock_room')) {
      context.handle(
        _minStockRoomMeta,
        minStockRoom.isAcceptableOrUnknown(
          data['min_stock_room']!,
          _minStockRoomMeta,
        ),
      );
    }
    if (data.containsKey('min_stock_branch')) {
      context.handle(
        _minStockBranchMeta,
        minStockBranch.isAcceptableOrUnknown(
          data['min_stock_branch']!,
          _minStockBranchMeta,
        ),
      );
    }
    if (data.containsKey('has_expiry')) {
      context.handle(
        _hasExpiryMeta,
        hasExpiry.isAcceptableOrUnknown(data['has_expiry']!, _hasExpiryMeta),
      );
    }
    if (data.containsKey('expiry_alert_days')) {
      context.handle(
        _expiryAlertDaysMeta,
        expiryAlertDays.isAcceptableOrUnknown(
          data['expiry_alert_days']!,
          _expiryAlertDaysMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Item map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Item(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ItemsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      minStockRoom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_stock_room'],
      )!,
      minStockBranch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_stock_branch'],
      )!,
      hasExpiry: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_expiry'],
      )!,
      expiryAlertDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expiry_alert_days'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $ItemsTable createAlias(String alias) {
    return $ItemsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class Item extends DataClass implements Insertable<Item> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String sku;
  final String name;
  final String categoryId;
  final String unit;
  final int minStockRoom;
  final int minStockBranch;
  final bool hasExpiry;
  final int expiryAlertDays;
  final bool isActive;
  const Item({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.sku,
    required this.name,
    required this.categoryId,
    required this.unit,
    required this.minStockRoom,
    required this.minStockBranch,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ItemsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['sku'] = Variable<String>(sku);
    map['name'] = Variable<String>(name);
    map['category_id'] = Variable<String>(categoryId);
    map['unit'] = Variable<String>(unit);
    map['min_stock_room'] = Variable<int>(minStockRoom);
    map['min_stock_branch'] = Variable<int>(minStockBranch);
    map['has_expiry'] = Variable<bool>(hasExpiry);
    map['expiry_alert_days'] = Variable<int>(expiryAlertDays);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ItemsCompanion toCompanion(bool nullToAbsent) {
    return ItemsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      sku: Value(sku),
      name: Value(name),
      categoryId: Value(categoryId),
      unit: Value(unit),
      minStockRoom: Value(minStockRoom),
      minStockBranch: Value(minStockBranch),
      hasExpiry: Value(hasExpiry),
      expiryAlertDays: Value(expiryAlertDays),
      isActive: Value(isActive),
    );
  }

  factory Item.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Item(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      sku: serializer.fromJson<String>(json['sku']),
      name: serializer.fromJson<String>(json['name']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      unit: serializer.fromJson<String>(json['unit']),
      minStockRoom: serializer.fromJson<int>(json['minStockRoom']),
      minStockBranch: serializer.fromJson<int>(json['minStockBranch']),
      hasExpiry: serializer.fromJson<bool>(json['hasExpiry']),
      expiryAlertDays: serializer.fromJson<int>(json['expiryAlertDays']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'sku': serializer.toJson<String>(sku),
      'name': serializer.toJson<String>(name),
      'categoryId': serializer.toJson<String>(categoryId),
      'unit': serializer.toJson<String>(unit),
      'minStockRoom': serializer.toJson<int>(minStockRoom),
      'minStockBranch': serializer.toJson<int>(minStockBranch),
      'hasExpiry': serializer.toJson<bool>(hasExpiry),
      'expiryAlertDays': serializer.toJson<int>(expiryAlertDays),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Item copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? sku,
    String? name,
    String? categoryId,
    String? unit,
    int? minStockRoom,
    int? minStockBranch,
    bool? hasExpiry,
    int? expiryAlertDays,
    bool? isActive,
  }) => Item(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    sku: sku ?? this.sku,
    name: name ?? this.name,
    categoryId: categoryId ?? this.categoryId,
    unit: unit ?? this.unit,
    minStockRoom: minStockRoom ?? this.minStockRoom,
    minStockBranch: minStockBranch ?? this.minStockBranch,
    hasExpiry: hasExpiry ?? this.hasExpiry,
    expiryAlertDays: expiryAlertDays ?? this.expiryAlertDays,
    isActive: isActive ?? this.isActive,
  );
  Item copyWithCompanion(ItemsCompanion data) {
    return Item(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      sku: data.sku.present ? data.sku.value : this.sku,
      name: data.name.present ? data.name.value : this.name,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      unit: data.unit.present ? data.unit.value : this.unit,
      minStockRoom: data.minStockRoom.present
          ? data.minStockRoom.value
          : this.minStockRoom,
      minStockBranch: data.minStockBranch.present
          ? data.minStockBranch.value
          : this.minStockBranch,
      hasExpiry: data.hasExpiry.present ? data.hasExpiry.value : this.hasExpiry,
      expiryAlertDays: data.expiryAlertDays.present
          ? data.expiryAlertDays.value
          : this.expiryAlertDays,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Item(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('sku: $sku, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('unit: $unit, ')
          ..write('minStockRoom: $minStockRoom, ')
          ..write('minStockBranch: $minStockBranch, ')
          ..write('hasExpiry: $hasExpiry, ')
          ..write('expiryAlertDays: $expiryAlertDays, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    sku,
    name,
    categoryId,
    unit,
    minStockRoom,
    minStockBranch,
    hasExpiry,
    expiryAlertDays,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Item &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.sku == this.sku &&
          other.name == this.name &&
          other.categoryId == this.categoryId &&
          other.unit == this.unit &&
          other.minStockRoom == this.minStockRoom &&
          other.minStockBranch == this.minStockBranch &&
          other.hasExpiry == this.hasExpiry &&
          other.expiryAlertDays == this.expiryAlertDays &&
          other.isActive == this.isActive);
}

class ItemsCompanion extends UpdateCompanion<Item> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> sku;
  final Value<String> name;
  final Value<String> categoryId;
  final Value<String> unit;
  final Value<int> minStockRoom;
  final Value<int> minStockBranch;
  final Value<bool> hasExpiry;
  final Value<int> expiryAlertDays;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ItemsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.sku = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.unit = const Value.absent(),
    this.minStockRoom = const Value.absent(),
    this.minStockBranch = const Value.absent(),
    this.hasExpiry = const Value.absent(),
    this.expiryAlertDays = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    this.minStockRoom = const Value.absent(),
    this.minStockBranch = const Value.absent(),
    this.hasExpiry = const Value.absent(),
    this.expiryAlertDays = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sku = Value(sku),
       name = Value(name),
       categoryId = Value(categoryId),
       unit = Value(unit);
  static Insertable<Item> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? sku,
    Expression<String>? name,
    Expression<String>? categoryId,
    Expression<String>? unit,
    Expression<int>? minStockRoom,
    Expression<int>? minStockBranch,
    Expression<bool>? hasExpiry,
    Expression<int>? expiryAlertDays,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (sku != null) 'sku': sku,
      if (name != null) 'name': name,
      if (categoryId != null) 'category_id': categoryId,
      if (unit != null) 'unit': unit,
      if (minStockRoom != null) 'min_stock_room': minStockRoom,
      if (minStockBranch != null) 'min_stock_branch': minStockBranch,
      if (hasExpiry != null) 'has_expiry': hasExpiry,
      if (expiryAlertDays != null) 'expiry_alert_days': expiryAlertDays,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? sku,
    Value<String>? name,
    Value<String>? categoryId,
    Value<String>? unit,
    Value<int>? minStockRoom,
    Value<int>? minStockBranch,
    Value<bool>? hasExpiry,
    Value<int>? expiryAlertDays,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return ItemsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      unit: unit ?? this.unit,
      minStockRoom: minStockRoom ?? this.minStockRoom,
      minStockBranch: minStockBranch ?? this.minStockBranch,
      hasExpiry: hasExpiry ?? this.hasExpiry,
      expiryAlertDays: expiryAlertDays ?? this.expiryAlertDays,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ItemsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (minStockRoom.present) {
      map['min_stock_room'] = Variable<int>(minStockRoom.value);
    }
    if (minStockBranch.present) {
      map['min_stock_branch'] = Variable<int>(minStockBranch.value);
    }
    if (hasExpiry.present) {
      map['has_expiry'] = Variable<bool>(hasExpiry.value);
    }
    if (expiryAlertDays.present) {
      map['expiry_alert_days'] = Variable<int>(expiryAlertDays.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('sku: $sku, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('unit: $unit, ')
          ..write('minStockRoom: $minStockRoom, ')
          ..write('minStockBranch: $minStockBranch, ')
          ..write('hasExpiry: $hasExpiry, ')
          ..write('expiryAlertDays: $expiryAlertDays, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemBatchesTable extends ItemBatches
    with TableInfo<$ItemBatchesTable, ItemBatch> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ItemBatchesTable.$convertersyncStatus);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchNoMeta = const VerificationMeta(
    'batchNo',
  );
  @override
  late final GeneratedColumn<String> batchNo = GeneratedColumn<String>(
    'batch_no',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiryDateMeta = const VerificationMeta(
    'expiryDate',
  );
  @override
  late final GeneratedColumn<DateTime> expiryDate = GeneratedColumn<DateTime>(
    'expiry_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    itemId,
    batchNo,
    expiryDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_batches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemBatch> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_no')) {
      context.handle(
        _batchNoMeta,
        batchNo.isAcceptableOrUnknown(data['batch_no']!, _batchNoMeta),
      );
    } else if (isInserting) {
      context.missing(_batchNoMeta);
    }
    if (data.containsKey('expiry_date')) {
      context.handle(
        _expiryDateMeta,
        expiryDate.isAcceptableOrUnknown(data['expiry_date']!, _expiryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_expiryDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {itemId, batchNo},
  ];
  @override
  ItemBatch map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemBatch(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ItemBatchesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_no'],
      )!,
      expiryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expiry_date'],
      )!,
    );
  }

  @override
  $ItemBatchesTable createAlias(String alias) {
    return $ItemBatchesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class ItemBatch extends DataClass implements Insertable<ItemBatch> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String itemId;
  final String batchNo;
  final DateTime expiryDate;
  const ItemBatch({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.itemId,
    required this.batchNo,
    required this.expiryDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ItemBatchesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['item_id'] = Variable<String>(itemId);
    map['batch_no'] = Variable<String>(batchNo);
    map['expiry_date'] = Variable<DateTime>(expiryDate);
    return map;
  }

  ItemBatchesCompanion toCompanion(bool nullToAbsent) {
    return ItemBatchesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      itemId: Value(itemId),
      batchNo: Value(batchNo),
      expiryDate: Value(expiryDate),
    );
  }

  factory ItemBatch.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemBatch(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchNo: serializer.fromJson<String>(json['batchNo']),
      expiryDate: serializer.fromJson<DateTime>(json['expiryDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'itemId': serializer.toJson<String>(itemId),
      'batchNo': serializer.toJson<String>(batchNo),
      'expiryDate': serializer.toJson<DateTime>(expiryDate),
    };
  }

  ItemBatch copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? itemId,
    String? batchNo,
    DateTime? expiryDate,
  }) => ItemBatch(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    itemId: itemId ?? this.itemId,
    batchNo: batchNo ?? this.batchNo,
    expiryDate: expiryDate ?? this.expiryDate,
  );
  ItemBatch copyWithCompanion(ItemBatchesCompanion data) {
    return ItemBatch(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchNo: data.batchNo.present ? data.batchNo.value : this.batchNo,
      expiryDate: data.expiryDate.present
          ? data.expiryDate.value
          : this.expiryDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemBatch(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('itemId: $itemId, ')
          ..write('batchNo: $batchNo, ')
          ..write('expiryDate: $expiryDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    itemId,
    batchNo,
    expiryDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemBatch &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.itemId == this.itemId &&
          other.batchNo == this.batchNo &&
          other.expiryDate == this.expiryDate);
}

class ItemBatchesCompanion extends UpdateCompanion<ItemBatch> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> itemId;
  final Value<String> batchNo;
  final Value<DateTime> expiryDate;
  final Value<int> rowid;
  const ItemBatchesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchNo = const Value.absent(),
    this.expiryDate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemBatchesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       batchNo = Value(batchNo),
       expiryDate = Value(expiryDate);
  static Insertable<ItemBatch> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? itemId,
    Expression<String>? batchNo,
    Expression<DateTime>? expiryDate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (itemId != null) 'item_id': itemId,
      if (batchNo != null) 'batch_no': batchNo,
      if (expiryDate != null) 'expiry_date': expiryDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemBatchesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? itemId,
    Value<String>? batchNo,
    Value<DateTime>? expiryDate,
    Value<int>? rowid,
  }) {
    return ItemBatchesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      itemId: itemId ?? this.itemId,
      batchNo: batchNo ?? this.batchNo,
      expiryDate: expiryDate ?? this.expiryDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ItemBatchesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchNo.present) {
      map['batch_no'] = Variable<String>(batchNo.value);
    }
    if (expiryDate.present) {
      map['expiry_date'] = Variable<DateTime>(expiryDate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemBatchesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('itemId: $itemId, ')
          ..write('batchNo: $batchNo, ')
          ..write('expiryDate: $expiryDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockLocationsTable extends StockLocations
    with TableInfo<$StockLocationsTable, StockLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($StockLocationsTable.$convertersyncStatus);
  @override
  late final GeneratedColumnWithTypeConverter<StockLocationType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StockLocationType>($StockLocationsTable.$convertertype);
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES rooms (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 190,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    type,
    branchId,
    roomId,
    name,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_locations';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockLocation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockLocation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $StockLocationsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      type: $StockLocationsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $StockLocationsTable createAlias(String alias) {
    return $StockLocationsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<StockLocationType, String> $convertertype =
      const StockLocationTypeConverter();
}

class StockLocation extends DataClass implements Insertable<StockLocation> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final StockLocationType type;
  final String? branchId;
  final String? roomId;
  final String name;
  const StockLocation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.type,
    this.branchId,
    this.roomId,
    required this.name,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $StockLocationsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    {
      map['type'] = Variable<String>(
        $StockLocationsTable.$convertertype.toSql(type),
      );
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    if (!nullToAbsent || roomId != null) {
      map['room_id'] = Variable<String>(roomId);
    }
    map['name'] = Variable<String>(name);
    return map;
  }

  StockLocationsCompanion toCompanion(bool nullToAbsent) {
    return StockLocationsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      type: Value(type),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      roomId: roomId == null && nullToAbsent
          ? const Value.absent()
          : Value(roomId),
      name: Value(name),
    );
  }

  factory StockLocation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockLocation(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      type: serializer.fromJson<StockLocationType>(json['type']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      roomId: serializer.fromJson<String?>(json['roomId']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'type': serializer.toJson<StockLocationType>(type),
      'branchId': serializer.toJson<String?>(branchId),
      'roomId': serializer.toJson<String?>(roomId),
      'name': serializer.toJson<String>(name),
    };
  }

  StockLocation copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    StockLocationType? type,
    Value<String?> branchId = const Value.absent(),
    Value<String?> roomId = const Value.absent(),
    String? name,
  }) => StockLocation(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    type: type ?? this.type,
    branchId: branchId.present ? branchId.value : this.branchId,
    roomId: roomId.present ? roomId.value : this.roomId,
    name: name ?? this.name,
  );
  StockLocation copyWithCompanion(StockLocationsCompanion data) {
    return StockLocation(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      type: data.type.present ? data.type.value : this.type,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockLocation(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('type: $type, ')
          ..write('branchId: $branchId, ')
          ..write('roomId: $roomId, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    type,
    branchId,
    roomId,
    name,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockLocation &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.type == this.type &&
          other.branchId == this.branchId &&
          other.roomId == this.roomId &&
          other.name == this.name);
}

class StockLocationsCompanion extends UpdateCompanion<StockLocation> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<StockLocationType> type;
  final Value<String?> branchId;
  final Value<String?> roomId;
  final Value<String> name;
  final Value<int> rowid;
  const StockLocationsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.type = const Value.absent(),
    this.branchId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockLocationsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required StockLocationType type,
    this.branchId = const Value.absent(),
    this.roomId = const Value.absent(),
    required String name,
    this.rowid = const Value.absent(),
  }) : type = Value(type),
       name = Value(name);
  static Insertable<StockLocation> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? type,
    Expression<String>? branchId,
    Expression<String>? roomId,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (type != null) 'type': type,
      if (branchId != null) 'branch_id': branchId,
      if (roomId != null) 'room_id': roomId,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockLocationsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<StockLocationType>? type,
    Value<String?>? branchId,
    Value<String?>? roomId,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return StockLocationsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      type: type ?? this.type,
      branchId: branchId ?? this.branchId,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $StockLocationsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $StockLocationsTable.$convertertype.toSql(type.value),
      );
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockLocationsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('type: $type, ')
          ..write('branchId: $branchId, ')
          ..write('roomId: $roomId, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockBalancesTable extends StockBalances
    with TableInfo<$StockBalancesTable, StockBalance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockBalancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($StockBalancesTable.$convertersyncStatus);
  static const VerificationMeta _locationIdMeta = const VerificationMeta(
    'locationId',
  );
  @override
  late final GeneratedColumn<String> locationId = GeneratedColumn<String>(
    'location_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_locations (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _qtyOnHandMeta = const VerificationMeta(
    'qtyOnHand',
  );
  @override
  late final GeneratedColumn<int> qtyOnHand = GeneratedColumn<int>(
    'qty_on_hand',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    locationId,
    itemId,
    batchId,
    qtyOnHand,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_balances';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockBalance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('location_id')) {
      context.handle(
        _locationIdMeta,
        locationId.isAcceptableOrUnknown(data['location_id']!, _locationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_locationIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('qty_on_hand')) {
      context.handle(
        _qtyOnHandMeta,
        qtyOnHand.isAcceptableOrUnknown(data['qty_on_hand']!, _qtyOnHandMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyOnHandMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockBalance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockBalance(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $StockBalancesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      locationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      qtyOnHand: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty_on_hand'],
      )!,
    );
  }

  @override
  $StockBalancesTable createAlias(String alias) {
    return $StockBalancesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class StockBalance extends DataClass implements Insertable<StockBalance> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String locationId;
  final String itemId;
  final String? batchId;

  /// Balance in **milli-units** — `Quantity.scale` (1000) per whole unit, so
  /// 0.5 on the shelf is stored as 500 (spec Q-3, schema v2).
  ///
  /// INTEGER, never REAL: a REAL balance would accumulate binary rounding error
  /// across postings and could drift away from the ledger it mirrors. The
  /// CHECK below applies to the scaled value, so it still means "never
  /// negative" (G-A2).
  final int qtyOnHand;
  const StockBalance({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.locationId,
    required this.itemId,
    this.batchId,
    required this.qtyOnHand,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $StockBalancesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['location_id'] = Variable<String>(locationId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['qty_on_hand'] = Variable<int>(qtyOnHand);
    return map;
  }

  StockBalancesCompanion toCompanion(bool nullToAbsent) {
    return StockBalancesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      locationId: Value(locationId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      qtyOnHand: Value(qtyOnHand),
    );
  }

  factory StockBalance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockBalance(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      locationId: serializer.fromJson<String>(json['locationId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      qtyOnHand: serializer.fromJson<int>(json['qtyOnHand']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'locationId': serializer.toJson<String>(locationId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'qtyOnHand': serializer.toJson<int>(qtyOnHand),
    };
  }

  StockBalance copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? locationId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? qtyOnHand,
  }) => StockBalance(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    locationId: locationId ?? this.locationId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    qtyOnHand: qtyOnHand ?? this.qtyOnHand,
  );
  StockBalance copyWithCompanion(StockBalancesCompanion data) {
    return StockBalance(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      locationId: data.locationId.present
          ? data.locationId.value
          : this.locationId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      qtyOnHand: data.qtyOnHand.present ? data.qtyOnHand.value : this.qtyOnHand,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockBalance(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('locationId: $locationId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qtyOnHand: $qtyOnHand')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    locationId,
    itemId,
    batchId,
    qtyOnHand,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockBalance &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.locationId == this.locationId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.qtyOnHand == this.qtyOnHand);
}

class StockBalancesCompanion extends UpdateCompanion<StockBalance> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> locationId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> qtyOnHand;
  final Value<int> rowid;
  const StockBalancesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.locationId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.qtyOnHand = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockBalancesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String locationId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int qtyOnHand,
    this.rowid = const Value.absent(),
  }) : locationId = Value(locationId),
       itemId = Value(itemId),
       qtyOnHand = Value(qtyOnHand);
  static Insertable<StockBalance> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? locationId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? qtyOnHand,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (locationId != null) 'location_id': locationId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (qtyOnHand != null) 'qty_on_hand': qtyOnHand,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockBalancesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? locationId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? qtyOnHand,
    Value<int>? rowid,
  }) {
    return StockBalancesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      locationId: locationId ?? this.locationId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      qtyOnHand: qtyOnHand ?? this.qtyOnHand,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $StockBalancesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (locationId.present) {
      map['location_id'] = Variable<String>(locationId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (qtyOnHand.present) {
      map['qty_on_hand'] = Variable<int>(qtyOnHand.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockBalancesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('locationId: $locationId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qtyOnHand: $qtyOnHand, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockMovementsTable extends StockMovements
    with TableInfo<$StockMovementsTable, StockMovement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockMovementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($StockMovementsTable.$convertersyncStatus);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _fromLocationIdMeta = const VerificationMeta(
    'fromLocationId',
  );
  @override
  late final GeneratedColumn<String> fromLocationId = GeneratedColumn<String>(
    'from_location_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_locations (id)',
    ),
  );
  static const VerificationMeta _toLocationIdMeta = const VerificationMeta(
    'toLocationId',
  );
  @override
  late final GeneratedColumn<String> toLocationId = GeneratedColumn<String>(
    'to_location_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_locations (id)',
    ),
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<StockMovementType, String>
  movementType =
      GeneratedColumn<String>(
        'movement_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<StockMovementType>(
        $StockMovementsTable.$convertermovementType,
      );
  static const VerificationMeta _refDocTypeMeta = const VerificationMeta(
    'refDocType',
  );
  @override
  late final GeneratedColumn<String> refDocType = GeneratedColumn<String>(
    'ref_doc_type',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 16),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refDocIdMeta = const VerificationMeta(
    'refDocId',
  );
  @override
  late final GeneratedColumn<String> refDocId = GeneratedColumn<String>(
    'ref_doc_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actorUserIdMeta = const VerificationMeta(
    'actorUserId',
  );
  @override
  late final GeneratedColumn<String> actorUserId = GeneratedColumn<String>(
    'actor_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reversalOfMovementIdMeta =
      const VerificationMeta('reversalOfMovementId');
  @override
  late final GeneratedColumn<String> reversalOfMovementId =
      GeneratedColumn<String>(
        'reversal_of_movement_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES stock_movements (id)',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    itemId,
    batchId,
    fromLocationId,
    toLocationId,
    qty,
    movementType,
    refDocType,
    refDocId,
    actorUserId,
    note,
    reversalOfMovementId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockMovement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('from_location_id')) {
      context.handle(
        _fromLocationIdMeta,
        fromLocationId.isAcceptableOrUnknown(
          data['from_location_id']!,
          _fromLocationIdMeta,
        ),
      );
    }
    if (data.containsKey('to_location_id')) {
      context.handle(
        _toLocationIdMeta,
        toLocationId.isAcceptableOrUnknown(
          data['to_location_id']!,
          _toLocationIdMeta,
        ),
      );
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('ref_doc_type')) {
      context.handle(
        _refDocTypeMeta,
        refDocType.isAcceptableOrUnknown(
          data['ref_doc_type']!,
          _refDocTypeMeta,
        ),
      );
    }
    if (data.containsKey('ref_doc_id')) {
      context.handle(
        _refDocIdMeta,
        refDocId.isAcceptableOrUnknown(data['ref_doc_id']!, _refDocIdMeta),
      );
    }
    if (data.containsKey('actor_user_id')) {
      context.handle(
        _actorUserIdMeta,
        actorUserId.isAcceptableOrUnknown(
          data['actor_user_id']!,
          _actorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actorUserIdMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('reversal_of_movement_id')) {
      context.handle(
        _reversalOfMovementIdMeta,
        reversalOfMovementId.isAcceptableOrUnknown(
          data['reversal_of_movement_id']!,
          _reversalOfMovementIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockMovement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockMovement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $StockMovementsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      fromLocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_location_id'],
      ),
      toLocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_location_id'],
      ),
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty'],
      )!,
      movementType: $StockMovementsTable.$convertermovementType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}movement_type'],
        )!,
      ),
      refDocType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_doc_type'],
      ),
      refDocId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_doc_id'],
      ),
      actorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_user_id'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      reversalOfMovementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reversal_of_movement_id'],
      ),
    );
  }

  @override
  $StockMovementsTable createAlias(String alias) {
    return $StockMovementsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<StockMovementType, String> $convertermovementType =
      const StockMovementTypeConverter();
}

class StockMovement extends DataClass implements Insertable<StockMovement> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String itemId;
  final String? batchId;
  final String? fromLocationId;
  final String? toLocationId;

  /// Movement quantity in **milli-units**, matching
  /// [StockBalances.qtyOnHand] (spec Q-3). `CHECK (qty > 0)` below is evaluated
  /// on the scaled value, so the smallest postable movement is 0.001 units.
  final int qty;
  final StockMovementType movementType;
  final String? refDocType;
  final String? refDocId;
  final String actorUserId;
  final String? note;
  final String? reversalOfMovementId;
  const StockMovement({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.itemId,
    this.batchId,
    this.fromLocationId,
    this.toLocationId,
    required this.qty,
    required this.movementType,
    this.refDocType,
    this.refDocId,
    required this.actorUserId,
    this.note,
    this.reversalOfMovementId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $StockMovementsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    if (!nullToAbsent || fromLocationId != null) {
      map['from_location_id'] = Variable<String>(fromLocationId);
    }
    if (!nullToAbsent || toLocationId != null) {
      map['to_location_id'] = Variable<String>(toLocationId);
    }
    map['qty'] = Variable<int>(qty);
    {
      map['movement_type'] = Variable<String>(
        $StockMovementsTable.$convertermovementType.toSql(movementType),
      );
    }
    if (!nullToAbsent || refDocType != null) {
      map['ref_doc_type'] = Variable<String>(refDocType);
    }
    if (!nullToAbsent || refDocId != null) {
      map['ref_doc_id'] = Variable<String>(refDocId);
    }
    map['actor_user_id'] = Variable<String>(actorUserId);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || reversalOfMovementId != null) {
      map['reversal_of_movement_id'] = Variable<String>(reversalOfMovementId);
    }
    return map;
  }

  StockMovementsCompanion toCompanion(bool nullToAbsent) {
    return StockMovementsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      fromLocationId: fromLocationId == null && nullToAbsent
          ? const Value.absent()
          : Value(fromLocationId),
      toLocationId: toLocationId == null && nullToAbsent
          ? const Value.absent()
          : Value(toLocationId),
      qty: Value(qty),
      movementType: Value(movementType),
      refDocType: refDocType == null && nullToAbsent
          ? const Value.absent()
          : Value(refDocType),
      refDocId: refDocId == null && nullToAbsent
          ? const Value.absent()
          : Value(refDocId),
      actorUserId: Value(actorUserId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      reversalOfMovementId: reversalOfMovementId == null && nullToAbsent
          ? const Value.absent()
          : Value(reversalOfMovementId),
    );
  }

  factory StockMovement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockMovement(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      fromLocationId: serializer.fromJson<String?>(json['fromLocationId']),
      toLocationId: serializer.fromJson<String?>(json['toLocationId']),
      qty: serializer.fromJson<int>(json['qty']),
      movementType: serializer.fromJson<StockMovementType>(
        json['movementType'],
      ),
      refDocType: serializer.fromJson<String?>(json['refDocType']),
      refDocId: serializer.fromJson<String?>(json['refDocId']),
      actorUserId: serializer.fromJson<String>(json['actorUserId']),
      note: serializer.fromJson<String?>(json['note']),
      reversalOfMovementId: serializer.fromJson<String?>(
        json['reversalOfMovementId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'fromLocationId': serializer.toJson<String?>(fromLocationId),
      'toLocationId': serializer.toJson<String?>(toLocationId),
      'qty': serializer.toJson<int>(qty),
      'movementType': serializer.toJson<StockMovementType>(movementType),
      'refDocType': serializer.toJson<String?>(refDocType),
      'refDocId': serializer.toJson<String?>(refDocId),
      'actorUserId': serializer.toJson<String>(actorUserId),
      'note': serializer.toJson<String?>(note),
      'reversalOfMovementId': serializer.toJson<String?>(reversalOfMovementId),
    };
  }

  StockMovement copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    Value<String?> fromLocationId = const Value.absent(),
    Value<String?> toLocationId = const Value.absent(),
    int? qty,
    StockMovementType? movementType,
    Value<String?> refDocType = const Value.absent(),
    Value<String?> refDocId = const Value.absent(),
    String? actorUserId,
    Value<String?> note = const Value.absent(),
    Value<String?> reversalOfMovementId = const Value.absent(),
  }) => StockMovement(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    fromLocationId: fromLocationId.present
        ? fromLocationId.value
        : this.fromLocationId,
    toLocationId: toLocationId.present ? toLocationId.value : this.toLocationId,
    qty: qty ?? this.qty,
    movementType: movementType ?? this.movementType,
    refDocType: refDocType.present ? refDocType.value : this.refDocType,
    refDocId: refDocId.present ? refDocId.value : this.refDocId,
    actorUserId: actorUserId ?? this.actorUserId,
    note: note.present ? note.value : this.note,
    reversalOfMovementId: reversalOfMovementId.present
        ? reversalOfMovementId.value
        : this.reversalOfMovementId,
  );
  StockMovement copyWithCompanion(StockMovementsCompanion data) {
    return StockMovement(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      fromLocationId: data.fromLocationId.present
          ? data.fromLocationId.value
          : this.fromLocationId,
      toLocationId: data.toLocationId.present
          ? data.toLocationId.value
          : this.toLocationId,
      qty: data.qty.present ? data.qty.value : this.qty,
      movementType: data.movementType.present
          ? data.movementType.value
          : this.movementType,
      refDocType: data.refDocType.present
          ? data.refDocType.value
          : this.refDocType,
      refDocId: data.refDocId.present ? data.refDocId.value : this.refDocId,
      actorUserId: data.actorUserId.present
          ? data.actorUserId.value
          : this.actorUserId,
      note: data.note.present ? data.note.value : this.note,
      reversalOfMovementId: data.reversalOfMovementId.present
          ? data.reversalOfMovementId.value
          : this.reversalOfMovementId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockMovement(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('fromLocationId: $fromLocationId, ')
          ..write('toLocationId: $toLocationId, ')
          ..write('qty: $qty, ')
          ..write('movementType: $movementType, ')
          ..write('refDocType: $refDocType, ')
          ..write('refDocId: $refDocId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('note: $note, ')
          ..write('reversalOfMovementId: $reversalOfMovementId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    itemId,
    batchId,
    fromLocationId,
    toLocationId,
    qty,
    movementType,
    refDocType,
    refDocId,
    actorUserId,
    note,
    reversalOfMovementId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockMovement &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.fromLocationId == this.fromLocationId &&
          other.toLocationId == this.toLocationId &&
          other.qty == this.qty &&
          other.movementType == this.movementType &&
          other.refDocType == this.refDocType &&
          other.refDocId == this.refDocId &&
          other.actorUserId == this.actorUserId &&
          other.note == this.note &&
          other.reversalOfMovementId == this.reversalOfMovementId);
}

class StockMovementsCompanion extends UpdateCompanion<StockMovement> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<String?> fromLocationId;
  final Value<String?> toLocationId;
  final Value<int> qty;
  final Value<StockMovementType> movementType;
  final Value<String?> refDocType;
  final Value<String?> refDocId;
  final Value<String> actorUserId;
  final Value<String?> note;
  final Value<String?> reversalOfMovementId;
  final Value<int> rowid;
  const StockMovementsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.fromLocationId = const Value.absent(),
    this.toLocationId = const Value.absent(),
    this.qty = const Value.absent(),
    this.movementType = const Value.absent(),
    this.refDocType = const Value.absent(),
    this.refDocId = const Value.absent(),
    this.actorUserId = const Value.absent(),
    this.note = const Value.absent(),
    this.reversalOfMovementId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockMovementsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String itemId,
    this.batchId = const Value.absent(),
    this.fromLocationId = const Value.absent(),
    this.toLocationId = const Value.absent(),
    required int qty,
    required StockMovementType movementType,
    this.refDocType = const Value.absent(),
    this.refDocId = const Value.absent(),
    required String actorUserId,
    this.note = const Value.absent(),
    this.reversalOfMovementId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       qty = Value(qty),
       movementType = Value(movementType),
       actorUserId = Value(actorUserId);
  static Insertable<StockMovement> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<String>? fromLocationId,
    Expression<String>? toLocationId,
    Expression<int>? qty,
    Expression<String>? movementType,
    Expression<String>? refDocType,
    Expression<String>? refDocId,
    Expression<String>? actorUserId,
    Expression<String>? note,
    Expression<String>? reversalOfMovementId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (fromLocationId != null) 'from_location_id': fromLocationId,
      if (toLocationId != null) 'to_location_id': toLocationId,
      if (qty != null) 'qty': qty,
      if (movementType != null) 'movement_type': movementType,
      if (refDocType != null) 'ref_doc_type': refDocType,
      if (refDocId != null) 'ref_doc_id': refDocId,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (note != null) 'note': note,
      if (reversalOfMovementId != null)
        'reversal_of_movement_id': reversalOfMovementId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockMovementsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<String?>? fromLocationId,
    Value<String?>? toLocationId,
    Value<int>? qty,
    Value<StockMovementType>? movementType,
    Value<String?>? refDocType,
    Value<String?>? refDocId,
    Value<String>? actorUserId,
    Value<String?>? note,
    Value<String?>? reversalOfMovementId,
    Value<int>? rowid,
  }) {
    return StockMovementsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      fromLocationId: fromLocationId ?? this.fromLocationId,
      toLocationId: toLocationId ?? this.toLocationId,
      qty: qty ?? this.qty,
      movementType: movementType ?? this.movementType,
      refDocType: refDocType ?? this.refDocType,
      refDocId: refDocId ?? this.refDocId,
      actorUserId: actorUserId ?? this.actorUserId,
      note: note ?? this.note,
      reversalOfMovementId: reversalOfMovementId ?? this.reversalOfMovementId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $StockMovementsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (fromLocationId.present) {
      map['from_location_id'] = Variable<String>(fromLocationId.value);
    }
    if (toLocationId.present) {
      map['to_location_id'] = Variable<String>(toLocationId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (movementType.present) {
      map['movement_type'] = Variable<String>(
        $StockMovementsTable.$convertermovementType.toSql(movementType.value),
      );
    }
    if (refDocType.present) {
      map['ref_doc_type'] = Variable<String>(refDocType.value);
    }
    if (refDocId.present) {
      map['ref_doc_id'] = Variable<String>(refDocId.value);
    }
    if (actorUserId.present) {
      map['actor_user_id'] = Variable<String>(actorUserId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (reversalOfMovementId.present) {
      map['reversal_of_movement_id'] = Variable<String>(
        reversalOfMovementId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockMovementsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('fromLocationId: $fromLocationId, ')
          ..write('toLocationId: $toLocationId, ')
          ..write('qty: $qty, ')
          ..write('movementType: $movementType, ')
          ..write('refDocType: $refDocType, ')
          ..write('refDocId: $refDocId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('note: $note, ')
          ..write('reversalOfMovementId: $reversalOfMovementId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockOpnamesTable extends StockOpnames
    with TableInfo<$StockOpnamesTable, StockOpnameRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockOpnamesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($StockOpnamesTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES rooms (id)',
    ),
  );
  static const VerificationMeta _periodYearMeta = const VerificationMeta(
    'periodYear',
  );
  @override
  late final GeneratedColumn<int> periodYear = GeneratedColumn<int>(
    'period_year',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodWeekMeta = const VerificationMeta(
    'periodWeek',
  );
  @override
  late final GeneratedColumn<int> periodWeek = GeneratedColumn<int>(
    'period_week',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countedByMeta = const VerificationMeta(
    'countedBy',
  );
  @override
  late final GeneratedColumn<String> countedBy = GeneratedColumn<String>(
    'counted_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<StockOpnameStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => StockOpnameStatus.draft.dbValue,
  ).withConverter<StockOpnameStatus>($StockOpnamesTable.$converterstatus);
  static const VerificationMeta _submittedAtMeta = const VerificationMeta(
    'submittedAt',
  );
  @override
  late final GeneratedColumn<DateTime> submittedAt = GeneratedColumn<DateTime>(
    'submitted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> reviewedAt = GeneratedColumn<DateTime>(
    'reviewed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewedByMeta = const VerificationMeta(
    'reviewedBy',
  );
  @override
  late final GeneratedColumn<String> reviewedBy = GeneratedColumn<String>(
    'reviewed_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    roomId,
    periodYear,
    periodWeek,
    countedBy,
    status,
    submittedAt,
    reviewedAt,
    reviewedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_opnames';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockOpnameRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('period_year')) {
      context.handle(
        _periodYearMeta,
        periodYear.isAcceptableOrUnknown(data['period_year']!, _periodYearMeta),
      );
    } else if (isInserting) {
      context.missing(_periodYearMeta);
    }
    if (data.containsKey('period_week')) {
      context.handle(
        _periodWeekMeta,
        periodWeek.isAcceptableOrUnknown(data['period_week']!, _periodWeekMeta),
      );
    } else if (isInserting) {
      context.missing(_periodWeekMeta);
    }
    if (data.containsKey('counted_by')) {
      context.handle(
        _countedByMeta,
        countedBy.isAcceptableOrUnknown(data['counted_by']!, _countedByMeta),
      );
    } else if (isInserting) {
      context.missing(_countedByMeta);
    }
    if (data.containsKey('submitted_at')) {
      context.handle(
        _submittedAtMeta,
        submittedAt.isAcceptableOrUnknown(
          data['submitted_at']!,
          _submittedAtMeta,
        ),
      );
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    }
    if (data.containsKey('reviewed_by')) {
      context.handle(
        _reviewedByMeta,
        reviewedBy.isAcceptableOrUnknown(data['reviewed_by']!, _reviewedByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockOpnameRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockOpnameRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $StockOpnamesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      periodYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_year'],
      )!,
      periodWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_week'],
      )!,
      countedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counted_by'],
      )!,
      status: $StockOpnamesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      submittedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}submitted_at'],
      ),
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reviewed_at'],
      ),
      reviewedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reviewed_by'],
      ),
    );
  }

  @override
  $StockOpnamesTable createAlias(String alias) {
    return $StockOpnamesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<StockOpnameStatus, String> $converterstatus =
      const StockOpnameStatusConverter();
}

class StockOpnameRow extends DataClass implements Insertable<StockOpnameRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-SO-{uuid}` until a sync backend assigns the
  /// final `SO-{cabang}-{yyyyMMdd}-{seq}` on submit (G-Y4). Inventing a
  /// server-shaped number offline would produce duplicates across devices.
  /// Uniqueness is enforced by the partial index above, not by `.unique()`:
  /// a column-level UNIQUE would also bind soft-deleted rows.
  final String docNumber;
  final String branchId;
  final String roomId;

  /// ISO week-numbering year — differs from the calendar year around new year.
  final int periodYear;

  /// ISO week number, 1–53.
  final int periodWeek;

  /// The perawat who performs the count.
  final String countedBy;
  final StockOpnameStatus status;

  /// UTC instants (T-1); the UI converts to GMT+8 for display.
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  /// The kepala cabang who locked the document.
  final String? reviewedBy;
  const StockOpnameRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.periodYear,
    required this.periodWeek,
    required this.countedBy,
    required this.status,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $StockOpnamesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['branch_id'] = Variable<String>(branchId);
    map['room_id'] = Variable<String>(roomId);
    map['period_year'] = Variable<int>(periodYear);
    map['period_week'] = Variable<int>(periodWeek);
    map['counted_by'] = Variable<String>(countedBy);
    {
      map['status'] = Variable<String>(
        $StockOpnamesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || submittedAt != null) {
      map['submitted_at'] = Variable<DateTime>(submittedAt);
    }
    if (!nullToAbsent || reviewedAt != null) {
      map['reviewed_at'] = Variable<DateTime>(reviewedAt);
    }
    if (!nullToAbsent || reviewedBy != null) {
      map['reviewed_by'] = Variable<String>(reviewedBy);
    }
    return map;
  }

  StockOpnamesCompanion toCompanion(bool nullToAbsent) {
    return StockOpnamesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      branchId: Value(branchId),
      roomId: Value(roomId),
      periodYear: Value(periodYear),
      periodWeek: Value(periodWeek),
      countedBy: Value(countedBy),
      status: Value(status),
      submittedAt: submittedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedAt),
      reviewedAt: reviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewedAt),
      reviewedBy: reviewedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewedBy),
    );
  }

  factory StockOpnameRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockOpnameRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      branchId: serializer.fromJson<String>(json['branchId']),
      roomId: serializer.fromJson<String>(json['roomId']),
      periodYear: serializer.fromJson<int>(json['periodYear']),
      periodWeek: serializer.fromJson<int>(json['periodWeek']),
      countedBy: serializer.fromJson<String>(json['countedBy']),
      status: serializer.fromJson<StockOpnameStatus>(json['status']),
      submittedAt: serializer.fromJson<DateTime?>(json['submittedAt']),
      reviewedAt: serializer.fromJson<DateTime?>(json['reviewedAt']),
      reviewedBy: serializer.fromJson<String?>(json['reviewedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'branchId': serializer.toJson<String>(branchId),
      'roomId': serializer.toJson<String>(roomId),
      'periodYear': serializer.toJson<int>(periodYear),
      'periodWeek': serializer.toJson<int>(periodWeek),
      'countedBy': serializer.toJson<String>(countedBy),
      'status': serializer.toJson<StockOpnameStatus>(status),
      'submittedAt': serializer.toJson<DateTime?>(submittedAt),
      'reviewedAt': serializer.toJson<DateTime?>(reviewedAt),
      'reviewedBy': serializer.toJson<String?>(reviewedBy),
    };
  }

  StockOpnameRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? branchId,
    String? roomId,
    int? periodYear,
    int? periodWeek,
    String? countedBy,
    StockOpnameStatus? status,
    Value<DateTime?> submittedAt = const Value.absent(),
    Value<DateTime?> reviewedAt = const Value.absent(),
    Value<String?> reviewedBy = const Value.absent(),
  }) => StockOpnameRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    branchId: branchId ?? this.branchId,
    roomId: roomId ?? this.roomId,
    periodYear: periodYear ?? this.periodYear,
    periodWeek: periodWeek ?? this.periodWeek,
    countedBy: countedBy ?? this.countedBy,
    status: status ?? this.status,
    submittedAt: submittedAt.present ? submittedAt.value : this.submittedAt,
    reviewedAt: reviewedAt.present ? reviewedAt.value : this.reviewedAt,
    reviewedBy: reviewedBy.present ? reviewedBy.value : this.reviewedBy,
  );
  StockOpnameRow copyWithCompanion(StockOpnamesCompanion data) {
    return StockOpnameRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      periodYear: data.periodYear.present
          ? data.periodYear.value
          : this.periodYear,
      periodWeek: data.periodWeek.present
          ? data.periodWeek.value
          : this.periodWeek,
      countedBy: data.countedBy.present ? data.countedBy.value : this.countedBy,
      status: data.status.present ? data.status.value : this.status,
      submittedAt: data.submittedAt.present
          ? data.submittedAt.value
          : this.submittedAt,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
      reviewedBy: data.reviewedBy.present
          ? data.reviewedBy.value
          : this.reviewedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockOpnameRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('roomId: $roomId, ')
          ..write('periodYear: $periodYear, ')
          ..write('periodWeek: $periodWeek, ')
          ..write('countedBy: $countedBy, ')
          ..write('status: $status, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('reviewedBy: $reviewedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    roomId,
    periodYear,
    periodWeek,
    countedBy,
    status,
    submittedAt,
    reviewedAt,
    reviewedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockOpnameRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.branchId == this.branchId &&
          other.roomId == this.roomId &&
          other.periodYear == this.periodYear &&
          other.periodWeek == this.periodWeek &&
          other.countedBy == this.countedBy &&
          other.status == this.status &&
          other.submittedAt == this.submittedAt &&
          other.reviewedAt == this.reviewedAt &&
          other.reviewedBy == this.reviewedBy);
}

class StockOpnamesCompanion extends UpdateCompanion<StockOpnameRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> branchId;
  final Value<String> roomId;
  final Value<int> periodYear;
  final Value<int> periodWeek;
  final Value<String> countedBy;
  final Value<StockOpnameStatus> status;
  final Value<DateTime?> submittedAt;
  final Value<DateTime?> reviewedAt;
  final Value<String?> reviewedBy;
  final Value<int> rowid;
  const StockOpnamesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.branchId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.periodYear = const Value.absent(),
    this.periodWeek = const Value.absent(),
    this.countedBy = const Value.absent(),
    this.status = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.reviewedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockOpnamesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String branchId,
    required String roomId,
    required int periodYear,
    required int periodWeek,
    required String countedBy,
    this.status = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.reviewedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       branchId = Value(branchId),
       roomId = Value(roomId),
       periodYear = Value(periodYear),
       periodWeek = Value(periodWeek),
       countedBy = Value(countedBy);
  static Insertable<StockOpnameRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? branchId,
    Expression<String>? roomId,
    Expression<int>? periodYear,
    Expression<int>? periodWeek,
    Expression<String>? countedBy,
    Expression<String>? status,
    Expression<DateTime>? submittedAt,
    Expression<DateTime>? reviewedAt,
    Expression<String>? reviewedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (branchId != null) 'branch_id': branchId,
      if (roomId != null) 'room_id': roomId,
      if (periodYear != null) 'period_year': periodYear,
      if (periodWeek != null) 'period_week': periodWeek,
      if (countedBy != null) 'counted_by': countedBy,
      if (status != null) 'status': status,
      if (submittedAt != null) 'submitted_at': submittedAt,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (reviewedBy != null) 'reviewed_by': reviewedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockOpnamesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? branchId,
    Value<String>? roomId,
    Value<int>? periodYear,
    Value<int>? periodWeek,
    Value<String>? countedBy,
    Value<StockOpnameStatus>? status,
    Value<DateTime?>? submittedAt,
    Value<DateTime?>? reviewedAt,
    Value<String?>? reviewedBy,
    Value<int>? rowid,
  }) {
    return StockOpnamesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      branchId: branchId ?? this.branchId,
      roomId: roomId ?? this.roomId,
      periodYear: periodYear ?? this.periodYear,
      periodWeek: periodWeek ?? this.periodWeek,
      countedBy: countedBy ?? this.countedBy,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $StockOpnamesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (periodYear.present) {
      map['period_year'] = Variable<int>(periodYear.value);
    }
    if (periodWeek.present) {
      map['period_week'] = Variable<int>(periodWeek.value);
    }
    if (countedBy.present) {
      map['counted_by'] = Variable<String>(countedBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $StockOpnamesTable.$converterstatus.toSql(status.value),
      );
    }
    if (submittedAt.present) {
      map['submitted_at'] = Variable<DateTime>(submittedAt.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<DateTime>(reviewedAt.value);
    }
    if (reviewedBy.present) {
      map['reviewed_by'] = Variable<String>(reviewedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockOpnamesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('roomId: $roomId, ')
          ..write('periodYear: $periodYear, ')
          ..write('periodWeek: $periodWeek, ')
          ..write('countedBy: $countedBy, ')
          ..write('status: $status, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('reviewedBy: $reviewedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockOpnameLinesTable extends StockOpnameLines
    with TableInfo<$StockOpnameLinesTable, StockOpnameLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockOpnameLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($StockOpnameLinesTable.$convertersyncStatus);
  static const VerificationMeta _opnameIdMeta = const VerificationMeta(
    'opnameId',
  );
  @override
  late final GeneratedColumn<String> opnameId = GeneratedColumn<String>(
    'opname_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_opnames (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _systemQtyMeta = const VerificationMeta(
    'systemQty',
  );
  @override
  late final GeneratedColumn<int> systemQty = GeneratedColumn<int>(
    'system_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countedQtyMeta = const VerificationMeta(
    'countedQty',
  );
  @override
  late final GeneratedColumn<int> countedQty = GeneratedColumn<int>(
    'counted_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _differenceMeta = const VerificationMeta(
    'difference',
  );
  @override
  late final GeneratedColumn<int> difference = GeneratedColumn<int>(
    'difference',
    aliasedName,
    false,
    generatedAs: GeneratedAs(countedQty - systemQty, true),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    opnameId,
    itemId,
    batchId,
    systemQty,
    countedQty,
    difference,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_opname_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockOpnameLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('opname_id')) {
      context.handle(
        _opnameIdMeta,
        opnameId.isAcceptableOrUnknown(data['opname_id']!, _opnameIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opnameIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('system_qty')) {
      context.handle(
        _systemQtyMeta,
        systemQty.isAcceptableOrUnknown(data['system_qty']!, _systemQtyMeta),
      );
    } else if (isInserting) {
      context.missing(_systemQtyMeta);
    }
    if (data.containsKey('counted_qty')) {
      context.handle(
        _countedQtyMeta,
        countedQty.isAcceptableOrUnknown(data['counted_qty']!, _countedQtyMeta),
      );
    } else if (isInserting) {
      context.missing(_countedQtyMeta);
    }
    if (data.containsKey('difference')) {
      context.handle(
        _differenceMeta,
        difference.isAcceptableOrUnknown(data['difference']!, _differenceMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockOpnameLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockOpnameLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $StockOpnameLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      opnameId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opname_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      systemQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}system_qty'],
      )!,
      countedQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}counted_qty'],
      )!,
      difference: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}difference'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $StockOpnameLinesTable createAlias(String alias) {
    return $StockOpnameLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class StockOpnameLineRow extends DataClass
    implements Insertable<StockOpnameLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String opnameId;
  final String itemId;
  final String? batchId;

  /// Snapshot of the room balance at the moment the opname was created (G-O2).
  /// Nothing in the application updates this column after the insert.
  final int systemQty;

  /// Physically counted quantity in milli-units — `0.5` arrives here as 500.
  final int countedQty;

  /// `counted_qty - system_qty`, computed by SQLite. Negative means stock is
  /// missing, positive means there is more on the shelf than the system knew.
  final int difference;

  /// Reason for the difference. Mandatory when the difference is non-zero, but
  /// only *at submit time* (G-O3) — see the note on constraints below.
  final String? note;
  const StockOpnameLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.opnameId,
    required this.itemId,
    this.batchId,
    required this.systemQty,
    required this.countedQty,
    required this.difference,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $StockOpnameLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['opname_id'] = Variable<String>(opnameId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['system_qty'] = Variable<int>(systemQty);
    map['counted_qty'] = Variable<int>(countedQty);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  StockOpnameLinesCompanion toCompanion(bool nullToAbsent) {
    return StockOpnameLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      opnameId: Value(opnameId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      systemQty: Value(systemQty),
      countedQty: Value(countedQty),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory StockOpnameLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockOpnameLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      opnameId: serializer.fromJson<String>(json['opnameId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      systemQty: serializer.fromJson<int>(json['systemQty']),
      countedQty: serializer.fromJson<int>(json['countedQty']),
      difference: serializer.fromJson<int>(json['difference']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'opnameId': serializer.toJson<String>(opnameId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'systemQty': serializer.toJson<int>(systemQty),
      'countedQty': serializer.toJson<int>(countedQty),
      'difference': serializer.toJson<int>(difference),
      'note': serializer.toJson<String?>(note),
    };
  }

  StockOpnameLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? opnameId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? systemQty,
    int? countedQty,
    int? difference,
    Value<String?> note = const Value.absent(),
  }) => StockOpnameLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    opnameId: opnameId ?? this.opnameId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    systemQty: systemQty ?? this.systemQty,
    countedQty: countedQty ?? this.countedQty,
    difference: difference ?? this.difference,
    note: note.present ? note.value : this.note,
  );
  @override
  String toString() {
    return (StringBuffer('StockOpnameLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('opnameId: $opnameId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('systemQty: $systemQty, ')
          ..write('countedQty: $countedQty, ')
          ..write('difference: $difference, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    opnameId,
    itemId,
    batchId,
    systemQty,
    countedQty,
    difference,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockOpnameLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.opnameId == this.opnameId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.systemQty == this.systemQty &&
          other.countedQty == this.countedQty &&
          other.difference == this.difference &&
          other.note == this.note);
}

class StockOpnameLinesCompanion extends UpdateCompanion<StockOpnameLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> opnameId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> systemQty;
  final Value<int> countedQty;
  final Value<String?> note;
  final Value<int> rowid;
  const StockOpnameLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.opnameId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.systemQty = const Value.absent(),
    this.countedQty = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockOpnameLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String opnameId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int systemQty,
    required int countedQty,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : opnameId = Value(opnameId),
       itemId = Value(itemId),
       systemQty = Value(systemQty),
       countedQty = Value(countedQty);
  static Insertable<StockOpnameLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? opnameId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? systemQty,
    Expression<int>? countedQty,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (opnameId != null) 'opname_id': opnameId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (systemQty != null) 'system_qty': systemQty,
      if (countedQty != null) 'counted_qty': countedQty,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockOpnameLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? opnameId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? systemQty,
    Value<int>? countedQty,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return StockOpnameLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      opnameId: opnameId ?? this.opnameId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      systemQty: systemQty ?? this.systemQty,
      countedQty: countedQty ?? this.countedQty,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $StockOpnameLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (opnameId.present) {
      map['opname_id'] = Variable<String>(opnameId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (systemQty.present) {
      map['system_qty'] = Variable<int>(systemQty.value);
    }
    if (countedQty.present) {
      map['counted_qty'] = Variable<int>(countedQty.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockOpnameLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('opnameId: $opnameId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('systemQty: $systemQty, ')
          ..write('countedQty: $countedQty, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseRequestsTable extends PurchaseRequests
    with TableInfo<$PurchaseRequestsTable, PurchaseRequestRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseRequestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($PurchaseRequestsTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _requestedByMeta = const VerificationMeta(
    'requestedBy',
  );
  @override
  late final GeneratedColumn<String> requestedBy = GeneratedColumn<String>(
    'requested_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PurchaseRequestStatus, String>
  status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => PurchaseRequestStatus.draft.dbValue,
      ).withConverter<PurchaseRequestStatus>(
        $PurchaseRequestsTable.$converterstatus,
      );
  static const VerificationMeta _neededDateMeta = const VerificationMeta(
    'neededDate',
  );
  @override
  late final GeneratedColumn<DateTime> neededDate = GeneratedColumn<DateTime>(
    'needed_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _submittedAtMeta = const VerificationMeta(
    'submittedAt',
  );
  @override
  late final GeneratedColumn<DateTime> submittedAt = GeneratedColumn<DateTime>(
    'submitted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processingAtMeta = const VerificationMeta(
    'processingAt',
  );
  @override
  late final GeneratedColumn<DateTime> processingAt = GeneratedColumn<DateTime>(
    'processing_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _processedByMeta = const VerificationMeta(
    'processedBy',
  );
  @override
  late final GeneratedColumn<String> processedBy = GeneratedColumn<String>(
    'processed_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _cancelledAtMeta = const VerificationMeta(
    'cancelledAt',
  );
  @override
  late final GeneratedColumn<DateTime> cancelledAt = GeneratedColumn<DateTime>(
    'cancelled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cancelledByMeta = const VerificationMeta(
    'cancelledBy',
  );
  @override
  late final GeneratedColumn<String> cancelledBy = GeneratedColumn<String>(
    'cancelled_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _cancelReasonMeta = const VerificationMeta(
    'cancelReason',
  );
  @override
  late final GeneratedColumn<String> cancelReason = GeneratedColumn<String>(
    'cancel_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectedAtMeta = const VerificationMeta(
    'rejectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> rejectedAt = GeneratedColumn<DateTime>(
    'rejected_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectedByMeta = const VerificationMeta(
    'rejectedBy',
  );
  @override
  late final GeneratedColumn<String> rejectedBy = GeneratedColumn<String>(
    'rejected_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _rejectReasonMeta = const VerificationMeta(
    'rejectReason',
  );
  @override
  late final GeneratedColumn<String> rejectReason = GeneratedColumn<String>(
    'reject_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    requestedBy,
    status,
    neededDate,
    note,
    submittedAt,
    processingAt,
    processedBy,
    cancelledAt,
    cancelledBy,
    cancelReason,
    rejectedAt,
    rejectedBy,
    rejectReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchase_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurchaseRequestRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('requested_by')) {
      context.handle(
        _requestedByMeta,
        requestedBy.isAcceptableOrUnknown(
          data['requested_by']!,
          _requestedByMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestedByMeta);
    }
    if (data.containsKey('needed_date')) {
      context.handle(
        _neededDateMeta,
        neededDate.isAcceptableOrUnknown(data['needed_date']!, _neededDateMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('submitted_at')) {
      context.handle(
        _submittedAtMeta,
        submittedAt.isAcceptableOrUnknown(
          data['submitted_at']!,
          _submittedAtMeta,
        ),
      );
    }
    if (data.containsKey('processing_at')) {
      context.handle(
        _processingAtMeta,
        processingAt.isAcceptableOrUnknown(
          data['processing_at']!,
          _processingAtMeta,
        ),
      );
    }
    if (data.containsKey('processed_by')) {
      context.handle(
        _processedByMeta,
        processedBy.isAcceptableOrUnknown(
          data['processed_by']!,
          _processedByMeta,
        ),
      );
    }
    if (data.containsKey('cancelled_at')) {
      context.handle(
        _cancelledAtMeta,
        cancelledAt.isAcceptableOrUnknown(
          data['cancelled_at']!,
          _cancelledAtMeta,
        ),
      );
    }
    if (data.containsKey('cancelled_by')) {
      context.handle(
        _cancelledByMeta,
        cancelledBy.isAcceptableOrUnknown(
          data['cancelled_by']!,
          _cancelledByMeta,
        ),
      );
    }
    if (data.containsKey('cancel_reason')) {
      context.handle(
        _cancelReasonMeta,
        cancelReason.isAcceptableOrUnknown(
          data['cancel_reason']!,
          _cancelReasonMeta,
        ),
      );
    }
    if (data.containsKey('rejected_at')) {
      context.handle(
        _rejectedAtMeta,
        rejectedAt.isAcceptableOrUnknown(data['rejected_at']!, _rejectedAtMeta),
      );
    }
    if (data.containsKey('rejected_by')) {
      context.handle(
        _rejectedByMeta,
        rejectedBy.isAcceptableOrUnknown(data['rejected_by']!, _rejectedByMeta),
      );
    }
    if (data.containsKey('reject_reason')) {
      context.handle(
        _rejectReasonMeta,
        rejectReason.isAcceptableOrUnknown(
          data['reject_reason']!,
          _rejectReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurchaseRequestRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseRequestRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $PurchaseRequestsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      requestedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}requested_by'],
      )!,
      status: $PurchaseRequestsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      neededDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}needed_date'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      submittedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}submitted_at'],
      ),
      processingAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}processing_at'],
      ),
      processedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processed_by'],
      ),
      cancelledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cancelled_at'],
      ),
      cancelledBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cancelled_by'],
      ),
      cancelReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cancel_reason'],
      ),
      rejectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}rejected_at'],
      ),
      rejectedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejected_by'],
      ),
      rejectReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reject_reason'],
      ),
    );
  }

  @override
  $PurchaseRequestsTable createAlias(String alias) {
    return $PurchaseRequestsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<PurchaseRequestStatus, String> $converterstatus =
      const PurchaseRequestStatusConverter();
}

class PurchaseRequestRow extends DataClass
    implements Insertable<PurchaseRequestRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-PR-{uuid}` until a sync backend assigns the
  /// final `PR-{cabang}-{yyyyMMdd}-{seq}` on submit (G-Y4). Minting a
  /// server-shaped number offline would collide across devices.
  final String docNumber;
  final String branchId;

  /// The Kepala Cabang who raised the request.
  final String requestedBy;
  final PurchaseRequestStatus status;

  /// Target arrival date — a **civil date** (T-8), stored as UTC midnight and
  /// never timezone converted.
  final DateTime? neededDate;
  final String? note;
  final DateTime? submittedAt;
  final DateTime? processingAt;

  /// The warehouse officer who took the order on.
  final String? processedBy;
  final DateTime? cancelledAt;

  /// The Kepala Cabang who withdrew the request — normally, and legitimately,
  /// the same person as [requestedBy].
  final String? cancelledBy;

  /// Why the request was withdrawn. Mandatory for a cancelled document: the
  /// detail screen shows it (§24.4) and an audit trail that records only
  /// "cancelled" explains nothing.
  final String? cancelReason;
  final DateTime? rejectedAt;
  final String? rejectedBy;

  /// Mandatory when rejected (spec §3.2: "rejected (oleh warehouse, wajib
  /// alasan)").
  final String? rejectReason;
  const PurchaseRequestRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.branchId,
    required this.requestedBy,
    required this.status,
    this.neededDate,
    this.note,
    this.submittedAt,
    this.processingAt,
    this.processedBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.rejectedAt,
    this.rejectedBy,
    this.rejectReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $PurchaseRequestsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['branch_id'] = Variable<String>(branchId);
    map['requested_by'] = Variable<String>(requestedBy);
    {
      map['status'] = Variable<String>(
        $PurchaseRequestsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || neededDate != null) {
      map['needed_date'] = Variable<DateTime>(neededDate);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || submittedAt != null) {
      map['submitted_at'] = Variable<DateTime>(submittedAt);
    }
    if (!nullToAbsent || processingAt != null) {
      map['processing_at'] = Variable<DateTime>(processingAt);
    }
    if (!nullToAbsent || processedBy != null) {
      map['processed_by'] = Variable<String>(processedBy);
    }
    if (!nullToAbsent || cancelledAt != null) {
      map['cancelled_at'] = Variable<DateTime>(cancelledAt);
    }
    if (!nullToAbsent || cancelledBy != null) {
      map['cancelled_by'] = Variable<String>(cancelledBy);
    }
    if (!nullToAbsent || cancelReason != null) {
      map['cancel_reason'] = Variable<String>(cancelReason);
    }
    if (!nullToAbsent || rejectedAt != null) {
      map['rejected_at'] = Variable<DateTime>(rejectedAt);
    }
    if (!nullToAbsent || rejectedBy != null) {
      map['rejected_by'] = Variable<String>(rejectedBy);
    }
    if (!nullToAbsent || rejectReason != null) {
      map['reject_reason'] = Variable<String>(rejectReason);
    }
    return map;
  }

  PurchaseRequestsCompanion toCompanion(bool nullToAbsent) {
    return PurchaseRequestsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      branchId: Value(branchId),
      requestedBy: Value(requestedBy),
      status: Value(status),
      neededDate: neededDate == null && nullToAbsent
          ? const Value.absent()
          : Value(neededDate),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      submittedAt: submittedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedAt),
      processingAt: processingAt == null && nullToAbsent
          ? const Value.absent()
          : Value(processingAt),
      processedBy: processedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(processedBy),
      cancelledAt: cancelledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledAt),
      cancelledBy: cancelledBy == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledBy),
      cancelReason: cancelReason == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelReason),
      rejectedAt: rejectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectedAt),
      rejectedBy: rejectedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectedBy),
      rejectReason: rejectReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectReason),
    );
  }

  factory PurchaseRequestRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseRequestRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      branchId: serializer.fromJson<String>(json['branchId']),
      requestedBy: serializer.fromJson<String>(json['requestedBy']),
      status: serializer.fromJson<PurchaseRequestStatus>(json['status']),
      neededDate: serializer.fromJson<DateTime?>(json['neededDate']),
      note: serializer.fromJson<String?>(json['note']),
      submittedAt: serializer.fromJson<DateTime?>(json['submittedAt']),
      processingAt: serializer.fromJson<DateTime?>(json['processingAt']),
      processedBy: serializer.fromJson<String?>(json['processedBy']),
      cancelledAt: serializer.fromJson<DateTime?>(json['cancelledAt']),
      cancelledBy: serializer.fromJson<String?>(json['cancelledBy']),
      cancelReason: serializer.fromJson<String?>(json['cancelReason']),
      rejectedAt: serializer.fromJson<DateTime?>(json['rejectedAt']),
      rejectedBy: serializer.fromJson<String?>(json['rejectedBy']),
      rejectReason: serializer.fromJson<String?>(json['rejectReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'branchId': serializer.toJson<String>(branchId),
      'requestedBy': serializer.toJson<String>(requestedBy),
      'status': serializer.toJson<PurchaseRequestStatus>(status),
      'neededDate': serializer.toJson<DateTime?>(neededDate),
      'note': serializer.toJson<String?>(note),
      'submittedAt': serializer.toJson<DateTime?>(submittedAt),
      'processingAt': serializer.toJson<DateTime?>(processingAt),
      'processedBy': serializer.toJson<String?>(processedBy),
      'cancelledAt': serializer.toJson<DateTime?>(cancelledAt),
      'cancelledBy': serializer.toJson<String?>(cancelledBy),
      'cancelReason': serializer.toJson<String?>(cancelReason),
      'rejectedAt': serializer.toJson<DateTime?>(rejectedAt),
      'rejectedBy': serializer.toJson<String?>(rejectedBy),
      'rejectReason': serializer.toJson<String?>(rejectReason),
    };
  }

  PurchaseRequestRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? branchId,
    String? requestedBy,
    PurchaseRequestStatus? status,
    Value<DateTime?> neededDate = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<DateTime?> submittedAt = const Value.absent(),
    Value<DateTime?> processingAt = const Value.absent(),
    Value<String?> processedBy = const Value.absent(),
    Value<DateTime?> cancelledAt = const Value.absent(),
    Value<String?> cancelledBy = const Value.absent(),
    Value<String?> cancelReason = const Value.absent(),
    Value<DateTime?> rejectedAt = const Value.absent(),
    Value<String?> rejectedBy = const Value.absent(),
    Value<String?> rejectReason = const Value.absent(),
  }) => PurchaseRequestRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    branchId: branchId ?? this.branchId,
    requestedBy: requestedBy ?? this.requestedBy,
    status: status ?? this.status,
    neededDate: neededDate.present ? neededDate.value : this.neededDate,
    note: note.present ? note.value : this.note,
    submittedAt: submittedAt.present ? submittedAt.value : this.submittedAt,
    processingAt: processingAt.present ? processingAt.value : this.processingAt,
    processedBy: processedBy.present ? processedBy.value : this.processedBy,
    cancelledAt: cancelledAt.present ? cancelledAt.value : this.cancelledAt,
    cancelledBy: cancelledBy.present ? cancelledBy.value : this.cancelledBy,
    cancelReason: cancelReason.present ? cancelReason.value : this.cancelReason,
    rejectedAt: rejectedAt.present ? rejectedAt.value : this.rejectedAt,
    rejectedBy: rejectedBy.present ? rejectedBy.value : this.rejectedBy,
    rejectReason: rejectReason.present ? rejectReason.value : this.rejectReason,
  );
  PurchaseRequestRow copyWithCompanion(PurchaseRequestsCompanion data) {
    return PurchaseRequestRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      requestedBy: data.requestedBy.present
          ? data.requestedBy.value
          : this.requestedBy,
      status: data.status.present ? data.status.value : this.status,
      neededDate: data.neededDate.present
          ? data.neededDate.value
          : this.neededDate,
      note: data.note.present ? data.note.value : this.note,
      submittedAt: data.submittedAt.present
          ? data.submittedAt.value
          : this.submittedAt,
      processingAt: data.processingAt.present
          ? data.processingAt.value
          : this.processingAt,
      processedBy: data.processedBy.present
          ? data.processedBy.value
          : this.processedBy,
      cancelledAt: data.cancelledAt.present
          ? data.cancelledAt.value
          : this.cancelledAt,
      cancelledBy: data.cancelledBy.present
          ? data.cancelledBy.value
          : this.cancelledBy,
      cancelReason: data.cancelReason.present
          ? data.cancelReason.value
          : this.cancelReason,
      rejectedAt: data.rejectedAt.present
          ? data.rejectedAt.value
          : this.rejectedAt,
      rejectedBy: data.rejectedBy.present
          ? data.rejectedBy.value
          : this.rejectedBy,
      rejectReason: data.rejectReason.present
          ? data.rejectReason.value
          : this.rejectReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseRequestRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('requestedBy: $requestedBy, ')
          ..write('status: $status, ')
          ..write('neededDate: $neededDate, ')
          ..write('note: $note, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('processingAt: $processingAt, ')
          ..write('processedBy: $processedBy, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('cancelledBy: $cancelledBy, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('rejectedAt: $rejectedAt, ')
          ..write('rejectedBy: $rejectedBy, ')
          ..write('rejectReason: $rejectReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    requestedBy,
    status,
    neededDate,
    note,
    submittedAt,
    processingAt,
    processedBy,
    cancelledAt,
    cancelledBy,
    cancelReason,
    rejectedAt,
    rejectedBy,
    rejectReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequestRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.branchId == this.branchId &&
          other.requestedBy == this.requestedBy &&
          other.status == this.status &&
          other.neededDate == this.neededDate &&
          other.note == this.note &&
          other.submittedAt == this.submittedAt &&
          other.processingAt == this.processingAt &&
          other.processedBy == this.processedBy &&
          other.cancelledAt == this.cancelledAt &&
          other.cancelledBy == this.cancelledBy &&
          other.cancelReason == this.cancelReason &&
          other.rejectedAt == this.rejectedAt &&
          other.rejectedBy == this.rejectedBy &&
          other.rejectReason == this.rejectReason);
}

class PurchaseRequestsCompanion extends UpdateCompanion<PurchaseRequestRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> branchId;
  final Value<String> requestedBy;
  final Value<PurchaseRequestStatus> status;
  final Value<DateTime?> neededDate;
  final Value<String?> note;
  final Value<DateTime?> submittedAt;
  final Value<DateTime?> processingAt;
  final Value<String?> processedBy;
  final Value<DateTime?> cancelledAt;
  final Value<String?> cancelledBy;
  final Value<String?> cancelReason;
  final Value<DateTime?> rejectedAt;
  final Value<String?> rejectedBy;
  final Value<String?> rejectReason;
  final Value<int> rowid;
  const PurchaseRequestsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.branchId = const Value.absent(),
    this.requestedBy = const Value.absent(),
    this.status = const Value.absent(),
    this.neededDate = const Value.absent(),
    this.note = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.processingAt = const Value.absent(),
    this.processedBy = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.cancelledBy = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.rejectedAt = const Value.absent(),
    this.rejectedBy = const Value.absent(),
    this.rejectReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseRequestsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String branchId,
    required String requestedBy,
    this.status = const Value.absent(),
    this.neededDate = const Value.absent(),
    this.note = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.processingAt = const Value.absent(),
    this.processedBy = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.cancelledBy = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.rejectedAt = const Value.absent(),
    this.rejectedBy = const Value.absent(),
    this.rejectReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       branchId = Value(branchId),
       requestedBy = Value(requestedBy);
  static Insertable<PurchaseRequestRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? branchId,
    Expression<String>? requestedBy,
    Expression<String>? status,
    Expression<DateTime>? neededDate,
    Expression<String>? note,
    Expression<DateTime>? submittedAt,
    Expression<DateTime>? processingAt,
    Expression<String>? processedBy,
    Expression<DateTime>? cancelledAt,
    Expression<String>? cancelledBy,
    Expression<String>? cancelReason,
    Expression<DateTime>? rejectedAt,
    Expression<String>? rejectedBy,
    Expression<String>? rejectReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (branchId != null) 'branch_id': branchId,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (status != null) 'status': status,
      if (neededDate != null) 'needed_date': neededDate,
      if (note != null) 'note': note,
      if (submittedAt != null) 'submitted_at': submittedAt,
      if (processingAt != null) 'processing_at': processingAt,
      if (processedBy != null) 'processed_by': processedBy,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
      if (cancelledBy != null) 'cancelled_by': cancelledBy,
      if (cancelReason != null) 'cancel_reason': cancelReason,
      if (rejectedAt != null) 'rejected_at': rejectedAt,
      if (rejectedBy != null) 'rejected_by': rejectedBy,
      if (rejectReason != null) 'reject_reason': rejectReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseRequestsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? branchId,
    Value<String>? requestedBy,
    Value<PurchaseRequestStatus>? status,
    Value<DateTime?>? neededDate,
    Value<String?>? note,
    Value<DateTime?>? submittedAt,
    Value<DateTime?>? processingAt,
    Value<String?>? processedBy,
    Value<DateTime?>? cancelledAt,
    Value<String?>? cancelledBy,
    Value<String?>? cancelReason,
    Value<DateTime?>? rejectedAt,
    Value<String?>? rejectedBy,
    Value<String?>? rejectReason,
    Value<int>? rowid,
  }) {
    return PurchaseRequestsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      branchId: branchId ?? this.branchId,
      requestedBy: requestedBy ?? this.requestedBy,
      status: status ?? this.status,
      neededDate: neededDate ?? this.neededDate,
      note: note ?? this.note,
      submittedAt: submittedAt ?? this.submittedAt,
      processingAt: processingAt ?? this.processingAt,
      processedBy: processedBy ?? this.processedBy,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelReason: cancelReason ?? this.cancelReason,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectReason: rejectReason ?? this.rejectReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $PurchaseRequestsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (requestedBy.present) {
      map['requested_by'] = Variable<String>(requestedBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $PurchaseRequestsTable.$converterstatus.toSql(status.value),
      );
    }
    if (neededDate.present) {
      map['needed_date'] = Variable<DateTime>(neededDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (submittedAt.present) {
      map['submitted_at'] = Variable<DateTime>(submittedAt.value);
    }
    if (processingAt.present) {
      map['processing_at'] = Variable<DateTime>(processingAt.value);
    }
    if (processedBy.present) {
      map['processed_by'] = Variable<String>(processedBy.value);
    }
    if (cancelledAt.present) {
      map['cancelled_at'] = Variable<DateTime>(cancelledAt.value);
    }
    if (cancelledBy.present) {
      map['cancelled_by'] = Variable<String>(cancelledBy.value);
    }
    if (cancelReason.present) {
      map['cancel_reason'] = Variable<String>(cancelReason.value);
    }
    if (rejectedAt.present) {
      map['rejected_at'] = Variable<DateTime>(rejectedAt.value);
    }
    if (rejectedBy.present) {
      map['rejected_by'] = Variable<String>(rejectedBy.value);
    }
    if (rejectReason.present) {
      map['reject_reason'] = Variable<String>(rejectReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseRequestsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('requestedBy: $requestedBy, ')
          ..write('status: $status, ')
          ..write('neededDate: $neededDate, ')
          ..write('note: $note, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('processingAt: $processingAt, ')
          ..write('processedBy: $processedBy, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('cancelledBy: $cancelledBy, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('rejectedAt: $rejectedAt, ')
          ..write('rejectedBy: $rejectedBy, ')
          ..write('rejectReason: $rejectReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseRequestOpnamesTable extends PurchaseRequestOpnames
    with TableInfo<$PurchaseRequestOpnamesTable, PurchaseRequestOpnameRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseRequestOpnamesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>(
        $PurchaseRequestOpnamesTable.$convertersyncStatus,
      );
  static const VerificationMeta _prIdMeta = const VerificationMeta('prId');
  @override
  late final GeneratedColumn<String> prId = GeneratedColumn<String>(
    'pr_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES purchase_requests (id)',
    ),
  );
  static const VerificationMeta _opnameIdMeta = const VerificationMeta(
    'opnameId',
  );
  @override
  late final GeneratedColumn<String> opnameId = GeneratedColumn<String>(
    'opname_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_opnames (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    prId,
    opnameId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchase_request_opnames';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurchaseRequestOpnameRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('pr_id')) {
      context.handle(
        _prIdMeta,
        prId.isAcceptableOrUnknown(data['pr_id']!, _prIdMeta),
      );
    } else if (isInserting) {
      context.missing(_prIdMeta);
    }
    if (data.containsKey('opname_id')) {
      context.handle(
        _opnameIdMeta,
        opnameId.isAcceptableOrUnknown(data['opname_id']!, _opnameIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opnameIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurchaseRequestOpnameRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseRequestOpnameRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $PurchaseRequestOpnamesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      prId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pr_id'],
      )!,
      opnameId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opname_id'],
      )!,
    );
  }

  @override
  $PurchaseRequestOpnamesTable createAlias(String alias) {
    return $PurchaseRequestOpnamesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class PurchaseRequestOpnameRow extends DataClass
    implements Insertable<PurchaseRequestOpnameRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String prId;
  final String opnameId;
  const PurchaseRequestOpnameRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.prId,
    required this.opnameId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $PurchaseRequestOpnamesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['pr_id'] = Variable<String>(prId);
    map['opname_id'] = Variable<String>(opnameId);
    return map;
  }

  PurchaseRequestOpnamesCompanion toCompanion(bool nullToAbsent) {
    return PurchaseRequestOpnamesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      prId: Value(prId),
      opnameId: Value(opnameId),
    );
  }

  factory PurchaseRequestOpnameRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseRequestOpnameRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      prId: serializer.fromJson<String>(json['prId']),
      opnameId: serializer.fromJson<String>(json['opnameId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'prId': serializer.toJson<String>(prId),
      'opnameId': serializer.toJson<String>(opnameId),
    };
  }

  PurchaseRequestOpnameRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? prId,
    String? opnameId,
  }) => PurchaseRequestOpnameRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    prId: prId ?? this.prId,
    opnameId: opnameId ?? this.opnameId,
  );
  PurchaseRequestOpnameRow copyWithCompanion(
    PurchaseRequestOpnamesCompanion data,
  ) {
    return PurchaseRequestOpnameRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      prId: data.prId.present ? data.prId.value : this.prId,
      opnameId: data.opnameId.present ? data.opnameId.value : this.opnameId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseRequestOpnameRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('prId: $prId, ')
          ..write('opnameId: $opnameId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    prId,
    opnameId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequestOpnameRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.prId == this.prId &&
          other.opnameId == this.opnameId);
}

class PurchaseRequestOpnamesCompanion
    extends UpdateCompanion<PurchaseRequestOpnameRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> prId;
  final Value<String> opnameId;
  final Value<int> rowid;
  const PurchaseRequestOpnamesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.prId = const Value.absent(),
    this.opnameId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseRequestOpnamesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String prId,
    required String opnameId,
    this.rowid = const Value.absent(),
  }) : prId = Value(prId),
       opnameId = Value(opnameId);
  static Insertable<PurchaseRequestOpnameRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? prId,
    Expression<String>? opnameId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (prId != null) 'pr_id': prId,
      if (opnameId != null) 'opname_id': opnameId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseRequestOpnamesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? prId,
    Value<String>? opnameId,
    Value<int>? rowid,
  }) {
    return PurchaseRequestOpnamesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      prId: prId ?? this.prId,
      opnameId: opnameId ?? this.opnameId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $PurchaseRequestOpnamesTable.$convertersyncStatus.toSql(
          syncStatus.value,
        ),
      );
    }
    if (prId.present) {
      map['pr_id'] = Variable<String>(prId.value);
    }
    if (opnameId.present) {
      map['opname_id'] = Variable<String>(opnameId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseRequestOpnamesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('prId: $prId, ')
          ..write('opnameId: $opnameId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PurchaseRequestLinesTable extends PurchaseRequestLines
    with TableInfo<$PurchaseRequestLinesTable, PurchaseRequestLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PurchaseRequestLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>(
        $PurchaseRequestLinesTable.$convertersyncStatus,
      );
  static const VerificationMeta _prIdMeta = const VerificationMeta('prId');
  @override
  late final GeneratedColumn<String> prId = GeneratedColumn<String>(
    'pr_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES purchase_requests (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _suggestedQtyMeta = const VerificationMeta(
    'suggestedQty',
  );
  @override
  late final GeneratedColumn<int> suggestedQty = GeneratedColumn<int>(
    'suggested_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestedQtyMeta = const VerificationMeta(
    'requestedQty',
  );
  @override
  late final GeneratedColumn<int> requestedQty = GeneratedColumn<int>(
    'requested_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    prId,
    itemId,
    suggestedQty,
    requestedQty,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'purchase_request_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<PurchaseRequestLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('pr_id')) {
      context.handle(
        _prIdMeta,
        prId.isAcceptableOrUnknown(data['pr_id']!, _prIdMeta),
      );
    } else if (isInserting) {
      context.missing(_prIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('suggested_qty')) {
      context.handle(
        _suggestedQtyMeta,
        suggestedQty.isAcceptableOrUnknown(
          data['suggested_qty']!,
          _suggestedQtyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_suggestedQtyMeta);
    }
    if (data.containsKey('requested_qty')) {
      context.handle(
        _requestedQtyMeta,
        requestedQty.isAcceptableOrUnknown(
          data['requested_qty']!,
          _requestedQtyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestedQtyMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PurchaseRequestLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PurchaseRequestLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $PurchaseRequestLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      prId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pr_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      suggestedQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}suggested_qty'],
      )!,
      requestedQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}requested_qty'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $PurchaseRequestLinesTable createAlias(String alias) {
    return $PurchaseRequestLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class PurchaseRequestLineRow extends DataClass
    implements Insertable<PurchaseRequestLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String prId;
  final String itemId;

  /// `max(0, min_stock_room − counted_qty)` aggregated over the linked opnames'
  /// rooms. Zero for a line the branch head added by hand.
  final int suggestedQty;

  /// What the branch head actually asks for. Strictly positive (G-P2).
  final int requestedQty;

  /// Justification. Mandatory when the request exceeds 150 % of the suggestion,
  /// or when there is no suggestion at all to exceed (G-P3) — enforced over the
  /// whole document at submit time rather than by a CHECK, because a draft must
  /// be saveable while the reason is still being typed.
  final String? note;
  const PurchaseRequestLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.prId,
    required this.itemId,
    required this.suggestedQty,
    required this.requestedQty,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $PurchaseRequestLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['pr_id'] = Variable<String>(prId);
    map['item_id'] = Variable<String>(itemId);
    map['suggested_qty'] = Variable<int>(suggestedQty);
    map['requested_qty'] = Variable<int>(requestedQty);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  PurchaseRequestLinesCompanion toCompanion(bool nullToAbsent) {
    return PurchaseRequestLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      prId: Value(prId),
      itemId: Value(itemId),
      suggestedQty: Value(suggestedQty),
      requestedQty: Value(requestedQty),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory PurchaseRequestLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PurchaseRequestLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      prId: serializer.fromJson<String>(json['prId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      suggestedQty: serializer.fromJson<int>(json['suggestedQty']),
      requestedQty: serializer.fromJson<int>(json['requestedQty']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'prId': serializer.toJson<String>(prId),
      'itemId': serializer.toJson<String>(itemId),
      'suggestedQty': serializer.toJson<int>(suggestedQty),
      'requestedQty': serializer.toJson<int>(requestedQty),
      'note': serializer.toJson<String?>(note),
    };
  }

  PurchaseRequestLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? prId,
    String? itemId,
    int? suggestedQty,
    int? requestedQty,
    Value<String?> note = const Value.absent(),
  }) => PurchaseRequestLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    prId: prId ?? this.prId,
    itemId: itemId ?? this.itemId,
    suggestedQty: suggestedQty ?? this.suggestedQty,
    requestedQty: requestedQty ?? this.requestedQty,
    note: note.present ? note.value : this.note,
  );
  PurchaseRequestLineRow copyWithCompanion(PurchaseRequestLinesCompanion data) {
    return PurchaseRequestLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      prId: data.prId.present ? data.prId.value : this.prId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      suggestedQty: data.suggestedQty.present
          ? data.suggestedQty.value
          : this.suggestedQty,
      requestedQty: data.requestedQty.present
          ? data.requestedQty.value
          : this.requestedQty,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseRequestLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('prId: $prId, ')
          ..write('itemId: $itemId, ')
          ..write('suggestedQty: $suggestedQty, ')
          ..write('requestedQty: $requestedQty, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    prId,
    itemId,
    suggestedQty,
    requestedQty,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PurchaseRequestLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.prId == this.prId &&
          other.itemId == this.itemId &&
          other.suggestedQty == this.suggestedQty &&
          other.requestedQty == this.requestedQty &&
          other.note == this.note);
}

class PurchaseRequestLinesCompanion
    extends UpdateCompanion<PurchaseRequestLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> prId;
  final Value<String> itemId;
  final Value<int> suggestedQty;
  final Value<int> requestedQty;
  final Value<String?> note;
  final Value<int> rowid;
  const PurchaseRequestLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.prId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.suggestedQty = const Value.absent(),
    this.requestedQty = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PurchaseRequestLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String prId,
    required String itemId,
    required int suggestedQty,
    required int requestedQty,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : prId = Value(prId),
       itemId = Value(itemId),
       suggestedQty = Value(suggestedQty),
       requestedQty = Value(requestedQty);
  static Insertable<PurchaseRequestLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? prId,
    Expression<String>? itemId,
    Expression<int>? suggestedQty,
    Expression<int>? requestedQty,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (prId != null) 'pr_id': prId,
      if (itemId != null) 'item_id': itemId,
      if (suggestedQty != null) 'suggested_qty': suggestedQty,
      if (requestedQty != null) 'requested_qty': requestedQty,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PurchaseRequestLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? prId,
    Value<String>? itemId,
    Value<int>? suggestedQty,
    Value<int>? requestedQty,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return PurchaseRequestLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      prId: prId ?? this.prId,
      itemId: itemId ?? this.itemId,
      suggestedQty: suggestedQty ?? this.suggestedQty,
      requestedQty: requestedQty ?? this.requestedQty,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $PurchaseRequestLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (prId.present) {
      map['pr_id'] = Variable<String>(prId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (suggestedQty.present) {
      map['suggested_qty'] = Variable<int>(suggestedQty.value);
    }
    if (requestedQty.present) {
      map['requested_qty'] = Variable<int>(requestedQty.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PurchaseRequestLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('prId: $prId, ')
          ..write('itemId: $itemId, ')
          ..write('suggestedQty: $suggestedQty, ')
          ..write('requestedQty: $requestedQty, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeliveryOrdersTable extends DeliveryOrders
    with TableInfo<$DeliveryOrdersTable, DeliveryOrderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeliveryOrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($DeliveryOrdersTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _prIdMeta = const VerificationMeta('prId');
  @override
  late final GeneratedColumn<String> prId = GeneratedColumn<String>(
    'pr_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES purchase_requests (id)',
    ),
  );
  static const VerificationMeta _preparedByMeta = const VerificationMeta(
    'preparedBy',
  );
  @override
  late final GeneratedColumn<String> preparedBy = GeneratedColumn<String>(
    'prepared_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DeliveryOrderStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => DeliveryOrderStatus.preparing.dbValue,
  ).withConverter<DeliveryOrderStatus>($DeliveryOrdersTable.$converterstatus);
  static const VerificationMeta _shippedAtMeta = const VerificationMeta(
    'shippedAt',
  );
  @override
  late final GeneratedColumn<DateTime> shippedAt = GeneratedColumn<DateTime>(
    'shipped_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shippedByMeta = const VerificationMeta(
    'shippedBy',
  );
  @override
  late final GeneratedColumn<String> shippedBy = GeneratedColumn<String>(
    'shipped_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    prId,
    preparedBy,
    status,
    shippedAt,
    shippedBy,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'delivery_orders';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeliveryOrderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('pr_id')) {
      context.handle(
        _prIdMeta,
        prId.isAcceptableOrUnknown(data['pr_id']!, _prIdMeta),
      );
    } else if (isInserting) {
      context.missing(_prIdMeta);
    }
    if (data.containsKey('prepared_by')) {
      context.handle(
        _preparedByMeta,
        preparedBy.isAcceptableOrUnknown(data['prepared_by']!, _preparedByMeta),
      );
    } else if (isInserting) {
      context.missing(_preparedByMeta);
    }
    if (data.containsKey('shipped_at')) {
      context.handle(
        _shippedAtMeta,
        shippedAt.isAcceptableOrUnknown(data['shipped_at']!, _shippedAtMeta),
      );
    }
    if (data.containsKey('shipped_by')) {
      context.handle(
        _shippedByMeta,
        shippedBy.isAcceptableOrUnknown(data['shipped_by']!, _shippedByMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeliveryOrderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeliveryOrderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $DeliveryOrdersTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      prId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pr_id'],
      )!,
      preparedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prepared_by'],
      )!,
      status: $DeliveryOrdersTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      shippedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}shipped_at'],
      ),
      shippedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shipped_by'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $DeliveryOrdersTable createAlias(String alias) {
    return $DeliveryOrdersTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<DeliveryOrderStatus, String> $converterstatus =
      const DeliveryOrderStatusConverter();
}

class DeliveryOrderRow extends DataClass
    implements Insertable<DeliveryOrderRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-DO-{uuid}` until a sync backend assigns the
  /// final `DO-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
  /// would collide across devices — and a warehouse ships from several of them.
  final String docNumber;
  final String prId;

  /// The warehouse officer who assembled the shipment.
  final String preparedBy;
  final DeliveryOrderStatus status;

  /// UTC instant the goods left the warehouse (T-1).
  final DateTime? shippedAt;

  /// The warehouse officer who posted the shipment.
  final String? shippedBy;

  /// Free text printed on the Surat Jalan — courier, vehicle, handover notes.
  final String? note;
  const DeliveryOrderRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.prId,
    required this.preparedBy,
    required this.status,
    this.shippedAt,
    this.shippedBy,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $DeliveryOrdersTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['pr_id'] = Variable<String>(prId);
    map['prepared_by'] = Variable<String>(preparedBy);
    {
      map['status'] = Variable<String>(
        $DeliveryOrdersTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || shippedAt != null) {
      map['shipped_at'] = Variable<DateTime>(shippedAt);
    }
    if (!nullToAbsent || shippedBy != null) {
      map['shipped_by'] = Variable<String>(shippedBy);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  DeliveryOrdersCompanion toCompanion(bool nullToAbsent) {
    return DeliveryOrdersCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      prId: Value(prId),
      preparedBy: Value(preparedBy),
      status: Value(status),
      shippedAt: shippedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(shippedAt),
      shippedBy: shippedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(shippedBy),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory DeliveryOrderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeliveryOrderRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      prId: serializer.fromJson<String>(json['prId']),
      preparedBy: serializer.fromJson<String>(json['preparedBy']),
      status: serializer.fromJson<DeliveryOrderStatus>(json['status']),
      shippedAt: serializer.fromJson<DateTime?>(json['shippedAt']),
      shippedBy: serializer.fromJson<String?>(json['shippedBy']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'prId': serializer.toJson<String>(prId),
      'preparedBy': serializer.toJson<String>(preparedBy),
      'status': serializer.toJson<DeliveryOrderStatus>(status),
      'shippedAt': serializer.toJson<DateTime?>(shippedAt),
      'shippedBy': serializer.toJson<String?>(shippedBy),
      'note': serializer.toJson<String?>(note),
    };
  }

  DeliveryOrderRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? prId,
    String? preparedBy,
    DeliveryOrderStatus? status,
    Value<DateTime?> shippedAt = const Value.absent(),
    Value<String?> shippedBy = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => DeliveryOrderRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    prId: prId ?? this.prId,
    preparedBy: preparedBy ?? this.preparedBy,
    status: status ?? this.status,
    shippedAt: shippedAt.present ? shippedAt.value : this.shippedAt,
    shippedBy: shippedBy.present ? shippedBy.value : this.shippedBy,
    note: note.present ? note.value : this.note,
  );
  DeliveryOrderRow copyWithCompanion(DeliveryOrdersCompanion data) {
    return DeliveryOrderRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      prId: data.prId.present ? data.prId.value : this.prId,
      preparedBy: data.preparedBy.present
          ? data.preparedBy.value
          : this.preparedBy,
      status: data.status.present ? data.status.value : this.status,
      shippedAt: data.shippedAt.present ? data.shippedAt.value : this.shippedAt,
      shippedBy: data.shippedBy.present ? data.shippedBy.value : this.shippedBy,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeliveryOrderRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('prId: $prId, ')
          ..write('preparedBy: $preparedBy, ')
          ..write('status: $status, ')
          ..write('shippedAt: $shippedAt, ')
          ..write('shippedBy: $shippedBy, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    prId,
    preparedBy,
    status,
    shippedAt,
    shippedBy,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryOrderRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.prId == this.prId &&
          other.preparedBy == this.preparedBy &&
          other.status == this.status &&
          other.shippedAt == this.shippedAt &&
          other.shippedBy == this.shippedBy &&
          other.note == this.note);
}

class DeliveryOrdersCompanion extends UpdateCompanion<DeliveryOrderRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> prId;
  final Value<String> preparedBy;
  final Value<DeliveryOrderStatus> status;
  final Value<DateTime?> shippedAt;
  final Value<String?> shippedBy;
  final Value<String?> note;
  final Value<int> rowid;
  const DeliveryOrdersCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.prId = const Value.absent(),
    this.preparedBy = const Value.absent(),
    this.status = const Value.absent(),
    this.shippedAt = const Value.absent(),
    this.shippedBy = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeliveryOrdersCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String prId,
    required String preparedBy,
    this.status = const Value.absent(),
    this.shippedAt = const Value.absent(),
    this.shippedBy = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       prId = Value(prId),
       preparedBy = Value(preparedBy);
  static Insertable<DeliveryOrderRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? prId,
    Expression<String>? preparedBy,
    Expression<String>? status,
    Expression<DateTime>? shippedAt,
    Expression<String>? shippedBy,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (prId != null) 'pr_id': prId,
      if (preparedBy != null) 'prepared_by': preparedBy,
      if (status != null) 'status': status,
      if (shippedAt != null) 'shipped_at': shippedAt,
      if (shippedBy != null) 'shipped_by': shippedBy,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeliveryOrdersCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? prId,
    Value<String>? preparedBy,
    Value<DeliveryOrderStatus>? status,
    Value<DateTime?>? shippedAt,
    Value<String?>? shippedBy,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return DeliveryOrdersCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      prId: prId ?? this.prId,
      preparedBy: preparedBy ?? this.preparedBy,
      status: status ?? this.status,
      shippedAt: shippedAt ?? this.shippedAt,
      shippedBy: shippedBy ?? this.shippedBy,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $DeliveryOrdersTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (prId.present) {
      map['pr_id'] = Variable<String>(prId.value);
    }
    if (preparedBy.present) {
      map['prepared_by'] = Variable<String>(preparedBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $DeliveryOrdersTable.$converterstatus.toSql(status.value),
      );
    }
    if (shippedAt.present) {
      map['shipped_at'] = Variable<DateTime>(shippedAt.value);
    }
    if (shippedBy.present) {
      map['shipped_by'] = Variable<String>(shippedBy.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeliveryOrdersCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('prId: $prId, ')
          ..write('preparedBy: $preparedBy, ')
          ..write('status: $status, ')
          ..write('shippedAt: $shippedAt, ')
          ..write('shippedBy: $shippedBy, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeliveryOrderLinesTable extends DeliveryOrderLines
    with TableInfo<$DeliveryOrderLinesTable, DeliveryOrderLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeliveryOrderLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>(
        $DeliveryOrderLinesTable.$convertersyncStatus,
      );
  static const VerificationMeta _doIdMeta = const VerificationMeta('doId');
  @override
  late final GeneratedColumn<String> doId = GeneratedColumn<String>(
    'do_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES delivery_orders (id)',
    ),
  );
  static const VerificationMeta _prLineIdMeta = const VerificationMeta(
    'prLineId',
  );
  @override
  late final GeneratedColumn<String> prLineId = GeneratedColumn<String>(
    'pr_line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES purchase_request_lines (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _shippedQtyMeta = const VerificationMeta(
    'shippedQty',
  );
  @override
  late final GeneratedColumn<int> shippedQty = GeneratedColumn<int>(
    'shipped_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fefoOverrideReasonMeta =
      const VerificationMeta('fefoOverrideReason');
  @override
  late final GeneratedColumn<String> fefoOverrideReason =
      GeneratedColumn<String>(
        'fefo_override_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _nearExpiryConfirmedMeta =
      const VerificationMeta('nearExpiryConfirmed');
  @override
  late final GeneratedColumn<bool> nearExpiryConfirmed = GeneratedColumn<bool>(
    'near_expiry_confirmed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("near_expiry_confirmed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nearExpiryNoteMeta = const VerificationMeta(
    'nearExpiryNote',
  );
  @override
  late final GeneratedColumn<String> nearExpiryNote = GeneratedColumn<String>(
    'near_expiry_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    doId,
    prLineId,
    itemId,
    batchId,
    shippedQty,
    fefoOverrideReason,
    nearExpiryConfirmed,
    nearExpiryNote,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'delivery_order_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeliveryOrderLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('do_id')) {
      context.handle(
        _doIdMeta,
        doId.isAcceptableOrUnknown(data['do_id']!, _doIdMeta),
      );
    } else if (isInserting) {
      context.missing(_doIdMeta);
    }
    if (data.containsKey('pr_line_id')) {
      context.handle(
        _prLineIdMeta,
        prLineId.isAcceptableOrUnknown(data['pr_line_id']!, _prLineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_prLineIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('shipped_qty')) {
      context.handle(
        _shippedQtyMeta,
        shippedQty.isAcceptableOrUnknown(data['shipped_qty']!, _shippedQtyMeta),
      );
    } else if (isInserting) {
      context.missing(_shippedQtyMeta);
    }
    if (data.containsKey('fefo_override_reason')) {
      context.handle(
        _fefoOverrideReasonMeta,
        fefoOverrideReason.isAcceptableOrUnknown(
          data['fefo_override_reason']!,
          _fefoOverrideReasonMeta,
        ),
      );
    }
    if (data.containsKey('near_expiry_confirmed')) {
      context.handle(
        _nearExpiryConfirmedMeta,
        nearExpiryConfirmed.isAcceptableOrUnknown(
          data['near_expiry_confirmed']!,
          _nearExpiryConfirmedMeta,
        ),
      );
    }
    if (data.containsKey('near_expiry_note')) {
      context.handle(
        _nearExpiryNoteMeta,
        nearExpiryNote.isAcceptableOrUnknown(
          data['near_expiry_note']!,
          _nearExpiryNoteMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeliveryOrderLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeliveryOrderLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $DeliveryOrderLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      doId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}do_id'],
      )!,
      prLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pr_line_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      shippedQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}shipped_qty'],
      )!,
      fefoOverrideReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fefo_override_reason'],
      ),
      nearExpiryConfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}near_expiry_confirmed'],
      )!,
      nearExpiryNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}near_expiry_note'],
      ),
    );
  }

  @override
  $DeliveryOrderLinesTable createAlias(String alias) {
    return $DeliveryOrderLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class DeliveryOrderLineRow extends DataClass
    implements Insertable<DeliveryOrderLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String doId;

  /// The requested position this allocation satisfies. Mandatory (spec §2.3:
  /// *"Wajib merujuk baris PR"*).
  final String prLineId;
  final String itemId;

  /// The batch the warehouse picked — FEFO by default (G-E3). NULL, and only
  /// NULL, for an item without expiry (G-E2); the use case enforces both
  /// directions because the rule depends on `items.has_expiry`.
  final String? batchId;

  /// Quantity in **milli-units**, matching `stock_balances.qty_on_hand` (Q-3).
  /// Strictly positive: a zero allocation is not a shipment, it is an absent
  /// line.
  final int shippedQty;

  /// Why the officer picked a batch that is not the FEFO suggestion (G-E3).
  ///
  /// Mandatory *when the selection violates FEFO*, which is a cross-table
  /// question — it depends on the expiry dates and the current warehouse
  /// balances of every other batch of the item — and is therefore enforced by
  /// `ShipDeliveryOrderUseCase` and re-checked at ship time rather than by a
  /// CHECK. What the constraint below can state is that a stored reason is never
  /// blank.
  final String? fefoOverrideReason;

  /// Explicit acknowledgement that the batch has less than `expiry_alert_days`
  /// of shelf life left (G-E4). Never defaulted to true anywhere.
  final bool nearExpiryConfirmed;

  /// Optional context for the confirmation, printed on the Surat Jalan.
  final String? nearExpiryNote;
  const DeliveryOrderLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.doId,
    required this.prLineId,
    required this.itemId,
    this.batchId,
    required this.shippedQty,
    this.fefoOverrideReason,
    required this.nearExpiryConfirmed,
    this.nearExpiryNote,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $DeliveryOrderLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['do_id'] = Variable<String>(doId);
    map['pr_line_id'] = Variable<String>(prLineId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['shipped_qty'] = Variable<int>(shippedQty);
    if (!nullToAbsent || fefoOverrideReason != null) {
      map['fefo_override_reason'] = Variable<String>(fefoOverrideReason);
    }
    map['near_expiry_confirmed'] = Variable<bool>(nearExpiryConfirmed);
    if (!nullToAbsent || nearExpiryNote != null) {
      map['near_expiry_note'] = Variable<String>(nearExpiryNote);
    }
    return map;
  }

  DeliveryOrderLinesCompanion toCompanion(bool nullToAbsent) {
    return DeliveryOrderLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      doId: Value(doId),
      prLineId: Value(prLineId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      shippedQty: Value(shippedQty),
      fefoOverrideReason: fefoOverrideReason == null && nullToAbsent
          ? const Value.absent()
          : Value(fefoOverrideReason),
      nearExpiryConfirmed: Value(nearExpiryConfirmed),
      nearExpiryNote: nearExpiryNote == null && nullToAbsent
          ? const Value.absent()
          : Value(nearExpiryNote),
    );
  }

  factory DeliveryOrderLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeliveryOrderLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      doId: serializer.fromJson<String>(json['doId']),
      prLineId: serializer.fromJson<String>(json['prLineId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      shippedQty: serializer.fromJson<int>(json['shippedQty']),
      fefoOverrideReason: serializer.fromJson<String?>(
        json['fefoOverrideReason'],
      ),
      nearExpiryConfirmed: serializer.fromJson<bool>(
        json['nearExpiryConfirmed'],
      ),
      nearExpiryNote: serializer.fromJson<String?>(json['nearExpiryNote']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'doId': serializer.toJson<String>(doId),
      'prLineId': serializer.toJson<String>(prLineId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'shippedQty': serializer.toJson<int>(shippedQty),
      'fefoOverrideReason': serializer.toJson<String?>(fefoOverrideReason),
      'nearExpiryConfirmed': serializer.toJson<bool>(nearExpiryConfirmed),
      'nearExpiryNote': serializer.toJson<String?>(nearExpiryNote),
    };
  }

  DeliveryOrderLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? doId,
    String? prLineId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? shippedQty,
    Value<String?> fefoOverrideReason = const Value.absent(),
    bool? nearExpiryConfirmed,
    Value<String?> nearExpiryNote = const Value.absent(),
  }) => DeliveryOrderLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    doId: doId ?? this.doId,
    prLineId: prLineId ?? this.prLineId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    shippedQty: shippedQty ?? this.shippedQty,
    fefoOverrideReason: fefoOverrideReason.present
        ? fefoOverrideReason.value
        : this.fefoOverrideReason,
    nearExpiryConfirmed: nearExpiryConfirmed ?? this.nearExpiryConfirmed,
    nearExpiryNote: nearExpiryNote.present
        ? nearExpiryNote.value
        : this.nearExpiryNote,
  );
  DeliveryOrderLineRow copyWithCompanion(DeliveryOrderLinesCompanion data) {
    return DeliveryOrderLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      doId: data.doId.present ? data.doId.value : this.doId,
      prLineId: data.prLineId.present ? data.prLineId.value : this.prLineId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      shippedQty: data.shippedQty.present
          ? data.shippedQty.value
          : this.shippedQty,
      fefoOverrideReason: data.fefoOverrideReason.present
          ? data.fefoOverrideReason.value
          : this.fefoOverrideReason,
      nearExpiryConfirmed: data.nearExpiryConfirmed.present
          ? data.nearExpiryConfirmed.value
          : this.nearExpiryConfirmed,
      nearExpiryNote: data.nearExpiryNote.present
          ? data.nearExpiryNote.value
          : this.nearExpiryNote,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeliveryOrderLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('doId: $doId, ')
          ..write('prLineId: $prLineId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('shippedQty: $shippedQty, ')
          ..write('fefoOverrideReason: $fefoOverrideReason, ')
          ..write('nearExpiryConfirmed: $nearExpiryConfirmed, ')
          ..write('nearExpiryNote: $nearExpiryNote')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    doId,
    prLineId,
    itemId,
    batchId,
    shippedQty,
    fefoOverrideReason,
    nearExpiryConfirmed,
    nearExpiryNote,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryOrderLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.doId == this.doId &&
          other.prLineId == this.prLineId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.shippedQty == this.shippedQty &&
          other.fefoOverrideReason == this.fefoOverrideReason &&
          other.nearExpiryConfirmed == this.nearExpiryConfirmed &&
          other.nearExpiryNote == this.nearExpiryNote);
}

class DeliveryOrderLinesCompanion
    extends UpdateCompanion<DeliveryOrderLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> doId;
  final Value<String> prLineId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> shippedQty;
  final Value<String?> fefoOverrideReason;
  final Value<bool> nearExpiryConfirmed;
  final Value<String?> nearExpiryNote;
  final Value<int> rowid;
  const DeliveryOrderLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.doId = const Value.absent(),
    this.prLineId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.shippedQty = const Value.absent(),
    this.fefoOverrideReason = const Value.absent(),
    this.nearExpiryConfirmed = const Value.absent(),
    this.nearExpiryNote = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeliveryOrderLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String doId,
    required String prLineId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int shippedQty,
    this.fefoOverrideReason = const Value.absent(),
    this.nearExpiryConfirmed = const Value.absent(),
    this.nearExpiryNote = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : doId = Value(doId),
       prLineId = Value(prLineId),
       itemId = Value(itemId),
       shippedQty = Value(shippedQty);
  static Insertable<DeliveryOrderLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? doId,
    Expression<String>? prLineId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? shippedQty,
    Expression<String>? fefoOverrideReason,
    Expression<bool>? nearExpiryConfirmed,
    Expression<String>? nearExpiryNote,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (doId != null) 'do_id': doId,
      if (prLineId != null) 'pr_line_id': prLineId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (shippedQty != null) 'shipped_qty': shippedQty,
      if (fefoOverrideReason != null)
        'fefo_override_reason': fefoOverrideReason,
      if (nearExpiryConfirmed != null)
        'near_expiry_confirmed': nearExpiryConfirmed,
      if (nearExpiryNote != null) 'near_expiry_note': nearExpiryNote,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeliveryOrderLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? doId,
    Value<String>? prLineId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? shippedQty,
    Value<String?>? fefoOverrideReason,
    Value<bool>? nearExpiryConfirmed,
    Value<String?>? nearExpiryNote,
    Value<int>? rowid,
  }) {
    return DeliveryOrderLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      doId: doId ?? this.doId,
      prLineId: prLineId ?? this.prLineId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      shippedQty: shippedQty ?? this.shippedQty,
      fefoOverrideReason: fefoOverrideReason ?? this.fefoOverrideReason,
      nearExpiryConfirmed: nearExpiryConfirmed ?? this.nearExpiryConfirmed,
      nearExpiryNote: nearExpiryNote ?? this.nearExpiryNote,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $DeliveryOrderLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (doId.present) {
      map['do_id'] = Variable<String>(doId.value);
    }
    if (prLineId.present) {
      map['pr_line_id'] = Variable<String>(prLineId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (shippedQty.present) {
      map['shipped_qty'] = Variable<int>(shippedQty.value);
    }
    if (fefoOverrideReason.present) {
      map['fefo_override_reason'] = Variable<String>(fefoOverrideReason.value);
    }
    if (nearExpiryConfirmed.present) {
      map['near_expiry_confirmed'] = Variable<bool>(nearExpiryConfirmed.value);
    }
    if (nearExpiryNote.present) {
      map['near_expiry_note'] = Variable<String>(nearExpiryNote.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeliveryOrderLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('doId: $doId, ')
          ..write('prLineId: $prLineId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('shippedQty: $shippedQty, ')
          ..write('fefoOverrideReason: $fefoOverrideReason, ')
          ..write('nearExpiryConfirmed: $nearExpiryConfirmed, ')
          ..write('nearExpiryNote: $nearExpiryNote, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoodReceiptsTable extends GoodReceipts
    with TableInfo<$GoodReceiptsTable, GoodReceiptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoodReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($GoodReceiptsTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doIdMeta = const VerificationMeta('doId');
  @override
  late final GeneratedColumn<String> doId = GeneratedColumn<String>(
    'do_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES delivery_orders (id)',
    ),
  );
  static const VerificationMeta _receivedByMeta = const VerificationMeta(
    'receivedBy',
  );
  @override
  late final GeneratedColumn<String> receivedBy = GeneratedColumn<String>(
    'received_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<GoodReceiptStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => GoodReceiptStatus.checking.dbValue,
  ).withConverter<GoodReceiptStatus>($GoodReceiptsTable.$converterstatus);
  static const VerificationMeta _postedAtMeta = const VerificationMeta(
    'postedAt',
  );
  @override
  late final GeneratedColumn<DateTime> postedAt = GeneratedColumn<DateTime>(
    'posted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    doId,
    receivedBy,
    status,
    postedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'good_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoodReceiptRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('do_id')) {
      context.handle(
        _doIdMeta,
        doId.isAcceptableOrUnknown(data['do_id']!, _doIdMeta),
      );
    } else if (isInserting) {
      context.missing(_doIdMeta);
    }
    if (data.containsKey('received_by')) {
      context.handle(
        _receivedByMeta,
        receivedBy.isAcceptableOrUnknown(data['received_by']!, _receivedByMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedByMeta);
    }
    if (data.containsKey('posted_at')) {
      context.handle(
        _postedAtMeta,
        postedAt.isAcceptableOrUnknown(data['posted_at']!, _postedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GoodReceiptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoodReceiptRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $GoodReceiptsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      doId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}do_id'],
      )!,
      receivedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}received_by'],
      )!,
      status: $GoodReceiptsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      postedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}posted_at'],
      ),
    );
  }

  @override
  $GoodReceiptsTable createAlias(String alias) {
    return $GoodReceiptsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<GoodReceiptStatus, String> $converterstatus =
      const GoodReceiptStatusConverter();
}

class GoodReceiptRow extends DataClass implements Insertable<GoodReceiptRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-GR-{uuid}` until a sync backend assigns the
  /// final `GR-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number
  /// offline would collide across devices — and every branch receives on its
  /// own.
  final String docNumber;

  /// The shipment being checked in. Unique: see the class note.
  final String doId;

  /// The Kepala Cabang who checked the goods (G-G1). Their branch must be the
  /// shipment's destination, which is a cross-table question and therefore the
  /// use case's to enforce.
  final String receivedBy;
  final GoodReceiptStatus status;

  /// UTC instant the receipt was posted and the branch store credited (T-1).
  final DateTime? postedAt;
  const GoodReceiptRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.doId,
    required this.receivedBy,
    required this.status,
    this.postedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $GoodReceiptsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['do_id'] = Variable<String>(doId);
    map['received_by'] = Variable<String>(receivedBy);
    {
      map['status'] = Variable<String>(
        $GoodReceiptsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || postedAt != null) {
      map['posted_at'] = Variable<DateTime>(postedAt);
    }
    return map;
  }

  GoodReceiptsCompanion toCompanion(bool nullToAbsent) {
    return GoodReceiptsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      doId: Value(doId),
      receivedBy: Value(receivedBy),
      status: Value(status),
      postedAt: postedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(postedAt),
    );
  }

  factory GoodReceiptRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoodReceiptRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      doId: serializer.fromJson<String>(json['doId']),
      receivedBy: serializer.fromJson<String>(json['receivedBy']),
      status: serializer.fromJson<GoodReceiptStatus>(json['status']),
      postedAt: serializer.fromJson<DateTime?>(json['postedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'doId': serializer.toJson<String>(doId),
      'receivedBy': serializer.toJson<String>(receivedBy),
      'status': serializer.toJson<GoodReceiptStatus>(status),
      'postedAt': serializer.toJson<DateTime?>(postedAt),
    };
  }

  GoodReceiptRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? doId,
    String? receivedBy,
    GoodReceiptStatus? status,
    Value<DateTime?> postedAt = const Value.absent(),
  }) => GoodReceiptRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    doId: doId ?? this.doId,
    receivedBy: receivedBy ?? this.receivedBy,
    status: status ?? this.status,
    postedAt: postedAt.present ? postedAt.value : this.postedAt,
  );
  GoodReceiptRow copyWithCompanion(GoodReceiptsCompanion data) {
    return GoodReceiptRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      doId: data.doId.present ? data.doId.value : this.doId,
      receivedBy: data.receivedBy.present
          ? data.receivedBy.value
          : this.receivedBy,
      status: data.status.present ? data.status.value : this.status,
      postedAt: data.postedAt.present ? data.postedAt.value : this.postedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoodReceiptRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('doId: $doId, ')
          ..write('receivedBy: $receivedBy, ')
          ..write('status: $status, ')
          ..write('postedAt: $postedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    doId,
    receivedBy,
    status,
    postedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodReceiptRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.doId == this.doId &&
          other.receivedBy == this.receivedBy &&
          other.status == this.status &&
          other.postedAt == this.postedAt);
}

class GoodReceiptsCompanion extends UpdateCompanion<GoodReceiptRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> doId;
  final Value<String> receivedBy;
  final Value<GoodReceiptStatus> status;
  final Value<DateTime?> postedAt;
  final Value<int> rowid;
  const GoodReceiptsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.doId = const Value.absent(),
    this.receivedBy = const Value.absent(),
    this.status = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoodReceiptsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String doId,
    required String receivedBy,
    this.status = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       doId = Value(doId),
       receivedBy = Value(receivedBy);
  static Insertable<GoodReceiptRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? doId,
    Expression<String>? receivedBy,
    Expression<String>? status,
    Expression<DateTime>? postedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (doId != null) 'do_id': doId,
      if (receivedBy != null) 'received_by': receivedBy,
      if (status != null) 'status': status,
      if (postedAt != null) 'posted_at': postedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoodReceiptsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? doId,
    Value<String>? receivedBy,
    Value<GoodReceiptStatus>? status,
    Value<DateTime?>? postedAt,
    Value<int>? rowid,
  }) {
    return GoodReceiptsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      doId: doId ?? this.doId,
      receivedBy: receivedBy ?? this.receivedBy,
      status: status ?? this.status,
      postedAt: postedAt ?? this.postedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $GoodReceiptsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (doId.present) {
      map['do_id'] = Variable<String>(doId.value);
    }
    if (receivedBy.present) {
      map['received_by'] = Variable<String>(receivedBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $GoodReceiptsTable.$converterstatus.toSql(status.value),
      );
    }
    if (postedAt.present) {
      map['posted_at'] = Variable<DateTime>(postedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoodReceiptsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('doId: $doId, ')
          ..write('receivedBy: $receivedBy, ')
          ..write('status: $status, ')
          ..write('postedAt: $postedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoodReceiptLinesTable extends GoodReceiptLines
    with TableInfo<$GoodReceiptLinesTable, GoodReceiptLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoodReceiptLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($GoodReceiptLinesTable.$convertersyncStatus);
  static const VerificationMeta _grIdMeta = const VerificationMeta('grId');
  @override
  late final GeneratedColumn<String> grId = GeneratedColumn<String>(
    'gr_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES good_receipts (id)',
    ),
  );
  static const VerificationMeta _doLineIdMeta = const VerificationMeta(
    'doLineId',
  );
  @override
  late final GeneratedColumn<String> doLineId = GeneratedColumn<String>(
    'do_line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES delivery_order_lines (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _shippedQtyMeta = const VerificationMeta(
    'shippedQty',
  );
  @override
  late final GeneratedColumn<int> shippedQty = GeneratedColumn<int>(
    'shipped_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedQtyMeta = const VerificationMeta(
    'receivedQty',
  );
  @override
  late final GeneratedColumn<int> receivedQty = GeneratedColumn<int>(
    'received_qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<GoodReceiptLineStatus, String>
  lineStatus =
      GeneratedColumn<String>(
        'line_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => GoodReceiptLineStatus.pending.dbValue,
      ).withConverter<GoodReceiptLineStatus>(
        $GoodReceiptLinesTable.$converterlineStatus,
      );
  static const VerificationMeta _rejectReasonMeta = const VerificationMeta(
    'rejectReason',
  );
  @override
  late final GeneratedColumn<String> rejectReason = GeneratedColumn<String>(
    'reject_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    grId,
    doLineId,
    itemId,
    batchId,
    shippedQty,
    receivedQty,
    lineStatus,
    rejectReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'good_receipt_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoodReceiptLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('gr_id')) {
      context.handle(
        _grIdMeta,
        grId.isAcceptableOrUnknown(data['gr_id']!, _grIdMeta),
      );
    } else if (isInserting) {
      context.missing(_grIdMeta);
    }
    if (data.containsKey('do_line_id')) {
      context.handle(
        _doLineIdMeta,
        doLineId.isAcceptableOrUnknown(data['do_line_id']!, _doLineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_doLineIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('shipped_qty')) {
      context.handle(
        _shippedQtyMeta,
        shippedQty.isAcceptableOrUnknown(data['shipped_qty']!, _shippedQtyMeta),
      );
    } else if (isInserting) {
      context.missing(_shippedQtyMeta);
    }
    if (data.containsKey('received_qty')) {
      context.handle(
        _receivedQtyMeta,
        receivedQty.isAcceptableOrUnknown(
          data['received_qty']!,
          _receivedQtyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receivedQtyMeta);
    }
    if (data.containsKey('reject_reason')) {
      context.handle(
        _rejectReasonMeta,
        rejectReason.isAcceptableOrUnknown(
          data['reject_reason']!,
          _rejectReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GoodReceiptLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoodReceiptLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $GoodReceiptLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      grId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gr_id'],
      )!,
      doLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}do_line_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      shippedQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}shipped_qty'],
      )!,
      receivedQty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_qty'],
      )!,
      lineStatus: $GoodReceiptLinesTable.$converterlineStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}line_status'],
        )!,
      ),
      rejectReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reject_reason'],
      ),
    );
  }

  @override
  $GoodReceiptLinesTable createAlias(String alias) {
    return $GoodReceiptLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<GoodReceiptLineStatus, String> $converterlineStatus =
      const GoodReceiptLineStatusConverter();
}

class GoodReceiptLineRow extends DataClass
    implements Insertable<GoodReceiptLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String grId;

  /// The shipped allocation this decision answers.
  final String doLineId;
  final String itemId;

  /// The batch the warehouse shipped, verified by the branch head against the
  /// packaging (spec §2.3). NULL, and only NULL, for an item without expiry
  /// (G-E2); the use case enforces both directions because the rule depends on
  /// `items.has_expiry`.
  final String? batchId;

  /// Snapshot of the Delivery Order line's quantity, in **milli-units** (Q-3).
  /// Strictly positive, because a shipment never allocates zero.
  final int shippedQty;

  /// What the branch actually accepted, in **milli-units**. Bounded by
  /// `0 ≤ received_qty ≤ shipped_qty` (G-G3) in SQL as well as in the domain.
  final int receivedQty;
  final GoodReceiptLineStatus lineStatus;

  /// Why the position was refused (G-G4). Mandatory for `rejected`, forbidden
  /// otherwise — a reason on an accepted line would be an audit trail for a
  /// decision nobody made.
  final String? rejectReason;
  const GoodReceiptLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.grId,
    required this.doLineId,
    required this.itemId,
    this.batchId,
    required this.shippedQty,
    required this.receivedQty,
    required this.lineStatus,
    this.rejectReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $GoodReceiptLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['gr_id'] = Variable<String>(grId);
    map['do_line_id'] = Variable<String>(doLineId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['shipped_qty'] = Variable<int>(shippedQty);
    map['received_qty'] = Variable<int>(receivedQty);
    {
      map['line_status'] = Variable<String>(
        $GoodReceiptLinesTable.$converterlineStatus.toSql(lineStatus),
      );
    }
    if (!nullToAbsent || rejectReason != null) {
      map['reject_reason'] = Variable<String>(rejectReason);
    }
    return map;
  }

  GoodReceiptLinesCompanion toCompanion(bool nullToAbsent) {
    return GoodReceiptLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      grId: Value(grId),
      doLineId: Value(doLineId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      shippedQty: Value(shippedQty),
      receivedQty: Value(receivedQty),
      lineStatus: Value(lineStatus),
      rejectReason: rejectReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectReason),
    );
  }

  factory GoodReceiptLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoodReceiptLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      grId: serializer.fromJson<String>(json['grId']),
      doLineId: serializer.fromJson<String>(json['doLineId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      shippedQty: serializer.fromJson<int>(json['shippedQty']),
      receivedQty: serializer.fromJson<int>(json['receivedQty']),
      lineStatus: serializer.fromJson<GoodReceiptLineStatus>(
        json['lineStatus'],
      ),
      rejectReason: serializer.fromJson<String?>(json['rejectReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'grId': serializer.toJson<String>(grId),
      'doLineId': serializer.toJson<String>(doLineId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'shippedQty': serializer.toJson<int>(shippedQty),
      'receivedQty': serializer.toJson<int>(receivedQty),
      'lineStatus': serializer.toJson<GoodReceiptLineStatus>(lineStatus),
      'rejectReason': serializer.toJson<String?>(rejectReason),
    };
  }

  GoodReceiptLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? grId,
    String? doLineId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? shippedQty,
    int? receivedQty,
    GoodReceiptLineStatus? lineStatus,
    Value<String?> rejectReason = const Value.absent(),
  }) => GoodReceiptLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    grId: grId ?? this.grId,
    doLineId: doLineId ?? this.doLineId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    shippedQty: shippedQty ?? this.shippedQty,
    receivedQty: receivedQty ?? this.receivedQty,
    lineStatus: lineStatus ?? this.lineStatus,
    rejectReason: rejectReason.present ? rejectReason.value : this.rejectReason,
  );
  GoodReceiptLineRow copyWithCompanion(GoodReceiptLinesCompanion data) {
    return GoodReceiptLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      grId: data.grId.present ? data.grId.value : this.grId,
      doLineId: data.doLineId.present ? data.doLineId.value : this.doLineId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      shippedQty: data.shippedQty.present
          ? data.shippedQty.value
          : this.shippedQty,
      receivedQty: data.receivedQty.present
          ? data.receivedQty.value
          : this.receivedQty,
      lineStatus: data.lineStatus.present
          ? data.lineStatus.value
          : this.lineStatus,
      rejectReason: data.rejectReason.present
          ? data.rejectReason.value
          : this.rejectReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoodReceiptLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('grId: $grId, ')
          ..write('doLineId: $doLineId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('shippedQty: $shippedQty, ')
          ..write('receivedQty: $receivedQty, ')
          ..write('lineStatus: $lineStatus, ')
          ..write('rejectReason: $rejectReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    grId,
    doLineId,
    itemId,
    batchId,
    shippedQty,
    receivedQty,
    lineStatus,
    rejectReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodReceiptLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.grId == this.grId &&
          other.doLineId == this.doLineId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.shippedQty == this.shippedQty &&
          other.receivedQty == this.receivedQty &&
          other.lineStatus == this.lineStatus &&
          other.rejectReason == this.rejectReason);
}

class GoodReceiptLinesCompanion extends UpdateCompanion<GoodReceiptLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> grId;
  final Value<String> doLineId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> shippedQty;
  final Value<int> receivedQty;
  final Value<GoodReceiptLineStatus> lineStatus;
  final Value<String?> rejectReason;
  final Value<int> rowid;
  const GoodReceiptLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.grId = const Value.absent(),
    this.doLineId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.shippedQty = const Value.absent(),
    this.receivedQty = const Value.absent(),
    this.lineStatus = const Value.absent(),
    this.rejectReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoodReceiptLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String grId,
    required String doLineId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int shippedQty,
    required int receivedQty,
    this.lineStatus = const Value.absent(),
    this.rejectReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : grId = Value(grId),
       doLineId = Value(doLineId),
       itemId = Value(itemId),
       shippedQty = Value(shippedQty),
       receivedQty = Value(receivedQty);
  static Insertable<GoodReceiptLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? grId,
    Expression<String>? doLineId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? shippedQty,
    Expression<int>? receivedQty,
    Expression<String>? lineStatus,
    Expression<String>? rejectReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (grId != null) 'gr_id': grId,
      if (doLineId != null) 'do_line_id': doLineId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (shippedQty != null) 'shipped_qty': shippedQty,
      if (receivedQty != null) 'received_qty': receivedQty,
      if (lineStatus != null) 'line_status': lineStatus,
      if (rejectReason != null) 'reject_reason': rejectReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoodReceiptLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? grId,
    Value<String>? doLineId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? shippedQty,
    Value<int>? receivedQty,
    Value<GoodReceiptLineStatus>? lineStatus,
    Value<String?>? rejectReason,
    Value<int>? rowid,
  }) {
    return GoodReceiptLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      grId: grId ?? this.grId,
      doLineId: doLineId ?? this.doLineId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      shippedQty: shippedQty ?? this.shippedQty,
      receivedQty: receivedQty ?? this.receivedQty,
      lineStatus: lineStatus ?? this.lineStatus,
      rejectReason: rejectReason ?? this.rejectReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $GoodReceiptLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (grId.present) {
      map['gr_id'] = Variable<String>(grId.value);
    }
    if (doLineId.present) {
      map['do_line_id'] = Variable<String>(doLineId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (shippedQty.present) {
      map['shipped_qty'] = Variable<int>(shippedQty.value);
    }
    if (receivedQty.present) {
      map['received_qty'] = Variable<int>(receivedQty.value);
    }
    if (lineStatus.present) {
      map['line_status'] = Variable<String>(
        $GoodReceiptLinesTable.$converterlineStatus.toSql(lineStatus.value),
      );
    }
    if (rejectReason.present) {
      map['reject_reason'] = Variable<String>(rejectReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoodReceiptLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('grId: $grId, ')
          ..write('doLineId: $doLineId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('shippedQty: $shippedQty, ')
          ..write('receivedQty: $receivedQty, ')
          ..write('lineStatus: $lineStatus, ')
          ..write('rejectReason: $rejectReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DistributionsTable extends Distributions
    with TableInfo<$DistributionsTable, DistributionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DistributionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($DistributionsTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _distributedByMeta = const VerificationMeta(
    'distributedBy',
  );
  @override
  late final GeneratedColumn<String> distributedBy = GeneratedColumn<String>(
    'distributed_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DistributionStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => DistributionStatus.draft.dbValue,
  ).withConverter<DistributionStatus>($DistributionsTable.$converterstatus);
  static const VerificationMeta _postedAtMeta = const VerificationMeta(
    'postedAt',
  );
  @override
  late final GeneratedColumn<DateTime> postedAt = GeneratedColumn<DateTime>(
    'posted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    distributedBy,
    status,
    postedAt,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'distributions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DistributionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('distributed_by')) {
      context.handle(
        _distributedByMeta,
        distributedBy.isAcceptableOrUnknown(
          data['distributed_by']!,
          _distributedByMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distributedByMeta);
    }
    if (data.containsKey('posted_at')) {
      context.handle(
        _postedAtMeta,
        postedAt.isAcceptableOrUnknown(data['posted_at']!, _postedAtMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DistributionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DistributionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $DistributionsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      distributedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}distributed_by'],
      )!,
      status: $DistributionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      postedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}posted_at'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $DistributionsTable createAlias(String alias) {
    return $DistributionsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<DistributionStatus, String> $converterstatus =
      const DistributionStatusConverter();
}

class DistributionRow extends DataClass implements Insertable<DistributionRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-DIST-{uuid}` until a sync backend assigns the
  /// final `DIST-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number
  /// offline would collide across devices — every branch distributes on its own.
  final String docNumber;

  /// The branch whose *Gudang Cabang* the goods leave, and the only branch whose
  /// rooms may receive them (G-T1).
  final String branchId;

  /// The Kepala Cabang who distributed (spec §3.1). Their branch must be
  /// [branchId], which is a cross-table question and therefore the use case's to
  /// enforce.
  final String distributedBy;
  final DistributionStatus status;

  /// UTC instant the distribution was posted and the balances moved (T-1).
  final DateTime? postedAt;

  /// Free-text remark about the distribution as a whole, e.g. why an unusual
  /// quantity left the store. Optional, and never a substitute for the per-line
  /// `fefo_override_reason`, which is an audit record for a specific decision.
  final String? note;
  const DistributionRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.branchId,
    required this.distributedBy,
    required this.status,
    this.postedAt,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $DistributionsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['branch_id'] = Variable<String>(branchId);
    map['distributed_by'] = Variable<String>(distributedBy);
    {
      map['status'] = Variable<String>(
        $DistributionsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || postedAt != null) {
      map['posted_at'] = Variable<DateTime>(postedAt);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  DistributionsCompanion toCompanion(bool nullToAbsent) {
    return DistributionsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      branchId: Value(branchId),
      distributedBy: Value(distributedBy),
      status: Value(status),
      postedAt: postedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(postedAt),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory DistributionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DistributionRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      branchId: serializer.fromJson<String>(json['branchId']),
      distributedBy: serializer.fromJson<String>(json['distributedBy']),
      status: serializer.fromJson<DistributionStatus>(json['status']),
      postedAt: serializer.fromJson<DateTime?>(json['postedAt']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'branchId': serializer.toJson<String>(branchId),
      'distributedBy': serializer.toJson<String>(distributedBy),
      'status': serializer.toJson<DistributionStatus>(status),
      'postedAt': serializer.toJson<DateTime?>(postedAt),
      'note': serializer.toJson<String?>(note),
    };
  }

  DistributionRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? branchId,
    String? distributedBy,
    DistributionStatus? status,
    Value<DateTime?> postedAt = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => DistributionRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    branchId: branchId ?? this.branchId,
    distributedBy: distributedBy ?? this.distributedBy,
    status: status ?? this.status,
    postedAt: postedAt.present ? postedAt.value : this.postedAt,
    note: note.present ? note.value : this.note,
  );
  DistributionRow copyWithCompanion(DistributionsCompanion data) {
    return DistributionRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      distributedBy: data.distributedBy.present
          ? data.distributedBy.value
          : this.distributedBy,
      status: data.status.present ? data.status.value : this.status,
      postedAt: data.postedAt.present ? data.postedAt.value : this.postedAt,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DistributionRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('distributedBy: $distributedBy, ')
          ..write('status: $status, ')
          ..write('postedAt: $postedAt, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    distributedBy,
    status,
    postedAt,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistributionRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.branchId == this.branchId &&
          other.distributedBy == this.distributedBy &&
          other.status == this.status &&
          other.postedAt == this.postedAt &&
          other.note == this.note);
}

class DistributionsCompanion extends UpdateCompanion<DistributionRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> branchId;
  final Value<String> distributedBy;
  final Value<DistributionStatus> status;
  final Value<DateTime?> postedAt;
  final Value<String?> note;
  final Value<int> rowid;
  const DistributionsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.branchId = const Value.absent(),
    this.distributedBy = const Value.absent(),
    this.status = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DistributionsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String branchId,
    required String distributedBy,
    this.status = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       branchId = Value(branchId),
       distributedBy = Value(distributedBy);
  static Insertable<DistributionRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? branchId,
    Expression<String>? distributedBy,
    Expression<String>? status,
    Expression<DateTime>? postedAt,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (branchId != null) 'branch_id': branchId,
      if (distributedBy != null) 'distributed_by': distributedBy,
      if (status != null) 'status': status,
      if (postedAt != null) 'posted_at': postedAt,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DistributionsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? branchId,
    Value<String>? distributedBy,
    Value<DistributionStatus>? status,
    Value<DateTime?>? postedAt,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return DistributionsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      branchId: branchId ?? this.branchId,
      distributedBy: distributedBy ?? this.distributedBy,
      status: status ?? this.status,
      postedAt: postedAt ?? this.postedAt,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $DistributionsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (distributedBy.present) {
      map['distributed_by'] = Variable<String>(distributedBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $DistributionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (postedAt.present) {
      map['posted_at'] = Variable<DateTime>(postedAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DistributionsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('distributedBy: $distributedBy, ')
          ..write('status: $status, ')
          ..write('postedAt: $postedAt, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DistributionLinesTable extends DistributionLines
    with TableInfo<$DistributionLinesTable, DistributionLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DistributionLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($DistributionLinesTable.$convertersyncStatus);
  static const VerificationMeta _distributionIdMeta = const VerificationMeta(
    'distributionId',
  );
  @override
  late final GeneratedColumn<String> distributionId = GeneratedColumn<String>(
    'distribution_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES distributions (id)',
    ),
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES rooms (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fefoOverrideReasonMeta =
      const VerificationMeta('fefoOverrideReason');
  @override
  late final GeneratedColumn<String> fefoOverrideReason =
      GeneratedColumn<String>(
        'fefo_override_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    distributionId,
    roomId,
    itemId,
    batchId,
    qty,
    fefoOverrideReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'distribution_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<DistributionLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('distribution_id')) {
      context.handle(
        _distributionIdMeta,
        distributionId.isAcceptableOrUnknown(
          data['distribution_id']!,
          _distributionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_distributionIdMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('fefo_override_reason')) {
      context.handle(
        _fefoOverrideReasonMeta,
        fefoOverrideReason.isAcceptableOrUnknown(
          data['fefo_override_reason']!,
          _fefoOverrideReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DistributionLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DistributionLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $DistributionLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      distributionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}distribution_id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty'],
      )!,
      fefoOverrideReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fefo_override_reason'],
      ),
    );
  }

  @override
  $DistributionLinesTable createAlias(String alias) {
    return $DistributionLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class DistributionLineRow extends DataClass
    implements Insertable<DistributionLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String distributionId;

  /// The destination room. Must belong to the header's branch (G-T1) — a
  /// cross-table rule SQLite cannot express, enforced by the use cases and
  /// revalidated inside the posting transaction.
  final String roomId;
  final String itemId;

  /// The batch leaving the store. NULL, and only NULL, for an item without expiry
  /// (G-E2); the use case enforces both directions because the rule depends on
  /// `items.has_expiry`, which this table cannot read.
  final String? batchId;

  /// Distributed quantity in **milli-units** (Q-3). Strictly positive: a
  /// distribution of nothing is not a line, and the ledger records changes rather
  /// than confirmations (G-A1).
  final int qty;

  /// Why a batch younger than the FEFO suggestion was chosen (G-E3).
  ///
  /// NULL when the selection follows FEFO, which is the overwhelmingly common
  /// case. Whether a reason is *required* depends on the batches the store holds
  /// right now, which is not a fact this table can see — so the domain decides it
  /// (`DistributionFefoPolicy`) and re-decides it inside the posting transaction
  /// against fresh balances.
  final String? fefoOverrideReason;
  const DistributionLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.distributionId,
    required this.roomId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.fefoOverrideReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $DistributionLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['distribution_id'] = Variable<String>(distributionId);
    map['room_id'] = Variable<String>(roomId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['qty'] = Variable<int>(qty);
    if (!nullToAbsent || fefoOverrideReason != null) {
      map['fefo_override_reason'] = Variable<String>(fefoOverrideReason);
    }
    return map;
  }

  DistributionLinesCompanion toCompanion(bool nullToAbsent) {
    return DistributionLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      distributionId: Value(distributionId),
      roomId: Value(roomId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      qty: Value(qty),
      fefoOverrideReason: fefoOverrideReason == null && nullToAbsent
          ? const Value.absent()
          : Value(fefoOverrideReason),
    );
  }

  factory DistributionLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DistributionLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      distributionId: serializer.fromJson<String>(json['distributionId']),
      roomId: serializer.fromJson<String>(json['roomId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      qty: serializer.fromJson<int>(json['qty']),
      fefoOverrideReason: serializer.fromJson<String?>(
        json['fefoOverrideReason'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'distributionId': serializer.toJson<String>(distributionId),
      'roomId': serializer.toJson<String>(roomId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'qty': serializer.toJson<int>(qty),
      'fefoOverrideReason': serializer.toJson<String?>(fefoOverrideReason),
    };
  }

  DistributionLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? distributionId,
    String? roomId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? qty,
    Value<String?> fefoOverrideReason = const Value.absent(),
  }) => DistributionLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    distributionId: distributionId ?? this.distributionId,
    roomId: roomId ?? this.roomId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    qty: qty ?? this.qty,
    fefoOverrideReason: fefoOverrideReason.present
        ? fefoOverrideReason.value
        : this.fefoOverrideReason,
  );
  DistributionLineRow copyWithCompanion(DistributionLinesCompanion data) {
    return DistributionLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      distributionId: data.distributionId.present
          ? data.distributionId.value
          : this.distributionId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      qty: data.qty.present ? data.qty.value : this.qty,
      fefoOverrideReason: data.fefoOverrideReason.present
          ? data.fefoOverrideReason.value
          : this.fefoOverrideReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DistributionLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('distributionId: $distributionId, ')
          ..write('roomId: $roomId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('fefoOverrideReason: $fefoOverrideReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    distributionId,
    roomId,
    itemId,
    batchId,
    qty,
    fefoOverrideReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistributionLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.distributionId == this.distributionId &&
          other.roomId == this.roomId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.qty == this.qty &&
          other.fefoOverrideReason == this.fefoOverrideReason);
}

class DistributionLinesCompanion extends UpdateCompanion<DistributionLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> distributionId;
  final Value<String> roomId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> qty;
  final Value<String?> fefoOverrideReason;
  final Value<int> rowid;
  const DistributionLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.distributionId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.qty = const Value.absent(),
    this.fefoOverrideReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DistributionLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String distributionId,
    required String roomId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int qty,
    this.fefoOverrideReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : distributionId = Value(distributionId),
       roomId = Value(roomId),
       itemId = Value(itemId),
       qty = Value(qty);
  static Insertable<DistributionLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? distributionId,
    Expression<String>? roomId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? qty,
    Expression<String>? fefoOverrideReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (distributionId != null) 'distribution_id': distributionId,
      if (roomId != null) 'room_id': roomId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (qty != null) 'qty': qty,
      if (fefoOverrideReason != null)
        'fefo_override_reason': fefoOverrideReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DistributionLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? distributionId,
    Value<String>? roomId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? qty,
    Value<String?>? fefoOverrideReason,
    Value<int>? rowid,
  }) {
    return DistributionLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      distributionId: distributionId ?? this.distributionId,
      roomId: roomId ?? this.roomId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      qty: qty ?? this.qty,
      fefoOverrideReason: fefoOverrideReason ?? this.fefoOverrideReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $DistributionLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (distributionId.present) {
      map['distribution_id'] = Variable<String>(distributionId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (fefoOverrideReason.present) {
      map['fefo_override_reason'] = Variable<String>(fefoOverrideReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DistributionLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('distributionId: $distributionId, ')
          ..write('roomId: $roomId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('fefoOverrideReason: $fefoOverrideReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DisposalsTable extends Disposals
    with TableInfo<$DisposalsTable, DisposalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DisposalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($DisposalsTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceLocationIdMeta = const VerificationMeta(
    'sourceLocationId',
  );
  @override
  late final GeneratedColumn<String> sourceLocationId = GeneratedColumn<String>(
    'source_location_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_locations (id)',
    ),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DisposalStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => DisposalStatus.draft.dbValue,
      ).withConverter<DisposalStatus>($DisposalsTable.$converterstatus);
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postedAtMeta = const VerificationMeta(
    'postedAt',
  );
  @override
  late final GeneratedColumn<DateTime> postedAt = GeneratedColumn<DateTime>(
    'posted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postedByMeta = const VerificationMeta(
    'postedBy',
  );
  @override
  late final GeneratedColumn<String> postedBy = GeneratedColumn<String>(
    'posted_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    sourceLocationId,
    createdBy,
    status,
    reason,
    postedAt,
    postedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'disposals';
  @override
  VerificationContext validateIntegrity(
    Insertable<DisposalRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('source_location_id')) {
      context.handle(
        _sourceLocationIdMeta,
        sourceLocationId.isAcceptableOrUnknown(
          data['source_location_id']!,
          _sourceLocationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLocationIdMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('posted_at')) {
      context.handle(
        _postedAtMeta,
        postedAt.isAcceptableOrUnknown(data['posted_at']!, _postedAtMeta),
      );
    }
    if (data.containsKey('posted_by')) {
      context.handle(
        _postedByMeta,
        postedBy.isAcceptableOrUnknown(data['posted_by']!, _postedByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DisposalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DisposalRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $DisposalsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      sourceLocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_location_id'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      status: $DisposalsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      postedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}posted_at'],
      ),
      postedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}posted_by'],
      ),
    );
  }

  @override
  $DisposalsTable createAlias(String alias) {
    return $DisposalsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<DisposalStatus, String> $converterstatus =
      const DisposalStatusConverter();
}

class DisposalRow extends DataClass implements Insertable<DisposalRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-DSP-{uuid}` until a sync backend assigns the
  /// final `DSP-{lokasi}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number
  /// offline would collide across devices — every branch disposes on its own.
  final String docNumber;

  /// The one location the goods physically leave.
  ///
  /// Warehouse Pusat for a `warehouse` actor; the acting branch head's own
  /// *Gudang Cabang* or one of their rooms otherwise. Which of those an actor may
  /// name is a cross-table question (`users.branch_id` against
  /// `stock_locations.branch_id`) that SQLite cannot express as a foreign key, so
  /// `DisposalLocationPolicy` enforces it and the posting transaction
  /// revalidates it.
  final String sourceLocationId;

  /// Who raised the document (G-A3).
  final String createdBy;
  final DisposalStatus status;

  /// G-E7's mandatory note, at document level.
  ///
  /// Nullable while the document is a draft — the form opens before the reason is
  /// typed — and mandatory the moment it posts, which is what the status CHECK
  /// below states. The domain is stricter than the CHECK can be: `String.trim()`
  /// in Dart removes tabs and newlines, and SQLite's `trim()` removes spaces
  /// only, so a reason of `"\n\n"` passes the database and is refused by
  /// `DisposalReasonPolicy`. The CHECK is the floor, not the authority.
  final String? reason;

  /// UTC instant the disposal was posted and the balance fell (T-1).
  final DateTime? postedAt;

  /// Who posted it (G-E7's *pelaku*). Null exactly while the document is a draft.
  final String? postedBy;
  const DisposalRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.sourceLocationId,
    required this.createdBy,
    required this.status,
    this.reason,
    this.postedAt,
    this.postedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $DisposalsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['source_location_id'] = Variable<String>(sourceLocationId);
    map['created_by'] = Variable<String>(createdBy);
    {
      map['status'] = Variable<String>(
        $DisposalsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || postedAt != null) {
      map['posted_at'] = Variable<DateTime>(postedAt);
    }
    if (!nullToAbsent || postedBy != null) {
      map['posted_by'] = Variable<String>(postedBy);
    }
    return map;
  }

  DisposalsCompanion toCompanion(bool nullToAbsent) {
    return DisposalsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      sourceLocationId: Value(sourceLocationId),
      createdBy: Value(createdBy),
      status: Value(status),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      postedAt: postedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(postedAt),
      postedBy: postedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(postedBy),
    );
  }

  factory DisposalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DisposalRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      sourceLocationId: serializer.fromJson<String>(json['sourceLocationId']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      status: serializer.fromJson<DisposalStatus>(json['status']),
      reason: serializer.fromJson<String?>(json['reason']),
      postedAt: serializer.fromJson<DateTime?>(json['postedAt']),
      postedBy: serializer.fromJson<String?>(json['postedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'sourceLocationId': serializer.toJson<String>(sourceLocationId),
      'createdBy': serializer.toJson<String>(createdBy),
      'status': serializer.toJson<DisposalStatus>(status),
      'reason': serializer.toJson<String?>(reason),
      'postedAt': serializer.toJson<DateTime?>(postedAt),
      'postedBy': serializer.toJson<String?>(postedBy),
    };
  }

  DisposalRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? sourceLocationId,
    String? createdBy,
    DisposalStatus? status,
    Value<String?> reason = const Value.absent(),
    Value<DateTime?> postedAt = const Value.absent(),
    Value<String?> postedBy = const Value.absent(),
  }) => DisposalRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    sourceLocationId: sourceLocationId ?? this.sourceLocationId,
    createdBy: createdBy ?? this.createdBy,
    status: status ?? this.status,
    reason: reason.present ? reason.value : this.reason,
    postedAt: postedAt.present ? postedAt.value : this.postedAt,
    postedBy: postedBy.present ? postedBy.value : this.postedBy,
  );
  DisposalRow copyWithCompanion(DisposalsCompanion data) {
    return DisposalRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      sourceLocationId: data.sourceLocationId.present
          ? data.sourceLocationId.value
          : this.sourceLocationId,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      status: data.status.present ? data.status.value : this.status,
      reason: data.reason.present ? data.reason.value : this.reason,
      postedAt: data.postedAt.present ? data.postedAt.value : this.postedAt,
      postedBy: data.postedBy.present ? data.postedBy.value : this.postedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DisposalRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('sourceLocationId: $sourceLocationId, ')
          ..write('createdBy: $createdBy, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('postedAt: $postedAt, ')
          ..write('postedBy: $postedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    sourceLocationId,
    createdBy,
    status,
    reason,
    postedAt,
    postedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisposalRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.sourceLocationId == this.sourceLocationId &&
          other.createdBy == this.createdBy &&
          other.status == this.status &&
          other.reason == this.reason &&
          other.postedAt == this.postedAt &&
          other.postedBy == this.postedBy);
}

class DisposalsCompanion extends UpdateCompanion<DisposalRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> sourceLocationId;
  final Value<String> createdBy;
  final Value<DisposalStatus> status;
  final Value<String?> reason;
  final Value<DateTime?> postedAt;
  final Value<String?> postedBy;
  final Value<int> rowid;
  const DisposalsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.sourceLocationId = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.status = const Value.absent(),
    this.reason = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.postedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DisposalsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String sourceLocationId,
    required String createdBy,
    this.status = const Value.absent(),
    this.reason = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.postedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       sourceLocationId = Value(sourceLocationId),
       createdBy = Value(createdBy);
  static Insertable<DisposalRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? sourceLocationId,
    Expression<String>? createdBy,
    Expression<String>? status,
    Expression<String>? reason,
    Expression<DateTime>? postedAt,
    Expression<String>? postedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (sourceLocationId != null) 'source_location_id': sourceLocationId,
      if (createdBy != null) 'created_by': createdBy,
      if (status != null) 'status': status,
      if (reason != null) 'reason': reason,
      if (postedAt != null) 'posted_at': postedAt,
      if (postedBy != null) 'posted_by': postedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DisposalsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? sourceLocationId,
    Value<String>? createdBy,
    Value<DisposalStatus>? status,
    Value<String?>? reason,
    Value<DateTime?>? postedAt,
    Value<String?>? postedBy,
    Value<int>? rowid,
  }) {
    return DisposalsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      sourceLocationId: sourceLocationId ?? this.sourceLocationId,
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      postedAt: postedAt ?? this.postedAt,
      postedBy: postedBy ?? this.postedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $DisposalsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (sourceLocationId.present) {
      map['source_location_id'] = Variable<String>(sourceLocationId.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $DisposalsTable.$converterstatus.toSql(status.value),
      );
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (postedAt.present) {
      map['posted_at'] = Variable<DateTime>(postedAt.value);
    }
    if (postedBy.present) {
      map['posted_by'] = Variable<String>(postedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DisposalsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('sourceLocationId: $sourceLocationId, ')
          ..write('createdBy: $createdBy, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('postedAt: $postedAt, ')
          ..write('postedBy: $postedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DisposalLinesTable extends DisposalLines
    with TableInfo<$DisposalLinesTable, DisposalLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DisposalLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($DisposalLinesTable.$convertersyncStatus);
  static const VerificationMeta _disposalIdMeta = const VerificationMeta(
    'disposalId',
  );
  @override
  late final GeneratedColumn<String> disposalId = GeneratedColumn<String>(
    'disposal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES disposals (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    disposalId,
    itemId,
    batchId,
    qty,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'disposal_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<DisposalLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('disposal_id')) {
      context.handle(
        _disposalIdMeta,
        disposalId.isAcceptableOrUnknown(data['disposal_id']!, _disposalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_disposalIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DisposalLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DisposalLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $DisposalLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      disposalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}disposal_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $DisposalLinesTable createAlias(String alias) {
    return $DisposalLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class DisposalLineRow extends DataClass implements Insertable<DisposalLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String disposalId;
  final String itemId;

  /// The batch being destroyed. Never NULL — see the class note.
  final String batchId;

  /// Destroyed quantity in **milli-units** (Q-3). Strictly positive: a disposal
  /// of nothing is not a line, and the ledger records changes rather than
  /// confirmations (G-A1).
  final int qty;

  /// Optional per-line detail, e.g. *"kemasan bocor"*. Never a substitute for the
  /// header's `reason`, which G-E7 makes mandatory; this only adds specificity to
  /// one position.
  final String? note;
  const DisposalLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.disposalId,
    required this.itemId,
    required this.batchId,
    required this.qty,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $DisposalLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['disposal_id'] = Variable<String>(disposalId);
    map['item_id'] = Variable<String>(itemId);
    map['batch_id'] = Variable<String>(batchId);
    map['qty'] = Variable<int>(qty);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  DisposalLinesCompanion toCompanion(bool nullToAbsent) {
    return DisposalLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      disposalId: Value(disposalId),
      itemId: Value(itemId),
      batchId: Value(batchId),
      qty: Value(qty),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory DisposalLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DisposalLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      disposalId: serializer.fromJson<String>(json['disposalId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String>(json['batchId']),
      qty: serializer.fromJson<int>(json['qty']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'disposalId': serializer.toJson<String>(disposalId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String>(batchId),
      'qty': serializer.toJson<int>(qty),
      'note': serializer.toJson<String?>(note),
    };
  }

  DisposalLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? disposalId,
    String? itemId,
    String? batchId,
    int? qty,
    Value<String?> note = const Value.absent(),
  }) => DisposalLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    disposalId: disposalId ?? this.disposalId,
    itemId: itemId ?? this.itemId,
    batchId: batchId ?? this.batchId,
    qty: qty ?? this.qty,
    note: note.present ? note.value : this.note,
  );
  DisposalLineRow copyWithCompanion(DisposalLinesCompanion data) {
    return DisposalLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      disposalId: data.disposalId.present
          ? data.disposalId.value
          : this.disposalId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      qty: data.qty.present ? data.qty.value : this.qty,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DisposalLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('disposalId: $disposalId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    disposalId,
    itemId,
    batchId,
    qty,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisposalLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.disposalId == this.disposalId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.qty == this.qty &&
          other.note == this.note);
}

class DisposalLinesCompanion extends UpdateCompanion<DisposalLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> disposalId;
  final Value<String> itemId;
  final Value<String> batchId;
  final Value<int> qty;
  final Value<String?> note;
  final Value<int> rowid;
  const DisposalLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.disposalId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.qty = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DisposalLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String disposalId,
    required String itemId,
    required String batchId,
    required int qty,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : disposalId = Value(disposalId),
       itemId = Value(itemId),
       batchId = Value(batchId),
       qty = Value(qty);
  static Insertable<DisposalLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? disposalId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? qty,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (disposalId != null) 'disposal_id': disposalId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (qty != null) 'qty': qty,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DisposalLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? disposalId,
    Value<String>? itemId,
    Value<String>? batchId,
    Value<int>? qty,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return DisposalLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      disposalId: disposalId ?? this.disposalId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      qty: qty ?? this.qty,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $DisposalLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (disposalId.present) {
      map['disposal_id'] = Variable<String>(disposalId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DisposalLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('disposalId: $disposalId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConsumptionsTable extends Consumptions
    with TableInfo<$ConsumptionsTable, ConsumptionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConsumptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ConsumptionsTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES rooms (id)',
    ),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ConsumptionStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => ConsumptionStatus.draft.dbValue,
  ).withConverter<ConsumptionStatus>($ConsumptionsTable.$converterstatus);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postedAtMeta = const VerificationMeta(
    'postedAt',
  );
  @override
  late final GeneratedColumn<DateTime> postedAt = GeneratedColumn<DateTime>(
    'posted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postedByMeta = const VerificationMeta(
    'postedBy',
  );
  @override
  late final GeneratedColumn<String> postedBy = GeneratedColumn<String>(
    'posted_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    roomId,
    createdBy,
    status,
    note,
    postedAt,
    postedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'consumptions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConsumptionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('posted_at')) {
      context.handle(
        _postedAtMeta,
        postedAt.isAcceptableOrUnknown(data['posted_at']!, _postedAtMeta),
      );
    }
    if (data.containsKey('posted_by')) {
      context.handle(
        _postedByMeta,
        postedBy.isAcceptableOrUnknown(data['posted_by']!, _postedByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConsumptionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConsumptionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ConsumptionsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      status: $ConsumptionsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      postedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}posted_at'],
      ),
      postedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}posted_by'],
      ),
    );
  }

  @override
  $ConsumptionsTable createAlias(String alias) {
    return $ConsumptionsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<ConsumptionStatus, String> $converterstatus =
      const ConsumptionStatusConverter();
}

class ConsumptionRow extends DataClass implements Insertable<ConsumptionRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-CNS-{uuid}` until a sync backend assigns the final
  /// `CNS-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
  /// would collide across devices — every room records its own usage.
  final String docNumber;

  /// The branch whose room the goods leave. Must be the room's branch and the
  /// nurse's branch — cross-table equalities SQLite cannot express, so the use cases
  /// enforce them and the posting transaction revalidates them.
  final String branchId;

  /// The one room the goods are used in. Fixed at creation: there is no statement
  /// anywhere that updates this column.
  final String roomId;

  /// The Perawat who recorded the usage (G-A3).
  final String createdBy;
  final ConsumptionStatus status;

  /// Free-text remark about the usage as a whole, e.g. *"pemakaian shift pagi"*.
  ///
  /// **Optional**, unlike `disposals.reason`. G-E7 makes a note mandatory on a
  /// disposal because destruction has to be explained; nothing in the specification
  /// asks a nurse to justify ordinary consumption, and inventing that requirement
  /// would be inventing a rule. What the CHECK below does refuse is *whitespace*
  /// pretending to be a remark.
  ///
  /// Never a place for patient information — see the class note.
  final String? note;

  /// UTC instant the consumption was posted and the room balance fell (T-1).
  final DateTime? postedAt;

  /// Who posted it. Null exactly while the document is a draft.
  final String? postedBy;
  const ConsumptionRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.createdBy,
    required this.status,
    this.note,
    this.postedAt,
    this.postedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ConsumptionsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['branch_id'] = Variable<String>(branchId);
    map['room_id'] = Variable<String>(roomId);
    map['created_by'] = Variable<String>(createdBy);
    {
      map['status'] = Variable<String>(
        $ConsumptionsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || postedAt != null) {
      map['posted_at'] = Variable<DateTime>(postedAt);
    }
    if (!nullToAbsent || postedBy != null) {
      map['posted_by'] = Variable<String>(postedBy);
    }
    return map;
  }

  ConsumptionsCompanion toCompanion(bool nullToAbsent) {
    return ConsumptionsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      branchId: Value(branchId),
      roomId: Value(roomId),
      createdBy: Value(createdBy),
      status: Value(status),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      postedAt: postedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(postedAt),
      postedBy: postedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(postedBy),
    );
  }

  factory ConsumptionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConsumptionRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      branchId: serializer.fromJson<String>(json['branchId']),
      roomId: serializer.fromJson<String>(json['roomId']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      status: serializer.fromJson<ConsumptionStatus>(json['status']),
      note: serializer.fromJson<String?>(json['note']),
      postedAt: serializer.fromJson<DateTime?>(json['postedAt']),
      postedBy: serializer.fromJson<String?>(json['postedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'branchId': serializer.toJson<String>(branchId),
      'roomId': serializer.toJson<String>(roomId),
      'createdBy': serializer.toJson<String>(createdBy),
      'status': serializer.toJson<ConsumptionStatus>(status),
      'note': serializer.toJson<String?>(note),
      'postedAt': serializer.toJson<DateTime?>(postedAt),
      'postedBy': serializer.toJson<String?>(postedBy),
    };
  }

  ConsumptionRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? branchId,
    String? roomId,
    String? createdBy,
    ConsumptionStatus? status,
    Value<String?> note = const Value.absent(),
    Value<DateTime?> postedAt = const Value.absent(),
    Value<String?> postedBy = const Value.absent(),
  }) => ConsumptionRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    branchId: branchId ?? this.branchId,
    roomId: roomId ?? this.roomId,
    createdBy: createdBy ?? this.createdBy,
    status: status ?? this.status,
    note: note.present ? note.value : this.note,
    postedAt: postedAt.present ? postedAt.value : this.postedAt,
    postedBy: postedBy.present ? postedBy.value : this.postedBy,
  );
  ConsumptionRow copyWithCompanion(ConsumptionsCompanion data) {
    return ConsumptionRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      status: data.status.present ? data.status.value : this.status,
      note: data.note.present ? data.note.value : this.note,
      postedAt: data.postedAt.present ? data.postedAt.value : this.postedAt,
      postedBy: data.postedBy.present ? data.postedBy.value : this.postedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConsumptionRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('roomId: $roomId, ')
          ..write('createdBy: $createdBy, ')
          ..write('status: $status, ')
          ..write('note: $note, ')
          ..write('postedAt: $postedAt, ')
          ..write('postedBy: $postedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    branchId,
    roomId,
    createdBy,
    status,
    note,
    postedAt,
    postedBy,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsumptionRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.branchId == this.branchId &&
          other.roomId == this.roomId &&
          other.createdBy == this.createdBy &&
          other.status == this.status &&
          other.note == this.note &&
          other.postedAt == this.postedAt &&
          other.postedBy == this.postedBy);
}

class ConsumptionsCompanion extends UpdateCompanion<ConsumptionRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> branchId;
  final Value<String> roomId;
  final Value<String> createdBy;
  final Value<ConsumptionStatus> status;
  final Value<String?> note;
  final Value<DateTime?> postedAt;
  final Value<String?> postedBy;
  final Value<int> rowid;
  const ConsumptionsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.branchId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.status = const Value.absent(),
    this.note = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.postedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConsumptionsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String branchId,
    required String roomId,
    required String createdBy,
    this.status = const Value.absent(),
    this.note = const Value.absent(),
    this.postedAt = const Value.absent(),
    this.postedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       branchId = Value(branchId),
       roomId = Value(roomId),
       createdBy = Value(createdBy);
  static Insertable<ConsumptionRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? branchId,
    Expression<String>? roomId,
    Expression<String>? createdBy,
    Expression<String>? status,
    Expression<String>? note,
    Expression<DateTime>? postedAt,
    Expression<String>? postedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (branchId != null) 'branch_id': branchId,
      if (roomId != null) 'room_id': roomId,
      if (createdBy != null) 'created_by': createdBy,
      if (status != null) 'status': status,
      if (note != null) 'note': note,
      if (postedAt != null) 'posted_at': postedAt,
      if (postedBy != null) 'posted_by': postedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConsumptionsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? branchId,
    Value<String>? roomId,
    Value<String>? createdBy,
    Value<ConsumptionStatus>? status,
    Value<String?>? note,
    Value<DateTime?>? postedAt,
    Value<String?>? postedBy,
    Value<int>? rowid,
  }) {
    return ConsumptionsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      branchId: branchId ?? this.branchId,
      roomId: roomId ?? this.roomId,
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      note: note ?? this.note,
      postedAt: postedAt ?? this.postedAt,
      postedBy: postedBy ?? this.postedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ConsumptionsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ConsumptionsTable.$converterstatus.toSql(status.value),
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (postedAt.present) {
      map['posted_at'] = Variable<DateTime>(postedAt.value);
    }
    if (postedBy.present) {
      map['posted_by'] = Variable<String>(postedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConsumptionsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('branchId: $branchId, ')
          ..write('roomId: $roomId, ')
          ..write('createdBy: $createdBy, ')
          ..write('status: $status, ')
          ..write('note: $note, ')
          ..write('postedAt: $postedAt, ')
          ..write('postedBy: $postedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConsumptionLinesTable extends ConsumptionLines
    with TableInfo<$ConsumptionLinesTable, ConsumptionLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConsumptionLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ConsumptionLinesTable.$convertersyncStatus);
  static const VerificationMeta _consumptionIdMeta = const VerificationMeta(
    'consumptionId',
  );
  @override
  late final GeneratedColumn<String> consumptionId = GeneratedColumn<String>(
    'consumption_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES consumptions (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    consumptionId,
    itemId,
    batchId,
    qty,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'consumption_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConsumptionLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('consumption_id')) {
      context.handle(
        _consumptionIdMeta,
        consumptionId.isAcceptableOrUnknown(
          data['consumption_id']!,
          _consumptionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_consumptionIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConsumptionLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConsumptionLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ConsumptionLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      consumptionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consumption_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $ConsumptionLinesTable createAlias(String alias) {
    return $ConsumptionLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class ConsumptionLineRow extends DataClass
    implements Insertable<ConsumptionLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String consumptionId;
  final String itemId;

  /// The batch used. NULL, and only NULL, for an item without expiry (G-E2); the use
  /// case enforces both directions because the rule depends on `items.has_expiry`,
  /// which this table cannot read.
  final String? batchId;

  /// Consumed quantity in **milli-units** (Q-3). Strictly positive: a consumption of
  /// nothing is not a line, and the ledger records changes rather than confirmations
  /// (G-A1).
  final int qty;

  /// Optional per-line detail, e.g. *"1 ampul pecah saat dibuka"*. Adds specificity
  /// to one position; never patient information.
  final String? note;
  const ConsumptionLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.consumptionId,
    required this.itemId,
    this.batchId,
    required this.qty,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ConsumptionLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['consumption_id'] = Variable<String>(consumptionId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['qty'] = Variable<int>(qty);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  ConsumptionLinesCompanion toCompanion(bool nullToAbsent) {
    return ConsumptionLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      consumptionId: Value(consumptionId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      qty: Value(qty),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory ConsumptionLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConsumptionLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      consumptionId: serializer.fromJson<String>(json['consumptionId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      qty: serializer.fromJson<int>(json['qty']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'consumptionId': serializer.toJson<String>(consumptionId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'qty': serializer.toJson<int>(qty),
      'note': serializer.toJson<String?>(note),
    };
  }

  ConsumptionLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? consumptionId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? qty,
    Value<String?> note = const Value.absent(),
  }) => ConsumptionLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    consumptionId: consumptionId ?? this.consumptionId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    qty: qty ?? this.qty,
    note: note.present ? note.value : this.note,
  );
  ConsumptionLineRow copyWithCompanion(ConsumptionLinesCompanion data) {
    return ConsumptionLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      consumptionId: data.consumptionId.present
          ? data.consumptionId.value
          : this.consumptionId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      qty: data.qty.present ? data.qty.value : this.qty,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConsumptionLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('consumptionId: $consumptionId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    consumptionId,
    itemId,
    batchId,
    qty,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsumptionLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.consumptionId == this.consumptionId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.qty == this.qty &&
          other.note == this.note);
}

class ConsumptionLinesCompanion extends UpdateCompanion<ConsumptionLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> consumptionId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> qty;
  final Value<String?> note;
  final Value<int> rowid;
  const ConsumptionLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.consumptionId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.qty = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConsumptionLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String consumptionId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int qty,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : consumptionId = Value(consumptionId),
       itemId = Value(itemId),
       qty = Value(qty);
  static Insertable<ConsumptionLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? consumptionId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? qty,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (consumptionId != null) 'consumption_id': consumptionId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (qty != null) 'qty': qty,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConsumptionLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? consumptionId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? qty,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return ConsumptionLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      consumptionId: consumptionId ?? this.consumptionId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      qty: qty ?? this.qty,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ConsumptionLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (consumptionId.present) {
      map['consumption_id'] = Variable<String>(consumptionId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConsumptionLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('consumptionId: $consumptionId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoodsReturnsTable extends GoodsReturns
    with TableInfo<$GoodsReturnsTable, GoodsReturnRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoodsReturnsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($GoodsReturnsTable.$convertersyncStatus);
  static const VerificationMeta _docNumberMeta = const VerificationMeta(
    'docNumber',
  );
  @override
  late final GeneratedColumn<String> docNumber = GeneratedColumn<String>(
    'doc_number',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grIdMeta = const VerificationMeta('grId');
  @override
  late final GeneratedColumn<String> grId = GeneratedColumn<String>(
    'gr_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES good_receipts (id)',
    ),
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<GoodsReturnStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: () => GoodsReturnStatus.draft.dbValue,
  ).withConverter<GoodsReturnStatus>($GoodsReturnsTable.$converterstatus);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shippedAtMeta = const VerificationMeta(
    'shippedAt',
  );
  @override
  late final GeneratedColumn<DateTime> shippedAt = GeneratedColumn<DateTime>(
    'shipped_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shippedByMeta = const VerificationMeta(
    'shippedBy',
  );
  @override
  late final GeneratedColumn<String> shippedBy = GeneratedColumn<String>(
    'shipped_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedByMeta = const VerificationMeta(
    'receivedBy',
  );
  @override
  late final GeneratedColumn<String> receivedBy = GeneratedColumn<String>(
    'received_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _warehouseNoteMeta = const VerificationMeta(
    'warehouseNote',
  );
  @override
  late final GeneratedColumn<String> warehouseNote = GeneratedColumn<String>(
    'warehouse_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    grId,
    branchId,
    createdBy,
    status,
    note,
    shippedAt,
    shippedBy,
    receivedAt,
    receivedBy,
    warehouseNote,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goods_returns';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoodsReturnRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('doc_number')) {
      context.handle(
        _docNumberMeta,
        docNumber.isAcceptableOrUnknown(data['doc_number']!, _docNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_docNumberMeta);
    }
    if (data.containsKey('gr_id')) {
      context.handle(
        _grIdMeta,
        grId.isAcceptableOrUnknown(data['gr_id']!, _grIdMeta),
      );
    } else if (isInserting) {
      context.missing(_grIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('shipped_at')) {
      context.handle(
        _shippedAtMeta,
        shippedAt.isAcceptableOrUnknown(data['shipped_at']!, _shippedAtMeta),
      );
    }
    if (data.containsKey('shipped_by')) {
      context.handle(
        _shippedByMeta,
        shippedBy.isAcceptableOrUnknown(data['shipped_by']!, _shippedByMeta),
      );
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    }
    if (data.containsKey('received_by')) {
      context.handle(
        _receivedByMeta,
        receivedBy.isAcceptableOrUnknown(data['received_by']!, _receivedByMeta),
      );
    }
    if (data.containsKey('warehouse_note')) {
      context.handle(
        _warehouseNoteMeta,
        warehouseNote.isAcceptableOrUnknown(
          data['warehouse_note']!,
          _warehouseNoteMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GoodsReturnRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoodsReturnRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $GoodsReturnsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      docNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_number'],
      )!,
      grId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gr_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      status: $GoodsReturnsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      shippedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}shipped_at'],
      ),
      shippedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shipped_by'],
      ),
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      ),
      receivedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}received_by'],
      ),
      warehouseNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}warehouse_note'],
      ),
    );
  }

  @override
  $GoodsReturnsTable createAlias(String alias) {
    return $GoodsReturnsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<GoodsReturnStatus, String> $converterstatus =
      const GoodsReturnStatusConverter();
}

class GoodsReturnRow extends DataClass implements Insertable<GoodsReturnRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Temporary local number `TMP-RET-{uuid}` until a sync backend assigns the final
  /// `RET-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
  /// would collide across devices — every branch returns on its own.
  final String docNumber;

  /// The Good Receipt whose rejections this document sends back. Unique: see the
  /// class note. Fixed at creation — there is no statement anywhere that updates it.
  final String grId;

  /// The branch sending the goods back. Must be the receipt's branch — a cross-table
  /// equality SQLite cannot express, so the use cases enforce it (see the class note).
  final String branchId;

  /// The Kepala Cabang who raised the document (G-A3). Immutable.
  final String createdBy;
  final GoodsReturnStatus status;

  /// Free-text remark from the branch, e.g. *"dikirim via kurir internal"*.
  ///
  /// **Optional.** Every line already carries the mandatory reason G-G4 demanded when
  /// the position was rejected, snapshotted below, so requiring a second explanation
  /// on the header would be inventing a rule. What the CHECK does refuse is
  /// *whitespace* pretending to be a remark.
  final String? note;

  /// UTC instant the branch handed the goods to the carrier (T-1).
  ///
  /// Records a *physical* event and nothing else: no balance moves when this is
  /// written (§20). The goods left the branch's care, but they were never in the
  /// branch's stock — G-G5 credits only `checked` lines — so there is no balance to
  /// take them out of.
  final DateTime? shippedAt;

  /// Who shipped it. Null exactly while the document is a draft.
  final String? shippedBy;

  /// UTC instant the Warehouse confirmed arrival and the ledger was posted (T-1).
  final DateTime? receivedAt;

  /// The Petugas Warehouse who confirmed arrival. Null until then, and never equal to
  /// [createdBy] or [shippedBy] — see the class note on G-R4.
  final String? receivedBy;

  /// Optional remark the Warehouse adds when confirming, e.g. *"kardus penyok tapi
  /// isi lengkap"*.
  ///
  /// Writable only by the receive transaction (§21). A branch cannot write it and the
  /// Warehouse cannot write the branch's [note]: the two sides of this document each
  /// own their own words, which is what makes either of them evidence.
  final String? warehouseNote;
  const GoodsReturnRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.docNumber,
    required this.grId,
    required this.branchId,
    required this.createdBy,
    required this.status,
    this.note,
    this.shippedAt,
    this.shippedBy,
    this.receivedAt,
    this.receivedBy,
    this.warehouseNote,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $GoodsReturnsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['doc_number'] = Variable<String>(docNumber);
    map['gr_id'] = Variable<String>(grId);
    map['branch_id'] = Variable<String>(branchId);
    map['created_by'] = Variable<String>(createdBy);
    {
      map['status'] = Variable<String>(
        $GoodsReturnsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || shippedAt != null) {
      map['shipped_at'] = Variable<DateTime>(shippedAt);
    }
    if (!nullToAbsent || shippedBy != null) {
      map['shipped_by'] = Variable<String>(shippedBy);
    }
    if (!nullToAbsent || receivedAt != null) {
      map['received_at'] = Variable<DateTime>(receivedAt);
    }
    if (!nullToAbsent || receivedBy != null) {
      map['received_by'] = Variable<String>(receivedBy);
    }
    if (!nullToAbsent || warehouseNote != null) {
      map['warehouse_note'] = Variable<String>(warehouseNote);
    }
    return map;
  }

  GoodsReturnsCompanion toCompanion(bool nullToAbsent) {
    return GoodsReturnsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      docNumber: Value(docNumber),
      grId: Value(grId),
      branchId: Value(branchId),
      createdBy: Value(createdBy),
      status: Value(status),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      shippedAt: shippedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(shippedAt),
      shippedBy: shippedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(shippedBy),
      receivedAt: receivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(receivedAt),
      receivedBy: receivedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(receivedBy),
      warehouseNote: warehouseNote == null && nullToAbsent
          ? const Value.absent()
          : Value(warehouseNote),
    );
  }

  factory GoodsReturnRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoodsReturnRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      docNumber: serializer.fromJson<String>(json['docNumber']),
      grId: serializer.fromJson<String>(json['grId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      status: serializer.fromJson<GoodsReturnStatus>(json['status']),
      note: serializer.fromJson<String?>(json['note']),
      shippedAt: serializer.fromJson<DateTime?>(json['shippedAt']),
      shippedBy: serializer.fromJson<String?>(json['shippedBy']),
      receivedAt: serializer.fromJson<DateTime?>(json['receivedAt']),
      receivedBy: serializer.fromJson<String?>(json['receivedBy']),
      warehouseNote: serializer.fromJson<String?>(json['warehouseNote']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'docNumber': serializer.toJson<String>(docNumber),
      'grId': serializer.toJson<String>(grId),
      'branchId': serializer.toJson<String>(branchId),
      'createdBy': serializer.toJson<String>(createdBy),
      'status': serializer.toJson<GoodsReturnStatus>(status),
      'note': serializer.toJson<String?>(note),
      'shippedAt': serializer.toJson<DateTime?>(shippedAt),
      'shippedBy': serializer.toJson<String?>(shippedBy),
      'receivedAt': serializer.toJson<DateTime?>(receivedAt),
      'receivedBy': serializer.toJson<String?>(receivedBy),
      'warehouseNote': serializer.toJson<String?>(warehouseNote),
    };
  }

  GoodsReturnRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? docNumber,
    String? grId,
    String? branchId,
    String? createdBy,
    GoodsReturnStatus? status,
    Value<String?> note = const Value.absent(),
    Value<DateTime?> shippedAt = const Value.absent(),
    Value<String?> shippedBy = const Value.absent(),
    Value<DateTime?> receivedAt = const Value.absent(),
    Value<String?> receivedBy = const Value.absent(),
    Value<String?> warehouseNote = const Value.absent(),
  }) => GoodsReturnRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    docNumber: docNumber ?? this.docNumber,
    grId: grId ?? this.grId,
    branchId: branchId ?? this.branchId,
    createdBy: createdBy ?? this.createdBy,
    status: status ?? this.status,
    note: note.present ? note.value : this.note,
    shippedAt: shippedAt.present ? shippedAt.value : this.shippedAt,
    shippedBy: shippedBy.present ? shippedBy.value : this.shippedBy,
    receivedAt: receivedAt.present ? receivedAt.value : this.receivedAt,
    receivedBy: receivedBy.present ? receivedBy.value : this.receivedBy,
    warehouseNote: warehouseNote.present
        ? warehouseNote.value
        : this.warehouseNote,
  );
  GoodsReturnRow copyWithCompanion(GoodsReturnsCompanion data) {
    return GoodsReturnRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      docNumber: data.docNumber.present ? data.docNumber.value : this.docNumber,
      grId: data.grId.present ? data.grId.value : this.grId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      status: data.status.present ? data.status.value : this.status,
      note: data.note.present ? data.note.value : this.note,
      shippedAt: data.shippedAt.present ? data.shippedAt.value : this.shippedAt,
      shippedBy: data.shippedBy.present ? data.shippedBy.value : this.shippedBy,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      receivedBy: data.receivedBy.present
          ? data.receivedBy.value
          : this.receivedBy,
      warehouseNote: data.warehouseNote.present
          ? data.warehouseNote.value
          : this.warehouseNote,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoodsReturnRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('grId: $grId, ')
          ..write('branchId: $branchId, ')
          ..write('createdBy: $createdBy, ')
          ..write('status: $status, ')
          ..write('note: $note, ')
          ..write('shippedAt: $shippedAt, ')
          ..write('shippedBy: $shippedBy, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('receivedBy: $receivedBy, ')
          ..write('warehouseNote: $warehouseNote')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    docNumber,
    grId,
    branchId,
    createdBy,
    status,
    note,
    shippedAt,
    shippedBy,
    receivedAt,
    receivedBy,
    warehouseNote,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodsReturnRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.docNumber == this.docNumber &&
          other.grId == this.grId &&
          other.branchId == this.branchId &&
          other.createdBy == this.createdBy &&
          other.status == this.status &&
          other.note == this.note &&
          other.shippedAt == this.shippedAt &&
          other.shippedBy == this.shippedBy &&
          other.receivedAt == this.receivedAt &&
          other.receivedBy == this.receivedBy &&
          other.warehouseNote == this.warehouseNote);
}

class GoodsReturnsCompanion extends UpdateCompanion<GoodsReturnRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> docNumber;
  final Value<String> grId;
  final Value<String> branchId;
  final Value<String> createdBy;
  final Value<GoodsReturnStatus> status;
  final Value<String?> note;
  final Value<DateTime?> shippedAt;
  final Value<String?> shippedBy;
  final Value<DateTime?> receivedAt;
  final Value<String?> receivedBy;
  final Value<String?> warehouseNote;
  final Value<int> rowid;
  const GoodsReturnsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.docNumber = const Value.absent(),
    this.grId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.status = const Value.absent(),
    this.note = const Value.absent(),
    this.shippedAt = const Value.absent(),
    this.shippedBy = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.receivedBy = const Value.absent(),
    this.warehouseNote = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoodsReturnsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String docNumber,
    required String grId,
    required String branchId,
    required String createdBy,
    this.status = const Value.absent(),
    this.note = const Value.absent(),
    this.shippedAt = const Value.absent(),
    this.shippedBy = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.receivedBy = const Value.absent(),
    this.warehouseNote = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docNumber = Value(docNumber),
       grId = Value(grId),
       branchId = Value(branchId),
       createdBy = Value(createdBy);
  static Insertable<GoodsReturnRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? docNumber,
    Expression<String>? grId,
    Expression<String>? branchId,
    Expression<String>? createdBy,
    Expression<String>? status,
    Expression<String>? note,
    Expression<DateTime>? shippedAt,
    Expression<String>? shippedBy,
    Expression<DateTime>? receivedAt,
    Expression<String>? receivedBy,
    Expression<String>? warehouseNote,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (docNumber != null) 'doc_number': docNumber,
      if (grId != null) 'gr_id': grId,
      if (branchId != null) 'branch_id': branchId,
      if (createdBy != null) 'created_by': createdBy,
      if (status != null) 'status': status,
      if (note != null) 'note': note,
      if (shippedAt != null) 'shipped_at': shippedAt,
      if (shippedBy != null) 'shipped_by': shippedBy,
      if (receivedAt != null) 'received_at': receivedAt,
      if (receivedBy != null) 'received_by': receivedBy,
      if (warehouseNote != null) 'warehouse_note': warehouseNote,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoodsReturnsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? docNumber,
    Value<String>? grId,
    Value<String>? branchId,
    Value<String>? createdBy,
    Value<GoodsReturnStatus>? status,
    Value<String?>? note,
    Value<DateTime?>? shippedAt,
    Value<String?>? shippedBy,
    Value<DateTime?>? receivedAt,
    Value<String?>? receivedBy,
    Value<String?>? warehouseNote,
    Value<int>? rowid,
  }) {
    return GoodsReturnsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      docNumber: docNumber ?? this.docNumber,
      grId: grId ?? this.grId,
      branchId: branchId ?? this.branchId,
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      note: note ?? this.note,
      shippedAt: shippedAt ?? this.shippedAt,
      shippedBy: shippedBy ?? this.shippedBy,
      receivedAt: receivedAt ?? this.receivedAt,
      receivedBy: receivedBy ?? this.receivedBy,
      warehouseNote: warehouseNote ?? this.warehouseNote,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $GoodsReturnsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (docNumber.present) {
      map['doc_number'] = Variable<String>(docNumber.value);
    }
    if (grId.present) {
      map['gr_id'] = Variable<String>(grId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $GoodsReturnsTable.$converterstatus.toSql(status.value),
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (shippedAt.present) {
      map['shipped_at'] = Variable<DateTime>(shippedAt.value);
    }
    if (shippedBy.present) {
      map['shipped_by'] = Variable<String>(shippedBy.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (receivedBy.present) {
      map['received_by'] = Variable<String>(receivedBy.value);
    }
    if (warehouseNote.present) {
      map['warehouse_note'] = Variable<String>(warehouseNote.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoodsReturnsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('docNumber: $docNumber, ')
          ..write('grId: $grId, ')
          ..write('branchId: $branchId, ')
          ..write('createdBy: $createdBy, ')
          ..write('status: $status, ')
          ..write('note: $note, ')
          ..write('shippedAt: $shippedAt, ')
          ..write('shippedBy: $shippedBy, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('receivedBy: $receivedBy, ')
          ..write('warehouseNote: $warehouseNote, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoodsReturnLinesTable extends GoodsReturnLines
    with TableInfo<$GoodsReturnLinesTable, GoodsReturnLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoodsReturnLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($GoodsReturnLinesTable.$convertersyncStatus);
  static const VerificationMeta _goodsReturnIdMeta = const VerificationMeta(
    'goodsReturnId',
  );
  @override
  late final GeneratedColumn<String> goodsReturnId = GeneratedColumn<String>(
    'goods_return_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES goods_returns (id)',
    ),
  );
  static const VerificationMeta _grLineIdMeta = const VerificationMeta(
    'grLineId',
  );
  @override
  late final GeneratedColumn<String> grLineId = GeneratedColumn<String>(
    'gr_line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES good_receipt_lines (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_batches (id)',
    ),
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rejectReasonSnapshotMeta =
      const VerificationMeta('rejectReasonSnapshot');
  @override
  late final GeneratedColumn<String> rejectReasonSnapshot =
      GeneratedColumn<String>(
        'reject_reason_snapshot',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    goodsReturnId,
    grLineId,
    itemId,
    batchId,
    qty,
    rejectReasonSnapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goods_return_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<GoodsReturnLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('goods_return_id')) {
      context.handle(
        _goodsReturnIdMeta,
        goodsReturnId.isAcceptableOrUnknown(
          data['goods_return_id']!,
          _goodsReturnIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_goodsReturnIdMeta);
    }
    if (data.containsKey('gr_line_id')) {
      context.handle(
        _grLineIdMeta,
        grLineId.isAcceptableOrUnknown(data['gr_line_id']!, _grLineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_grLineIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('reject_reason_snapshot')) {
      context.handle(
        _rejectReasonSnapshotMeta,
        rejectReasonSnapshot.isAcceptableOrUnknown(
          data['reject_reason_snapshot']!,
          _rejectReasonSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rejectReasonSnapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GoodsReturnLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GoodsReturnLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $GoodsReturnLinesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      goodsReturnId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goods_return_id'],
      )!,
      grLineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gr_line_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty'],
      )!,
      rejectReasonSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reject_reason_snapshot'],
      )!,
    );
  }

  @override
  $GoodsReturnLinesTable createAlias(String alias) {
    return $GoodsReturnLinesTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
}

class GoodsReturnLineRow extends DataClass
    implements Insertable<GoodsReturnLineRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final String goodsReturnId;

  /// The rejected Good Receipt position this line sends back. Unique twice: see the
  /// class note.
  final String grLineId;
  final String itemId;

  /// The batch that was rejected. NULL, and only NULL, for an item without expiry
  /// (G-E2); the create use case enforces both directions because the rule depends on
  /// `items.has_expiry`, which this table cannot read.
  ///
  /// An **expired** batch is entirely legitimate here, unlike on every outbound
  /// document in this schema. G-E5 says so directly — goods too close to their expiry
  /// date are a reason to reject, and a rejection has to be able to go home (§36).
  final String? batchId;

  /// Returned quantity in **milli-units** (Q-3), always equal to the source Good
  /// Receipt line's `shipped_qty`. Strictly positive: a return of nothing is not a
  /// line, and the ledger records changes rather than confirmations (G-A1).
  final int qty;

  /// The reason the branch head gave when refusing this position (G-G4), copied at
  /// creation. Mandatory and non-blank — see the class note.
  final String rejectReasonSnapshot;
  const GoodsReturnLineRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.goodsReturnId,
    required this.grLineId,
    required this.itemId,
    this.batchId,
    required this.qty,
    required this.rejectReasonSnapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $GoodsReturnLinesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['goods_return_id'] = Variable<String>(goodsReturnId);
    map['gr_line_id'] = Variable<String>(grLineId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    map['qty'] = Variable<int>(qty);
    map['reject_reason_snapshot'] = Variable<String>(rejectReasonSnapshot);
    return map;
  }

  GoodsReturnLinesCompanion toCompanion(bool nullToAbsent) {
    return GoodsReturnLinesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      goodsReturnId: Value(goodsReturnId),
      grLineId: Value(grLineId),
      itemId: Value(itemId),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
      qty: Value(qty),
      rejectReasonSnapshot: Value(rejectReasonSnapshot),
    );
  }

  factory GoodsReturnLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GoodsReturnLineRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      goodsReturnId: serializer.fromJson<String>(json['goodsReturnId']),
      grLineId: serializer.fromJson<String>(json['grLineId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      batchId: serializer.fromJson<String?>(json['batchId']),
      qty: serializer.fromJson<int>(json['qty']),
      rejectReasonSnapshot: serializer.fromJson<String>(
        json['rejectReasonSnapshot'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'goodsReturnId': serializer.toJson<String>(goodsReturnId),
      'grLineId': serializer.toJson<String>(grLineId),
      'itemId': serializer.toJson<String>(itemId),
      'batchId': serializer.toJson<String?>(batchId),
      'qty': serializer.toJson<int>(qty),
      'rejectReasonSnapshot': serializer.toJson<String>(rejectReasonSnapshot),
    };
  }

  GoodsReturnLineRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    String? goodsReturnId,
    String? grLineId,
    String? itemId,
    Value<String?> batchId = const Value.absent(),
    int? qty,
    String? rejectReasonSnapshot,
  }) => GoodsReturnLineRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    goodsReturnId: goodsReturnId ?? this.goodsReturnId,
    grLineId: grLineId ?? this.grLineId,
    itemId: itemId ?? this.itemId,
    batchId: batchId.present ? batchId.value : this.batchId,
    qty: qty ?? this.qty,
    rejectReasonSnapshot: rejectReasonSnapshot ?? this.rejectReasonSnapshot,
  );
  GoodsReturnLineRow copyWithCompanion(GoodsReturnLinesCompanion data) {
    return GoodsReturnLineRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      goodsReturnId: data.goodsReturnId.present
          ? data.goodsReturnId.value
          : this.goodsReturnId,
      grLineId: data.grLineId.present ? data.grLineId.value : this.grLineId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      qty: data.qty.present ? data.qty.value : this.qty,
      rejectReasonSnapshot: data.rejectReasonSnapshot.present
          ? data.rejectReasonSnapshot.value
          : this.rejectReasonSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GoodsReturnLineRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('goodsReturnId: $goodsReturnId, ')
          ..write('grLineId: $grLineId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('rejectReasonSnapshot: $rejectReasonSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    goodsReturnId,
    grLineId,
    itemId,
    batchId,
    qty,
    rejectReasonSnapshot,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoodsReturnLineRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.goodsReturnId == this.goodsReturnId &&
          other.grLineId == this.grLineId &&
          other.itemId == this.itemId &&
          other.batchId == this.batchId &&
          other.qty == this.qty &&
          other.rejectReasonSnapshot == this.rejectReasonSnapshot);
}

class GoodsReturnLinesCompanion extends UpdateCompanion<GoodsReturnLineRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<String> goodsReturnId;
  final Value<String> grLineId;
  final Value<String> itemId;
  final Value<String?> batchId;
  final Value<int> qty;
  final Value<String> rejectReasonSnapshot;
  final Value<int> rowid;
  const GoodsReturnLinesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.goodsReturnId = const Value.absent(),
    this.grLineId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.batchId = const Value.absent(),
    this.qty = const Value.absent(),
    this.rejectReasonSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoodsReturnLinesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required String goodsReturnId,
    required String grLineId,
    required String itemId,
    this.batchId = const Value.absent(),
    required int qty,
    required String rejectReasonSnapshot,
    this.rowid = const Value.absent(),
  }) : goodsReturnId = Value(goodsReturnId),
       grLineId = Value(grLineId),
       itemId = Value(itemId),
       qty = Value(qty),
       rejectReasonSnapshot = Value(rejectReasonSnapshot);
  static Insertable<GoodsReturnLineRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? goodsReturnId,
    Expression<String>? grLineId,
    Expression<String>? itemId,
    Expression<String>? batchId,
    Expression<int>? qty,
    Expression<String>? rejectReasonSnapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (goodsReturnId != null) 'goods_return_id': goodsReturnId,
      if (grLineId != null) 'gr_line_id': grLineId,
      if (itemId != null) 'item_id': itemId,
      if (batchId != null) 'batch_id': batchId,
      if (qty != null) 'qty': qty,
      if (rejectReasonSnapshot != null)
        'reject_reason_snapshot': rejectReasonSnapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoodsReturnLinesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<String>? goodsReturnId,
    Value<String>? grLineId,
    Value<String>? itemId,
    Value<String?>? batchId,
    Value<int>? qty,
    Value<String>? rejectReasonSnapshot,
    Value<int>? rowid,
  }) {
    return GoodsReturnLinesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      goodsReturnId: goodsReturnId ?? this.goodsReturnId,
      grLineId: grLineId ?? this.grLineId,
      itemId: itemId ?? this.itemId,
      batchId: batchId ?? this.batchId,
      qty: qty ?? this.qty,
      rejectReasonSnapshot: rejectReasonSnapshot ?? this.rejectReasonSnapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $GoodsReturnLinesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (goodsReturnId.present) {
      map['goods_return_id'] = Variable<String>(goodsReturnId.value);
    }
    if (grLineId.present) {
      map['gr_line_id'] = Variable<String>(grLineId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (rejectReasonSnapshot.present) {
      map['reject_reason_snapshot'] = Variable<String>(
        rejectReasonSnapshot.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoodsReturnLinesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('goodsReturnId: $goodsReturnId, ')
          ..write('grLineId: $grLineId, ')
          ..write('itemId: $itemId, ')
          ..write('batchId: $batchId, ')
          ..write('qty: $qty, ')
          ..write('rejectReasonSnapshot: $rejectReasonSnapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExportLogsTable extends ExportLogs
    with TableInfo<$ExportLogsTable, ExportLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExportLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ExportLogsTable.$convertersyncStatus);
  @override
  late final GeneratedColumnWithTypeConverter<ReportType, String> reportType =
      GeneratedColumn<String>(
        'report_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ReportType>($ExportLogsTable.$converterreportType);
  @override
  late final GeneratedColumnWithTypeConverter<ReportFormat, String> format =
      GeneratedColumn<String>(
        'format',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ReportFormat>($ExportLogsTable.$converterformat);
  @override
  late final GeneratedColumnWithTypeConverter<ReportScopeType, String>
  scopeType = GeneratedColumn<String>(
    'scope_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<ReportScopeType>($ExportLogsTable.$converterscopeType);
  static const VerificationMeta _locationIdMeta = const VerificationMeta(
    'locationId',
  );
  @override
  late final GeneratedColumn<String> locationId = GeneratedColumn<String>(
    'location_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_locations (id)',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES item_categories (id)',
    ),
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES branches (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id)',
    ),
  );
  static const VerificationMeta _periodStartMeta = const VerificationMeta(
    'periodStart',
  );
  @override
  late final GeneratedColumn<DateTime> periodStart = GeneratedColumn<DateTime>(
    'period_start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodEndMeta = const VerificationMeta(
    'periodEnd',
  );
  @override
  late final GeneratedColumn<DateTime> periodEnd = GeneratedColumn<DateTime>(
    'period_end',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exportedByMeta = const VerificationMeta(
    'exportedBy',
  );
  @override
  late final GeneratedColumn<String> exportedBy = GeneratedColumn<String>(
    'exported_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataCutoffAtMeta = const VerificationMeta(
    'dataCutoffAt',
  );
  @override
  late final GeneratedColumn<DateTime> dataCutoffAt = GeneratedColumn<DateTime>(
    'data_cutoff_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncSummaryMeta = const VerificationMeta(
    'syncSummary',
  );
  @override
  late final GeneratedColumn<String> syncSummary = GeneratedColumn<String>(
    'sync_summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowCountMeta = const VerificationMeta(
    'rowCount',
  );
  @override
  late final GeneratedColumn<int> rowCount = GeneratedColumn<int>(
    'row_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    reportType,
    format,
    scopeType,
    locationId,
    categoryId,
    branchId,
    itemId,
    periodStart,
    periodEnd,
    exportedBy,
    fileName,
    dataCutoffAt,
    syncSummary,
    rowCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'export_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExportLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('location_id')) {
      context.handle(
        _locationIdMeta,
        locationId.isAcceptableOrUnknown(data['location_id']!, _locationIdMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    }
    if (data.containsKey('period_start')) {
      context.handle(
        _periodStartMeta,
        periodStart.isAcceptableOrUnknown(
          data['period_start']!,
          _periodStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodStartMeta);
    }
    if (data.containsKey('period_end')) {
      context.handle(
        _periodEndMeta,
        periodEnd.isAcceptableOrUnknown(data['period_end']!, _periodEndMeta),
      );
    } else if (isInserting) {
      context.missing(_periodEndMeta);
    }
    if (data.containsKey('exported_by')) {
      context.handle(
        _exportedByMeta,
        exportedBy.isAcceptableOrUnknown(data['exported_by']!, _exportedByMeta),
      );
    } else if (isInserting) {
      context.missing(_exportedByMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('data_cutoff_at')) {
      context.handle(
        _dataCutoffAtMeta,
        dataCutoffAt.isAcceptableOrUnknown(
          data['data_cutoff_at']!,
          _dataCutoffAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dataCutoffAtMeta);
    }
    if (data.containsKey('sync_summary')) {
      context.handle(
        _syncSummaryMeta,
        syncSummary.isAcceptableOrUnknown(
          data['sync_summary']!,
          _syncSummaryMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_syncSummaryMeta);
    }
    if (data.containsKey('row_count')) {
      context.handle(
        _rowCountMeta,
        rowCount.isAcceptableOrUnknown(data['row_count']!, _rowCountMeta),
      );
    } else if (isInserting) {
      context.missing(_rowCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExportLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExportLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ExportLogsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      reportType: $ExportLogsTable.$converterreportType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}report_type'],
        )!,
      ),
      format: $ExportLogsTable.$converterformat.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}format'],
        )!,
      ),
      scopeType: $ExportLogsTable.$converterscopeType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}scope_type'],
        )!,
      ),
      locationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_id'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      ),
      periodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}period_start'],
      )!,
      periodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}period_end'],
      )!,
      exportedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exported_by'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      dataCutoffAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}data_cutoff_at'],
      )!,
      syncSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_summary'],
      )!,
      rowCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_count'],
      )!,
    );
  }

  @override
  $ExportLogsTable createAlias(String alias) {
    return $ExportLogsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<ReportType, String> $converterreportType =
      const ReportTypeConverter();
  static TypeConverter<ReportFormat, String> $converterformat =
      const ReportFormatConverter();
  static TypeConverter<ReportScopeType, String> $converterscopeType =
      const ReportScopeTypeConverter();
}

class ExportLogRow extends DataClass implements Insertable<ExportLogRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Which report. Stored as the enum's `dbValue`, so the audit string and G-L5's
  /// filename token are the same token.
  final ReportType reportType;
  final ReportFormat format;
  final ReportScopeType scopeType;

  /// The single stock location, for the three single-location scopes. NULL for
  /// `branch_all`, `cross_branch` and `all_locations` — see the class note.
  final String? locationId;

  /// The category filter that was applied, or NULL when the report was run across
  /// every category and grouped with subtotals instead (G-L6).
  final String? categoryId;
  final String? branchId;

  /// The item a Kartu Stok was run for. NULL on every other report, and NULL is
  /// also legitimate on a `stok_lokasi` run without an item filter.
  final String? itemId;

  /// Civil dates (T-8), carried as UTC midnights and never converted. For an as-of
  /// report both hold the same date (§3.9) — an audit row that left `period_start`
  /// NULL would make "as of one day" and "range whose start was lost" the same row.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Who ran it (G-L2). Never nullable: an export with no actor is not an audit
  /// record.
  final String exportedBy;

  /// The canonical name the file was written and shared under (G-L5). Not a path.
  final String fileName;

  /// UTC instant the report snapshot was taken — the "data per" of G-L3.
  final DateTime dataCutoffAt;

  /// Human-readable sync snapshot, e.g. *"18 tersinkron · 2 pending · 0 konflik"*.
  /// Non-blank: a header that printed nothing here would be a header that did not
  /// answer G-L3.
  final String syncSummary;

  /// Data rows in the exported file. Zero is legitimate — an empty report still
  /// produces a valid file carrying its header and *"Tidak ada data"* (§52), and
  /// an export that found nothing is exactly the kind of thing an audit should
  /// record rather than swallow.
  final int rowCount;
  const ExportLogRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.reportType,
    required this.format,
    required this.scopeType,
    this.locationId,
    this.categoryId,
    this.branchId,
    this.itemId,
    required this.periodStart,
    required this.periodEnd,
    required this.exportedBy,
    required this.fileName,
    required this.dataCutoffAt,
    required this.syncSummary,
    required this.rowCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ExportLogsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    {
      map['report_type'] = Variable<String>(
        $ExportLogsTable.$converterreportType.toSql(reportType),
      );
    }
    {
      map['format'] = Variable<String>(
        $ExportLogsTable.$converterformat.toSql(format),
      );
    }
    {
      map['scope_type'] = Variable<String>(
        $ExportLogsTable.$converterscopeType.toSql(scopeType),
      );
    }
    if (!nullToAbsent || locationId != null) {
      map['location_id'] = Variable<String>(locationId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    if (!nullToAbsent || itemId != null) {
      map['item_id'] = Variable<String>(itemId);
    }
    map['period_start'] = Variable<DateTime>(periodStart);
    map['period_end'] = Variable<DateTime>(periodEnd);
    map['exported_by'] = Variable<String>(exportedBy);
    map['file_name'] = Variable<String>(fileName);
    map['data_cutoff_at'] = Variable<DateTime>(dataCutoffAt);
    map['sync_summary'] = Variable<String>(syncSummary);
    map['row_count'] = Variable<int>(rowCount);
    return map;
  }

  ExportLogsCompanion toCompanion(bool nullToAbsent) {
    return ExportLogsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      reportType: Value(reportType),
      format: Value(format),
      scopeType: Value(scopeType),
      locationId: locationId == null && nullToAbsent
          ? const Value.absent()
          : Value(locationId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      itemId: itemId == null && nullToAbsent
          ? const Value.absent()
          : Value(itemId),
      periodStart: Value(periodStart),
      periodEnd: Value(periodEnd),
      exportedBy: Value(exportedBy),
      fileName: Value(fileName),
      dataCutoffAt: Value(dataCutoffAt),
      syncSummary: Value(syncSummary),
      rowCount: Value(rowCount),
    );
  }

  factory ExportLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExportLogRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      reportType: serializer.fromJson<ReportType>(json['reportType']),
      format: serializer.fromJson<ReportFormat>(json['format']),
      scopeType: serializer.fromJson<ReportScopeType>(json['scopeType']),
      locationId: serializer.fromJson<String?>(json['locationId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      itemId: serializer.fromJson<String?>(json['itemId']),
      periodStart: serializer.fromJson<DateTime>(json['periodStart']),
      periodEnd: serializer.fromJson<DateTime>(json['periodEnd']),
      exportedBy: serializer.fromJson<String>(json['exportedBy']),
      fileName: serializer.fromJson<String>(json['fileName']),
      dataCutoffAt: serializer.fromJson<DateTime>(json['dataCutoffAt']),
      syncSummary: serializer.fromJson<String>(json['syncSummary']),
      rowCount: serializer.fromJson<int>(json['rowCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'reportType': serializer.toJson<ReportType>(reportType),
      'format': serializer.toJson<ReportFormat>(format),
      'scopeType': serializer.toJson<ReportScopeType>(scopeType),
      'locationId': serializer.toJson<String?>(locationId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'branchId': serializer.toJson<String?>(branchId),
      'itemId': serializer.toJson<String?>(itemId),
      'periodStart': serializer.toJson<DateTime>(periodStart),
      'periodEnd': serializer.toJson<DateTime>(periodEnd),
      'exportedBy': serializer.toJson<String>(exportedBy),
      'fileName': serializer.toJson<String>(fileName),
      'dataCutoffAt': serializer.toJson<DateTime>(dataCutoffAt),
      'syncSummary': serializer.toJson<String>(syncSummary),
      'rowCount': serializer.toJson<int>(rowCount),
    };
  }

  ExportLogRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    ReportType? reportType,
    ReportFormat? format,
    ReportScopeType? scopeType,
    Value<String?> locationId = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<String?> branchId = const Value.absent(),
    Value<String?> itemId = const Value.absent(),
    DateTime? periodStart,
    DateTime? periodEnd,
    String? exportedBy,
    String? fileName,
    DateTime? dataCutoffAt,
    String? syncSummary,
    int? rowCount,
  }) => ExportLogRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    reportType: reportType ?? this.reportType,
    format: format ?? this.format,
    scopeType: scopeType ?? this.scopeType,
    locationId: locationId.present ? locationId.value : this.locationId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    branchId: branchId.present ? branchId.value : this.branchId,
    itemId: itemId.present ? itemId.value : this.itemId,
    periodStart: periodStart ?? this.periodStart,
    periodEnd: periodEnd ?? this.periodEnd,
    exportedBy: exportedBy ?? this.exportedBy,
    fileName: fileName ?? this.fileName,
    dataCutoffAt: dataCutoffAt ?? this.dataCutoffAt,
    syncSummary: syncSummary ?? this.syncSummary,
    rowCount: rowCount ?? this.rowCount,
  );
  ExportLogRow copyWithCompanion(ExportLogsCompanion data) {
    return ExportLogRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      reportType: data.reportType.present
          ? data.reportType.value
          : this.reportType,
      format: data.format.present ? data.format.value : this.format,
      scopeType: data.scopeType.present ? data.scopeType.value : this.scopeType,
      locationId: data.locationId.present
          ? data.locationId.value
          : this.locationId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      periodStart: data.periodStart.present
          ? data.periodStart.value
          : this.periodStart,
      periodEnd: data.periodEnd.present ? data.periodEnd.value : this.periodEnd,
      exportedBy: data.exportedBy.present
          ? data.exportedBy.value
          : this.exportedBy,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      dataCutoffAt: data.dataCutoffAt.present
          ? data.dataCutoffAt.value
          : this.dataCutoffAt,
      syncSummary: data.syncSummary.present
          ? data.syncSummary.value
          : this.syncSummary,
      rowCount: data.rowCount.present ? data.rowCount.value : this.rowCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExportLogRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('reportType: $reportType, ')
          ..write('format: $format, ')
          ..write('scopeType: $scopeType, ')
          ..write('locationId: $locationId, ')
          ..write('categoryId: $categoryId, ')
          ..write('branchId: $branchId, ')
          ..write('itemId: $itemId, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('exportedBy: $exportedBy, ')
          ..write('fileName: $fileName, ')
          ..write('dataCutoffAt: $dataCutoffAt, ')
          ..write('syncSummary: $syncSummary, ')
          ..write('rowCount: $rowCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    reportType,
    format,
    scopeType,
    locationId,
    categoryId,
    branchId,
    itemId,
    periodStart,
    periodEnd,
    exportedBy,
    fileName,
    dataCutoffAt,
    syncSummary,
    rowCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExportLogRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.reportType == this.reportType &&
          other.format == this.format &&
          other.scopeType == this.scopeType &&
          other.locationId == this.locationId &&
          other.categoryId == this.categoryId &&
          other.branchId == this.branchId &&
          other.itemId == this.itemId &&
          other.periodStart == this.periodStart &&
          other.periodEnd == this.periodEnd &&
          other.exportedBy == this.exportedBy &&
          other.fileName == this.fileName &&
          other.dataCutoffAt == this.dataCutoffAt &&
          other.syncSummary == this.syncSummary &&
          other.rowCount == this.rowCount);
}

class ExportLogsCompanion extends UpdateCompanion<ExportLogRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<ReportType> reportType;
  final Value<ReportFormat> format;
  final Value<ReportScopeType> scopeType;
  final Value<String?> locationId;
  final Value<String?> categoryId;
  final Value<String?> branchId;
  final Value<String?> itemId;
  final Value<DateTime> periodStart;
  final Value<DateTime> periodEnd;
  final Value<String> exportedBy;
  final Value<String> fileName;
  final Value<DateTime> dataCutoffAt;
  final Value<String> syncSummary;
  final Value<int> rowCount;
  final Value<int> rowid;
  const ExportLogsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.reportType = const Value.absent(),
    this.format = const Value.absent(),
    this.scopeType = const Value.absent(),
    this.locationId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.periodStart = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.exportedBy = const Value.absent(),
    this.fileName = const Value.absent(),
    this.dataCutoffAt = const Value.absent(),
    this.syncSummary = const Value.absent(),
    this.rowCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExportLogsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required ReportType reportType,
    required ReportFormat format,
    required ReportScopeType scopeType,
    this.locationId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.itemId = const Value.absent(),
    required DateTime periodStart,
    required DateTime periodEnd,
    required String exportedBy,
    required String fileName,
    required DateTime dataCutoffAt,
    required String syncSummary,
    required int rowCount,
    this.rowid = const Value.absent(),
  }) : reportType = Value(reportType),
       format = Value(format),
       scopeType = Value(scopeType),
       periodStart = Value(periodStart),
       periodEnd = Value(periodEnd),
       exportedBy = Value(exportedBy),
       fileName = Value(fileName),
       dataCutoffAt = Value(dataCutoffAt),
       syncSummary = Value(syncSummary),
       rowCount = Value(rowCount);
  static Insertable<ExportLogRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? reportType,
    Expression<String>? format,
    Expression<String>? scopeType,
    Expression<String>? locationId,
    Expression<String>? categoryId,
    Expression<String>? branchId,
    Expression<String>? itemId,
    Expression<DateTime>? periodStart,
    Expression<DateTime>? periodEnd,
    Expression<String>? exportedBy,
    Expression<String>? fileName,
    Expression<DateTime>? dataCutoffAt,
    Expression<String>? syncSummary,
    Expression<int>? rowCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (reportType != null) 'report_type': reportType,
      if (format != null) 'format': format,
      if (scopeType != null) 'scope_type': scopeType,
      if (locationId != null) 'location_id': locationId,
      if (categoryId != null) 'category_id': categoryId,
      if (branchId != null) 'branch_id': branchId,
      if (itemId != null) 'item_id': itemId,
      if (periodStart != null) 'period_start': periodStart,
      if (periodEnd != null) 'period_end': periodEnd,
      if (exportedBy != null) 'exported_by': exportedBy,
      if (fileName != null) 'file_name': fileName,
      if (dataCutoffAt != null) 'data_cutoff_at': dataCutoffAt,
      if (syncSummary != null) 'sync_summary': syncSummary,
      if (rowCount != null) 'row_count': rowCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExportLogsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<ReportType>? reportType,
    Value<ReportFormat>? format,
    Value<ReportScopeType>? scopeType,
    Value<String?>? locationId,
    Value<String?>? categoryId,
    Value<String?>? branchId,
    Value<String?>? itemId,
    Value<DateTime>? periodStart,
    Value<DateTime>? periodEnd,
    Value<String>? exportedBy,
    Value<String>? fileName,
    Value<DateTime>? dataCutoffAt,
    Value<String>? syncSummary,
    Value<int>? rowCount,
    Value<int>? rowid,
  }) {
    return ExportLogsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      reportType: reportType ?? this.reportType,
      format: format ?? this.format,
      scopeType: scopeType ?? this.scopeType,
      locationId: locationId ?? this.locationId,
      categoryId: categoryId ?? this.categoryId,
      branchId: branchId ?? this.branchId,
      itemId: itemId ?? this.itemId,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      exportedBy: exportedBy ?? this.exportedBy,
      fileName: fileName ?? this.fileName,
      dataCutoffAt: dataCutoffAt ?? this.dataCutoffAt,
      syncSummary: syncSummary ?? this.syncSummary,
      rowCount: rowCount ?? this.rowCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ExportLogsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (reportType.present) {
      map['report_type'] = Variable<String>(
        $ExportLogsTable.$converterreportType.toSql(reportType.value),
      );
    }
    if (format.present) {
      map['format'] = Variable<String>(
        $ExportLogsTable.$converterformat.toSql(format.value),
      );
    }
    if (scopeType.present) {
      map['scope_type'] = Variable<String>(
        $ExportLogsTable.$converterscopeType.toSql(scopeType.value),
      );
    }
    if (locationId.present) {
      map['location_id'] = Variable<String>(locationId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (periodStart.present) {
      map['period_start'] = Variable<DateTime>(periodStart.value);
    }
    if (periodEnd.present) {
      map['period_end'] = Variable<DateTime>(periodEnd.value);
    }
    if (exportedBy.present) {
      map['exported_by'] = Variable<String>(exportedBy.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (dataCutoffAt.present) {
      map['data_cutoff_at'] = Variable<DateTime>(dataCutoffAt.value);
    }
    if (syncSummary.present) {
      map['sync_summary'] = Variable<String>(syncSummary.value);
    }
    if (rowCount.present) {
      map['row_count'] = Variable<int>(rowCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExportLogsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('reportType: $reportType, ')
          ..write('format: $format, ')
          ..write('scopeType: $scopeType, ')
          ..write('locationId: $locationId, ')
          ..write('categoryId: $categoryId, ')
          ..write('branchId: $branchId, ')
          ..write('itemId: $itemId, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('exportedBy: $exportedBy, ')
          ..write('fileName: $fileName, ')
          ..write('dataCutoffAt: $dataCutoffAt, ')
          ..write('syncSummary: $syncSummary, ')
          ..write('rowCount: $rowCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportLogsTable extends ImportLogs
    with TableInfo<$ImportLogsTable, ImportLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncStatus, String> syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        clientDefault: () => SyncStatus.pending.dbValue,
      ).withConverter<SyncStatus>($ImportLogsTable.$convertersyncStatus);
  @override
  late final GeneratedColumnWithTypeConverter<ImportEntity, String> entity =
      GeneratedColumn<String>(
        'entity',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ImportEntity>($ImportLogsTable.$converterentity);
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalRowsMeta = const VerificationMeta(
    'totalRows',
  );
  @override
  late final GeneratedColumn<int> totalRows = GeneratedColumn<int>(
    'total_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _insertedRowsMeta = const VerificationMeta(
    'insertedRows',
  );
  @override
  late final GeneratedColumn<int> insertedRows = GeneratedColumn<int>(
    'inserted_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedRowsMeta = const VerificationMeta(
    'updatedRows',
  );
  @override
  late final GeneratedColumn<int> updatedRows = GeneratedColumn<int>(
    'updated_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failedRowsMeta = const VerificationMeta(
    'failedRows',
  );
  @override
  late final GeneratedColumn<int> failedRows = GeneratedColumn<int>(
    'failed_rows',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorDetailMeta = const VerificationMeta(
    'errorDetail',
  );
  @override
  late final GeneratedColumn<String> errorDetail = GeneratedColumn<String>(
    'error_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ImportStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ImportStatus>($ImportLogsTable.$converterstatus);
  static const VerificationMeta _importedByMeta = const VerificationMeta(
    'importedBy',
  );
  @override
  late final GeneratedColumn<String> importedBy = GeneratedColumn<String>(
    'imported_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES users (id)',
    ),
  );
  static const VerificationMeta _storedFilePathMeta = const VerificationMeta(
    'storedFilePath',
  );
  @override
  late final GeneratedColumn<String> storedFilePath = GeneratedColumn<String>(
    'stored_file_path',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 1024,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSha256Meta = const VerificationMeta(
    'fileSha256',
  );
  @override
  late final GeneratedColumn<String> fileSha256 = GeneratedColumn<String>(
    'file_sha256',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateVersionMeta = const VerificationMeta(
    'templateVersion',
  );
  @override
  late final GeneratedColumn<String> templateVersion = GeneratedColumn<String>(
    'template_version',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    entity,
    fileName,
    totalRows,
    insertedRows,
    updatedRows,
    failedRows,
    errorDetail,
    status,
    importedBy,
    storedFilePath,
    fileSha256,
    fileSizeBytes,
    templateVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'import_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('total_rows')) {
      context.handle(
        _totalRowsMeta,
        totalRows.isAcceptableOrUnknown(data['total_rows']!, _totalRowsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalRowsMeta);
    }
    if (data.containsKey('inserted_rows')) {
      context.handle(
        _insertedRowsMeta,
        insertedRows.isAcceptableOrUnknown(
          data['inserted_rows']!,
          _insertedRowsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_insertedRowsMeta);
    }
    if (data.containsKey('updated_rows')) {
      context.handle(
        _updatedRowsMeta,
        updatedRows.isAcceptableOrUnknown(
          data['updated_rows']!,
          _updatedRowsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedRowsMeta);
    }
    if (data.containsKey('failed_rows')) {
      context.handle(
        _failedRowsMeta,
        failedRows.isAcceptableOrUnknown(data['failed_rows']!, _failedRowsMeta),
      );
    } else if (isInserting) {
      context.missing(_failedRowsMeta);
    }
    if (data.containsKey('error_detail')) {
      context.handle(
        _errorDetailMeta,
        errorDetail.isAcceptableOrUnknown(
          data['error_detail']!,
          _errorDetailMeta,
        ),
      );
    }
    if (data.containsKey('imported_by')) {
      context.handle(
        _importedByMeta,
        importedBy.isAcceptableOrUnknown(data['imported_by']!, _importedByMeta),
      );
    } else if (isInserting) {
      context.missing(_importedByMeta);
    }
    if (data.containsKey('stored_file_path')) {
      context.handle(
        _storedFilePathMeta,
        storedFilePath.isAcceptableOrUnknown(
          data['stored_file_path']!,
          _storedFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_storedFilePathMeta);
    }
    if (data.containsKey('file_sha256')) {
      context.handle(
        _fileSha256Meta,
        fileSha256.isAcceptableOrUnknown(data['file_sha256']!, _fileSha256Meta),
      );
    } else if (isInserting) {
      context.missing(_fileSha256Meta);
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('template_version')) {
      context.handle(
        _templateVersionMeta,
        templateVersion.isAcceptableOrUnknown(
          data['template_version']!,
          _templateVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_templateVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: $ImportLogsTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      entity: $ImportLogsTable.$converterentity.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}entity'],
        )!,
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      totalRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_rows'],
      )!,
      insertedRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}inserted_rows'],
      )!,
      updatedRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_rows'],
      )!,
      failedRows: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed_rows'],
      )!,
      errorDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_detail'],
      ),
      status: $ImportLogsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      importedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}imported_by'],
      )!,
      storedFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stored_file_path'],
      )!,
      fileSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_sha256'],
      )!,
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      )!,
      templateVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_version'],
      )!,
    );
  }

  @override
  $ImportLogsTable createAlias(String alias) {
    return $ImportLogsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncStatus, String> $convertersyncStatus =
      const SyncStatusConverter();
  static TypeConverter<ImportEntity, String> $converterentity =
      const ImportEntityConverter();
  static TypeConverter<ImportStatus, String> $converterstatus =
      const ImportStatusConverter();
}

class ImportLogRow extends DataClass implements Insertable<ImportLogRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  /// Which master entity was imported. Stored as the enum's `dbValue`, which is
  /// the physical table name — so the audit row names the table it touched.
  final ImportEntity entity;

  /// The name the user's file had when they picked it. Not a path.
  final String fileName;

  /// Data rows the workbook held, blank rows and the template's sample row
  /// excluded. Zero is legitimate: an empty-but-valid template is a thing a user
  /// can upload, and an import of nothing is exactly what the audit should say.
  final int totalRows;
  final int insertedRows;
  final int updatedRows;
  final int failedRows;

  /// Structured JSON, one object per issue, deterministically ordered (§32).
  ///
  /// NULL when nothing failed. Never the raw rows: a workbook of users would put
  /// every full name and email into a column that outlives the file.
  final String? errorDetail;
  final ImportStatus status;

  /// Who ran it (G-M6). Never nullable: an import with no actor is not an audit
  /// record.
  final String importedBy;

  /// Absolute path of the retained source copy under app documents (§3.8).
  ///
  /// **Never rendered to a user.** An app-private path tells an administrator
  /// nothing they can act on, and §36 keeps paths out of every screen.
  final String storedFilePath;

  /// Lowercase hex SHA-256 of the source bytes.
  final String fileSha256;
  final int fileSizeBytes;

  /// The template generation the workbook declared, e.g. `aish-master-v1`.
  final String templateVersion;
  const ImportLogRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
    required this.entity,
    required this.fileName,
    required this.totalRows,
    required this.insertedRows,
    required this.updatedRows,
    required this.failedRows,
    this.errorDetail,
    required this.status,
    required this.importedBy,
    required this.storedFilePath,
    required this.fileSha256,
    required this.fileSizeBytes,
    required this.templateVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    {
      map['sync_status'] = Variable<String>(
        $ImportLogsTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    {
      map['entity'] = Variable<String>(
        $ImportLogsTable.$converterentity.toSql(entity),
      );
    }
    map['file_name'] = Variable<String>(fileName);
    map['total_rows'] = Variable<int>(totalRows);
    map['inserted_rows'] = Variable<int>(insertedRows);
    map['updated_rows'] = Variable<int>(updatedRows);
    map['failed_rows'] = Variable<int>(failedRows);
    if (!nullToAbsent || errorDetail != null) {
      map['error_detail'] = Variable<String>(errorDetail);
    }
    {
      map['status'] = Variable<String>(
        $ImportLogsTable.$converterstatus.toSql(status),
      );
    }
    map['imported_by'] = Variable<String>(importedBy);
    map['stored_file_path'] = Variable<String>(storedFilePath);
    map['file_sha256'] = Variable<String>(fileSha256);
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['template_version'] = Variable<String>(templateVersion);
    return map;
  }

  ImportLogsCompanion toCompanion(bool nullToAbsent) {
    return ImportLogsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
      entity: Value(entity),
      fileName: Value(fileName),
      totalRows: Value(totalRows),
      insertedRows: Value(insertedRows),
      updatedRows: Value(updatedRows),
      failedRows: Value(failedRows),
      errorDetail: errorDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(errorDetail),
      status: Value(status),
      importedBy: Value(importedBy),
      storedFilePath: Value(storedFilePath),
      fileSha256: Value(fileSha256),
      fileSizeBytes: Value(fileSizeBytes),
      templateVersion: Value(templateVersion),
    );
  }

  factory ImportLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportLogRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<SyncStatus>(json['syncStatus']),
      entity: serializer.fromJson<ImportEntity>(json['entity']),
      fileName: serializer.fromJson<String>(json['fileName']),
      totalRows: serializer.fromJson<int>(json['totalRows']),
      insertedRows: serializer.fromJson<int>(json['insertedRows']),
      updatedRows: serializer.fromJson<int>(json['updatedRows']),
      failedRows: serializer.fromJson<int>(json['failedRows']),
      errorDetail: serializer.fromJson<String?>(json['errorDetail']),
      status: serializer.fromJson<ImportStatus>(json['status']),
      importedBy: serializer.fromJson<String>(json['importedBy']),
      storedFilePath: serializer.fromJson<String>(json['storedFilePath']),
      fileSha256: serializer.fromJson<String>(json['fileSha256']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      templateVersion: serializer.fromJson<String>(json['templateVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<SyncStatus>(syncStatus),
      'entity': serializer.toJson<ImportEntity>(entity),
      'fileName': serializer.toJson<String>(fileName),
      'totalRows': serializer.toJson<int>(totalRows),
      'insertedRows': serializer.toJson<int>(insertedRows),
      'updatedRows': serializer.toJson<int>(updatedRows),
      'failedRows': serializer.toJson<int>(failedRows),
      'errorDetail': serializer.toJson<String?>(errorDetail),
      'status': serializer.toJson<ImportStatus>(status),
      'importedBy': serializer.toJson<String>(importedBy),
      'storedFilePath': serializer.toJson<String>(storedFilePath),
      'fileSha256': serializer.toJson<String>(fileSha256),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'templateVersion': serializer.toJson<String>(templateVersion),
    };
  }

  ImportLogRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    SyncStatus? syncStatus,
    ImportEntity? entity,
    String? fileName,
    int? totalRows,
    int? insertedRows,
    int? updatedRows,
    int? failedRows,
    Value<String?> errorDetail = const Value.absent(),
    ImportStatus? status,
    String? importedBy,
    String? storedFilePath,
    String? fileSha256,
    int? fileSizeBytes,
    String? templateVersion,
  }) => ImportLogRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    entity: entity ?? this.entity,
    fileName: fileName ?? this.fileName,
    totalRows: totalRows ?? this.totalRows,
    insertedRows: insertedRows ?? this.insertedRows,
    updatedRows: updatedRows ?? this.updatedRows,
    failedRows: failedRows ?? this.failedRows,
    errorDetail: errorDetail.present ? errorDetail.value : this.errorDetail,
    status: status ?? this.status,
    importedBy: importedBy ?? this.importedBy,
    storedFilePath: storedFilePath ?? this.storedFilePath,
    fileSha256: fileSha256 ?? this.fileSha256,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    templateVersion: templateVersion ?? this.templateVersion,
  );
  ImportLogRow copyWithCompanion(ImportLogsCompanion data) {
    return ImportLogRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      entity: data.entity.present ? data.entity.value : this.entity,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      totalRows: data.totalRows.present ? data.totalRows.value : this.totalRows,
      insertedRows: data.insertedRows.present
          ? data.insertedRows.value
          : this.insertedRows,
      updatedRows: data.updatedRows.present
          ? data.updatedRows.value
          : this.updatedRows,
      failedRows: data.failedRows.present
          ? data.failedRows.value
          : this.failedRows,
      errorDetail: data.errorDetail.present
          ? data.errorDetail.value
          : this.errorDetail,
      status: data.status.present ? data.status.value : this.status,
      importedBy: data.importedBy.present
          ? data.importedBy.value
          : this.importedBy,
      storedFilePath: data.storedFilePath.present
          ? data.storedFilePath.value
          : this.storedFilePath,
      fileSha256: data.fileSha256.present
          ? data.fileSha256.value
          : this.fileSha256,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      templateVersion: data.templateVersion.present
          ? data.templateVersion.value
          : this.templateVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportLogRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('entity: $entity, ')
          ..write('fileName: $fileName, ')
          ..write('totalRows: $totalRows, ')
          ..write('insertedRows: $insertedRows, ')
          ..write('updatedRows: $updatedRows, ')
          ..write('failedRows: $failedRows, ')
          ..write('errorDetail: $errorDetail, ')
          ..write('status: $status, ')
          ..write('importedBy: $importedBy, ')
          ..write('storedFilePath: $storedFilePath, ')
          ..write('fileSha256: $fileSha256, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('templateVersion: $templateVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
    entity,
    fileName,
    totalRows,
    insertedRows,
    updatedRows,
    failedRows,
    errorDetail,
    status,
    importedBy,
    storedFilePath,
    fileSha256,
    fileSizeBytes,
    templateVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportLogRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus &&
          other.entity == this.entity &&
          other.fileName == this.fileName &&
          other.totalRows == this.totalRows &&
          other.insertedRows == this.insertedRows &&
          other.updatedRows == this.updatedRows &&
          other.failedRows == this.failedRows &&
          other.errorDetail == this.errorDetail &&
          other.status == this.status &&
          other.importedBy == this.importedBy &&
          other.storedFilePath == this.storedFilePath &&
          other.fileSha256 == this.fileSha256 &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.templateVersion == this.templateVersion);
}

class ImportLogsCompanion extends UpdateCompanion<ImportLogRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<SyncStatus> syncStatus;
  final Value<ImportEntity> entity;
  final Value<String> fileName;
  final Value<int> totalRows;
  final Value<int> insertedRows;
  final Value<int> updatedRows;
  final Value<int> failedRows;
  final Value<String?> errorDetail;
  final Value<ImportStatus> status;
  final Value<String> importedBy;
  final Value<String> storedFilePath;
  final Value<String> fileSha256;
  final Value<int> fileSizeBytes;
  final Value<String> templateVersion;
  final Value<int> rowid;
  const ImportLogsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.entity = const Value.absent(),
    this.fileName = const Value.absent(),
    this.totalRows = const Value.absent(),
    this.insertedRows = const Value.absent(),
    this.updatedRows = const Value.absent(),
    this.failedRows = const Value.absent(),
    this.errorDetail = const Value.absent(),
    this.status = const Value.absent(),
    this.importedBy = const Value.absent(),
    this.storedFilePath = const Value.absent(),
    this.fileSha256 = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.templateVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportLogsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required ImportEntity entity,
    required String fileName,
    required int totalRows,
    required int insertedRows,
    required int updatedRows,
    required int failedRows,
    this.errorDetail = const Value.absent(),
    required ImportStatus status,
    required String importedBy,
    required String storedFilePath,
    required String fileSha256,
    required int fileSizeBytes,
    required String templateVersion,
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       fileName = Value(fileName),
       totalRows = Value(totalRows),
       insertedRows = Value(insertedRows),
       updatedRows = Value(updatedRows),
       failedRows = Value(failedRows),
       status = Value(status),
       importedBy = Value(importedBy),
       storedFilePath = Value(storedFilePath),
       fileSha256 = Value(fileSha256),
       fileSizeBytes = Value(fileSizeBytes),
       templateVersion = Value(templateVersion);
  static Insertable<ImportLogRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<String>? entity,
    Expression<String>? fileName,
    Expression<int>? totalRows,
    Expression<int>? insertedRows,
    Expression<int>? updatedRows,
    Expression<int>? failedRows,
    Expression<String>? errorDetail,
    Expression<String>? status,
    Expression<String>? importedBy,
    Expression<String>? storedFilePath,
    Expression<String>? fileSha256,
    Expression<int>? fileSizeBytes,
    Expression<String>? templateVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (entity != null) 'entity': entity,
      if (fileName != null) 'file_name': fileName,
      if (totalRows != null) 'total_rows': totalRows,
      if (insertedRows != null) 'inserted_rows': insertedRows,
      if (updatedRows != null) 'updated_rows': updatedRows,
      if (failedRows != null) 'failed_rows': failedRows,
      if (errorDetail != null) 'error_detail': errorDetail,
      if (status != null) 'status': status,
      if (importedBy != null) 'imported_by': importedBy,
      if (storedFilePath != null) 'stored_file_path': storedFilePath,
      if (fileSha256 != null) 'file_sha256': fileSha256,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (templateVersion != null) 'template_version': templateVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportLogsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<SyncStatus>? syncStatus,
    Value<ImportEntity>? entity,
    Value<String>? fileName,
    Value<int>? totalRows,
    Value<int>? insertedRows,
    Value<int>? updatedRows,
    Value<int>? failedRows,
    Value<String?>? errorDetail,
    Value<ImportStatus>? status,
    Value<String>? importedBy,
    Value<String>? storedFilePath,
    Value<String>? fileSha256,
    Value<int>? fileSizeBytes,
    Value<String>? templateVersion,
    Value<int>? rowid,
  }) {
    return ImportLogsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      entity: entity ?? this.entity,
      fileName: fileName ?? this.fileName,
      totalRows: totalRows ?? this.totalRows,
      insertedRows: insertedRows ?? this.insertedRows,
      updatedRows: updatedRows ?? this.updatedRows,
      failedRows: failedRows ?? this.failedRows,
      errorDetail: errorDetail ?? this.errorDetail,
      status: status ?? this.status,
      importedBy: importedBy ?? this.importedBy,
      storedFilePath: storedFilePath ?? this.storedFilePath,
      fileSha256: fileSha256 ?? this.fileSha256,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      templateVersion: templateVersion ?? this.templateVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $ImportLogsTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (entity.present) {
      map['entity'] = Variable<String>(
        $ImportLogsTable.$converterentity.toSql(entity.value),
      );
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (totalRows.present) {
      map['total_rows'] = Variable<int>(totalRows.value);
    }
    if (insertedRows.present) {
      map['inserted_rows'] = Variable<int>(insertedRows.value);
    }
    if (updatedRows.present) {
      map['updated_rows'] = Variable<int>(updatedRows.value);
    }
    if (failedRows.present) {
      map['failed_rows'] = Variable<int>(failedRows.value);
    }
    if (errorDetail.present) {
      map['error_detail'] = Variable<String>(errorDetail.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ImportLogsTable.$converterstatus.toSql(status.value),
      );
    }
    if (importedBy.present) {
      map['imported_by'] = Variable<String>(importedBy.value);
    }
    if (storedFilePath.present) {
      map['stored_file_path'] = Variable<String>(storedFilePath.value);
    }
    if (fileSha256.present) {
      map['file_sha256'] = Variable<String>(fileSha256.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (templateVersion.present) {
      map['template_version'] = Variable<String>(templateVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportLogsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('entity: $entity, ')
          ..write('fileName: $fileName, ')
          ..write('totalRows: $totalRows, ')
          ..write('insertedRows: $insertedRows, ')
          ..write('updatedRows: $updatedRows, ')
          ..write('failedRows: $failedRows, ')
          ..write('errorDetail: $errorDetail, ')
          ..write('status: $status, ')
          ..write('importedBy: $importedBy, ')
          ..write('storedFilePath: $storedFilePath, ')
          ..write('fileSha256: $fileSha256, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('templateVersion: $templateVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncDevicesTable extends SyncDevices
    with TableInfo<$SyncDevicesTable, SyncDeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _appInstallIdMeta = const VerificationMeta(
    'appInstallId',
  );
  @override
  late final GeneratedColumn<String> appInstallId = GeneratedColumn<String>(
    'app_install_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayLabelMeta = const VerificationMeta(
    'displayLabel',
  );
  @override
  late final GeneratedColumn<String> displayLabel = GeneratedColumn<String>(
    'display_label',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 128),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    lastSeenAt,
    appInstallId,
    displayLabel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncDeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('app_install_id')) {
      context.handle(
        _appInstallIdMeta,
        appInstallId.isAcceptableOrUnknown(
          data['app_install_id']!,
          _appInstallIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_appInstallIdMeta);
    }
    if (data.containsKey('display_label')) {
      context.handle(
        _displayLabelMeta,
        displayLabel.isAcceptableOrUnknown(
          data['display_label']!,
          _displayLabelMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncDeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncDeviceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
      appInstallId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_install_id'],
      )!,
      displayLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_label'],
      ),
    );
  }

  @override
  $SyncDevicesTable createAlias(String alias) {
    return $SyncDevicesTable(attachedDatabase, alias);
  }
}

class SyncDeviceRow extends DataClass implements Insertable<SyncDeviceRow> {
  final String id;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final String appInstallId;
  final String? displayLabel;
  const SyncDeviceRow({
    required this.id,
    required this.createdAt,
    required this.lastSeenAt,
    required this.appInstallId,
    this.displayLabel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    map['app_install_id'] = Variable<String>(appInstallId);
    if (!nullToAbsent || displayLabel != null) {
      map['display_label'] = Variable<String>(displayLabel);
    }
    return map;
  }

  SyncDevicesCompanion toCompanion(bool nullToAbsent) {
    return SyncDevicesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      lastSeenAt: Value(lastSeenAt),
      appInstallId: Value(appInstallId),
      displayLabel: displayLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(displayLabel),
    );
  }

  factory SyncDeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncDeviceRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
      appInstallId: serializer.fromJson<String>(json['appInstallId']),
      displayLabel: serializer.fromJson<String?>(json['displayLabel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
      'appInstallId': serializer.toJson<String>(appInstallId),
      'displayLabel': serializer.toJson<String?>(displayLabel),
    };
  }

  SyncDeviceRow copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? lastSeenAt,
    String? appInstallId,
    Value<String?> displayLabel = const Value.absent(),
  }) => SyncDeviceRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    appInstallId: appInstallId ?? this.appInstallId,
    displayLabel: displayLabel.present ? displayLabel.value : this.displayLabel,
  );
  SyncDeviceRow copyWithCompanion(SyncDevicesCompanion data) {
    return SyncDeviceRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      appInstallId: data.appInstallId.present
          ? data.appInstallId.value
          : this.appInstallId,
      displayLabel: data.displayLabel.present
          ? data.displayLabel.value
          : this.displayLabel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncDeviceRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('appInstallId: $appInstallId, ')
          ..write('displayLabel: $displayLabel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, createdAt, lastSeenAt, appInstallId, displayLabel);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncDeviceRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.appInstallId == this.appInstallId &&
          other.displayLabel == this.displayLabel);
}

class SyncDevicesCompanion extends UpdateCompanion<SyncDeviceRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastSeenAt;
  final Value<String> appInstallId;
  final Value<String?> displayLabel;
  final Value<int> rowid;
  const SyncDevicesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.appInstallId = const Value.absent(),
    this.displayLabel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncDevicesCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    required String appInstallId,
    this.displayLabel = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : appInstallId = Value(appInstallId);
  static Insertable<SyncDeviceRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastSeenAt,
    Expression<String>? appInstallId,
    Expression<String>? displayLabel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (appInstallId != null) 'app_install_id': appInstallId,
      if (displayLabel != null) 'display_label': displayLabel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncDevicesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastSeenAt,
    Value<String>? appInstallId,
    Value<String?>? displayLabel,
    Value<int>? rowid,
  }) {
    return SyncDevicesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      appInstallId: appInstallId ?? this.appInstallId,
      displayLabel: displayLabel ?? this.displayLabel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (appInstallId.present) {
      map['app_install_id'] = Variable<String>(appInstallId.value);
    }
    if (displayLabel.present) {
      map['display_label'] = Variable<String>(displayLabel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncDevicesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('appInstallId: $appInstallId, ')
          ..write('displayLabel: $displayLabel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sync_devices (id)',
    ),
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorUserIdMeta = const VerificationMeta(
    'actorUserId',
  );
  @override
  late final GeneratedColumn<String> actorUserId = GeneratedColumn<String>(
    'actor_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadVersionMeta = const VerificationMeta(
    'payloadVersion',
  );
  @override
  late final GeneratedColumn<int> payloadVersion = GeneratedColumn<int>(
    'payload_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _baseServerVersionMeta = const VerificationMeta(
    'baseServerVersion',
  );
  @override
  late final GeneratedColumn<int> baseServerVersion = GeneratedColumn<int>(
    'base_server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _occurredAtUtcMeta = const VerificationMeta(
    'occurredAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAtUtc =
      GeneratedColumn<DateTime>(
        'occurred_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _payloadHashMeta = const VerificationMeta(
    'payloadHash',
  );
  @override
  late final GeneratedColumn<String> payloadHash = GeneratedColumn<String>(
    'payload_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptEpochMsMeta =
      const VerificationMeta('nextAttemptEpochMs');
  @override
  late final GeneratedColumn<int> nextAttemptEpochMs = GeneratedColumn<int>(
    'next_attempt_epoch_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _leaseStartedEpochMsMeta =
      const VerificationMeta('leaseStartedEpochMs');
  @override
  late final GeneratedColumn<int> leaseStartedEpochMs = GeneratedColumn<int>(
    'lease_started_epoch_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 96),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMessageMeta = const VerificationMeta(
    'lastErrorMessage',
  );
  @override
  late final GeneratedColumn<String> lastErrorMessage = GeneratedColumn<String>(
    'last_error_message',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 512),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    deviceId,
    operationType,
    aggregateType,
    aggregateId,
    actorUserId,
    payloadVersion,
    baseServerVersion,
    occurredAtUtc,
    payloadHash,
    status,
    attemptCount,
    nextAttemptEpochMs,
    leaseStartedEpochMs,
    lastErrorCode,
    lastErrorMessage,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('actor_user_id')) {
      context.handle(
        _actorUserIdMeta,
        actorUserId.isAcceptableOrUnknown(
          data['actor_user_id']!,
          _actorUserIdMeta,
        ),
      );
    }
    if (data.containsKey('payload_version')) {
      context.handle(
        _payloadVersionMeta,
        payloadVersion.isAcceptableOrUnknown(
          data['payload_version']!,
          _payloadVersionMeta,
        ),
      );
    }
    if (data.containsKey('base_server_version')) {
      context.handle(
        _baseServerVersionMeta,
        baseServerVersion.isAcceptableOrUnknown(
          data['base_server_version']!,
          _baseServerVersionMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at_utc')) {
      context.handle(
        _occurredAtUtcMeta,
        occurredAtUtc.isAcceptableOrUnknown(
          data['occurred_at_utc']!,
          _occurredAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMeta);
    }
    if (data.containsKey('payload_hash')) {
      context.handle(
        _payloadHashMeta,
        payloadHash.isAcceptableOrUnknown(
          data['payload_hash']!,
          _payloadHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadHashMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_epoch_ms')) {
      context.handle(
        _nextAttemptEpochMsMeta,
        nextAttemptEpochMs.isAcceptableOrUnknown(
          data['next_attempt_epoch_ms']!,
          _nextAttemptEpochMsMeta,
        ),
      );
    }
    if (data.containsKey('lease_started_epoch_ms')) {
      context.handle(
        _leaseStartedEpochMsMeta,
        leaseStartedEpochMs.isAcceptableOrUnknown(
          data['lease_started_epoch_ms']!,
          _leaseStartedEpochMsMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_message')) {
      context.handle(
        _lastErrorMessageMeta,
        lastErrorMessage.isAcceptableOrUnknown(
          data['last_error_message']!,
          _lastErrorMessageMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      actorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_user_id'],
      ),
      payloadVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_version'],
      )!,
      baseServerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_server_version'],
      )!,
      occurredAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at_utc'],
      )!,
      payloadHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_hash'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_epoch_ms'],
      )!,
      leaseStartedEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lease_started_epoch_ms'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxRow extends DataClass implements Insertable<SyncOutboxRow> {
  final String id;
  final String requestId;
  final String deviceId;
  final String operationType;
  final String aggregateType;
  final String aggregateId;

  /// Original business actor. Legacy master rows created before schema v14 do
  /// not carry actor provenance, so their permanently blocked reconstruction
  /// deliberately stores NULL instead of inventing an identity.
  final String? actorUserId;
  final int payloadVersion;
  final int baseServerVersion;
  final DateTime occurredAtUtc;
  final String payloadHash;
  final String status;
  final int attemptCount;
  final int nextAttemptEpochMs;
  final int? leaseStartedEpochMs;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SyncOutboxRow({
    required this.id,
    required this.requestId,
    required this.deviceId,
    required this.operationType,
    required this.aggregateType,
    required this.aggregateId,
    this.actorUserId,
    required this.payloadVersion,
    required this.baseServerVersion,
    required this.occurredAtUtc,
    required this.payloadHash,
    required this.status,
    required this.attemptCount,
    required this.nextAttemptEpochMs,
    this.leaseStartedEpochMs,
    this.lastErrorCode,
    this.lastErrorMessage,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['request_id'] = Variable<String>(requestId);
    map['device_id'] = Variable<String>(deviceId);
    map['operation_type'] = Variable<String>(operationType);
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    if (!nullToAbsent || actorUserId != null) {
      map['actor_user_id'] = Variable<String>(actorUserId);
    }
    map['payload_version'] = Variable<int>(payloadVersion);
    map['base_server_version'] = Variable<int>(baseServerVersion);
    map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc);
    map['payload_hash'] = Variable<String>(payloadHash);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['next_attempt_epoch_ms'] = Variable<int>(nextAttemptEpochMs);
    if (!nullToAbsent || leaseStartedEpochMs != null) {
      map['lease_started_epoch_ms'] = Variable<int>(leaseStartedEpochMs);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorMessage != null) {
      map['last_error_message'] = Variable<String>(lastErrorMessage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      requestId: Value(requestId),
      deviceId: Value(deviceId),
      operationType: Value(operationType),
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      actorUserId: actorUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(actorUserId),
      payloadVersion: Value(payloadVersion),
      baseServerVersion: Value(baseServerVersion),
      occurredAtUtc: Value(occurredAtUtc),
      payloadHash: Value(payloadHash),
      status: Value(status),
      attemptCount: Value(attemptCount),
      nextAttemptEpochMs: Value(nextAttemptEpochMs),
      leaseStartedEpochMs: leaseStartedEpochMs == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseStartedEpochMs),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorMessage: lastErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorMessage),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxRow(
      id: serializer.fromJson<String>(json['id']),
      requestId: serializer.fromJson<String>(json['requestId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      actorUserId: serializer.fromJson<String?>(json['actorUserId']),
      payloadVersion: serializer.fromJson<int>(json['payloadVersion']),
      baseServerVersion: serializer.fromJson<int>(json['baseServerVersion']),
      occurredAtUtc: serializer.fromJson<DateTime>(json['occurredAtUtc']),
      payloadHash: serializer.fromJson<String>(json['payloadHash']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptEpochMs: serializer.fromJson<int>(json['nextAttemptEpochMs']),
      leaseStartedEpochMs: serializer.fromJson<int?>(
        json['leaseStartedEpochMs'],
      ),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorMessage: serializer.fromJson<String?>(json['lastErrorMessage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'requestId': serializer.toJson<String>(requestId),
      'deviceId': serializer.toJson<String>(deviceId),
      'operationType': serializer.toJson<String>(operationType),
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'actorUserId': serializer.toJson<String?>(actorUserId),
      'payloadVersion': serializer.toJson<int>(payloadVersion),
      'baseServerVersion': serializer.toJson<int>(baseServerVersion),
      'occurredAtUtc': serializer.toJson<DateTime>(occurredAtUtc),
      'payloadHash': serializer.toJson<String>(payloadHash),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptEpochMs': serializer.toJson<int>(nextAttemptEpochMs),
      'leaseStartedEpochMs': serializer.toJson<int?>(leaseStartedEpochMs),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorMessage': serializer.toJson<String?>(lastErrorMessage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncOutboxRow copyWith({
    String? id,
    String? requestId,
    String? deviceId,
    String? operationType,
    String? aggregateType,
    String? aggregateId,
    Value<String?> actorUserId = const Value.absent(),
    int? payloadVersion,
    int? baseServerVersion,
    DateTime? occurredAtUtc,
    String? payloadHash,
    String? status,
    int? attemptCount,
    int? nextAttemptEpochMs,
    Value<int?> leaseStartedEpochMs = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorMessage = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SyncOutboxRow(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    deviceId: deviceId ?? this.deviceId,
    operationType: operationType ?? this.operationType,
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    actorUserId: actorUserId.present ? actorUserId.value : this.actorUserId,
    payloadVersion: payloadVersion ?? this.payloadVersion,
    baseServerVersion: baseServerVersion ?? this.baseServerVersion,
    occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
    payloadHash: payloadHash ?? this.payloadHash,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptEpochMs: nextAttemptEpochMs ?? this.nextAttemptEpochMs,
    leaseStartedEpochMs: leaseStartedEpochMs.present
        ? leaseStartedEpochMs.value
        : this.leaseStartedEpochMs,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorMessage: lastErrorMessage.present
        ? lastErrorMessage.value
        : this.lastErrorMessage,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncOutboxRow copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxRow(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      actorUserId: data.actorUserId.present
          ? data.actorUserId.value
          : this.actorUserId,
      payloadVersion: data.payloadVersion.present
          ? data.payloadVersion.value
          : this.payloadVersion,
      baseServerVersion: data.baseServerVersion.present
          ? data.baseServerVersion.value
          : this.baseServerVersion,
      occurredAtUtc: data.occurredAtUtc.present
          ? data.occurredAtUtc.value
          : this.occurredAtUtc,
      payloadHash: data.payloadHash.present
          ? data.payloadHash.value
          : this.payloadHash,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptEpochMs: data.nextAttemptEpochMs.present
          ? data.nextAttemptEpochMs.value
          : this.nextAttemptEpochMs,
      leaseStartedEpochMs: data.leaseStartedEpochMs.present
          ? data.leaseStartedEpochMs.value
          : this.leaseStartedEpochMs,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorMessage: data.lastErrorMessage.present
          ? data.lastErrorMessage.value
          : this.lastErrorMessage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxRow(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('deviceId: $deviceId, ')
          ..write('operationType: $operationType, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('baseServerVersion: $baseServerVersion, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptEpochMs: $nextAttemptEpochMs, ')
          ..write('leaseStartedEpochMs: $leaseStartedEpochMs, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    requestId,
    deviceId,
    operationType,
    aggregateType,
    aggregateId,
    actorUserId,
    payloadVersion,
    baseServerVersion,
    occurredAtUtc,
    payloadHash,
    status,
    attemptCount,
    nextAttemptEpochMs,
    leaseStartedEpochMs,
    lastErrorCode,
    lastErrorMessage,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxRow &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.deviceId == this.deviceId &&
          other.operationType == this.operationType &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.actorUserId == this.actorUserId &&
          other.payloadVersion == this.payloadVersion &&
          other.baseServerVersion == this.baseServerVersion &&
          other.occurredAtUtc == this.occurredAtUtc &&
          other.payloadHash == this.payloadHash &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptEpochMs == this.nextAttemptEpochMs &&
          other.leaseStartedEpochMs == this.leaseStartedEpochMs &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorMessage == this.lastErrorMessage &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxRow> {
  final Value<String> id;
  final Value<String> requestId;
  final Value<String> deviceId;
  final Value<String> operationType;
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<String?> actorUserId;
  final Value<int> payloadVersion;
  final Value<int> baseServerVersion;
  final Value<DateTime> occurredAtUtc;
  final Value<String> payloadHash;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<int> nextAttemptEpochMs;
  final Value<int?> leaseStartedEpochMs;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorMessage;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.actorUserId = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.baseServerVersion = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.payloadHash = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptEpochMs = const Value.absent(),
    this.leaseStartedEpochMs = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String requestId,
    required String deviceId,
    required String operationType,
    required String aggregateType,
    required String aggregateId,
    this.actorUserId = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.baseServerVersion = const Value.absent(),
    required DateTime occurredAtUtc,
    required String payloadHash,
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptEpochMs = const Value.absent(),
    this.leaseStartedEpochMs = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : requestId = Value(requestId),
       deviceId = Value(deviceId),
       operationType = Value(operationType),
       aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId),
       occurredAtUtc = Value(occurredAtUtc),
       payloadHash = Value(payloadHash);
  static Insertable<SyncOutboxRow> custom({
    Expression<String>? id,
    Expression<String>? requestId,
    Expression<String>? deviceId,
    Expression<String>? operationType,
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<String>? actorUserId,
    Expression<int>? payloadVersion,
    Expression<int>? baseServerVersion,
    Expression<DateTime>? occurredAtUtc,
    Expression<String>? payloadHash,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<int>? nextAttemptEpochMs,
    Expression<int>? leaseStartedEpochMs,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorMessage,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (deviceId != null) 'device_id': deviceId,
      if (operationType != null) 'operation_type': operationType,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (payloadVersion != null) 'payload_version': payloadVersion,
      if (baseServerVersion != null) 'base_server_version': baseServerVersion,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (payloadHash != null) 'payload_hash': payloadHash,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptEpochMs != null)
        'next_attempt_epoch_ms': nextAttemptEpochMs,
      if (leaseStartedEpochMs != null)
        'lease_started_epoch_ms': leaseStartedEpochMs,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? id,
    Value<String>? requestId,
    Value<String>? deviceId,
    Value<String>? operationType,
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<String?>? actorUserId,
    Value<int>? payloadVersion,
    Value<int>? baseServerVersion,
    Value<DateTime>? occurredAtUtc,
    Value<String>? payloadHash,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<int>? nextAttemptEpochMs,
    Value<int?>? leaseStartedEpochMs,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorMessage,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      deviceId: deviceId ?? this.deviceId,
      operationType: operationType ?? this.operationType,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      actorUserId: actorUserId ?? this.actorUserId,
      payloadVersion: payloadVersion ?? this.payloadVersion,
      baseServerVersion: baseServerVersion ?? this.baseServerVersion,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      payloadHash: payloadHash ?? this.payloadHash,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptEpochMs: nextAttemptEpochMs ?? this.nextAttemptEpochMs,
      leaseStartedEpochMs: leaseStartedEpochMs ?? this.leaseStartedEpochMs,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (actorUserId.present) {
      map['actor_user_id'] = Variable<String>(actorUserId.value);
    }
    if (payloadVersion.present) {
      map['payload_version'] = Variable<int>(payloadVersion.value);
    }
    if (baseServerVersion.present) {
      map['base_server_version'] = Variable<int>(baseServerVersion.value);
    }
    if (occurredAtUtc.present) {
      map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc.value);
    }
    if (payloadHash.present) {
      map['payload_hash'] = Variable<String>(payloadHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptEpochMs.present) {
      map['next_attempt_epoch_ms'] = Variable<int>(nextAttemptEpochMs.value);
    }
    if (leaseStartedEpochMs.present) {
      map['lease_started_epoch_ms'] = Variable<int>(leaseStartedEpochMs.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorMessage.present) {
      map['last_error_message'] = Variable<String>(lastErrorMessage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('deviceId: $deviceId, ')
          ..write('operationType: $operationType, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('baseServerVersion: $baseServerVersion, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptEpochMs: $nextAttemptEpochMs, ')
          ..write('leaseStartedEpochMs: $leaseStartedEpochMs, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncEntityStatesTable extends SyncEntityStates
    with TableInfo<$SyncEntityStatesTable, SyncEntityStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncEntityStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverUpdatedAtUtcMeta =
      const VerificationMeta('serverUpdatedAtUtc');
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAtUtc =
      GeneratedColumn<DateTime>(
        'server_updated_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSyncedPayloadHashMeta =
      const VerificationMeta('lastSyncedPayloadHash');
  @override
  late final GeneratedColumn<String> lastSyncedPayloadHash =
      GeneratedColumn<String>(
        'last_synced_payload_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSyncedRequestIdMeta =
      const VerificationMeta('lastSyncedRequestId');
  @override
  late final GeneratedColumn<String> lastSyncedRequestId =
      GeneratedColumn<String>(
        'last_synced_request_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    aggregateType,
    aggregateId,
    serverVersion,
    serverUpdatedAtUtc,
    lastSyncedPayloadHash,
    lastSyncedRequestId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_entity_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncEntityStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at_utc')) {
      context.handle(
        _serverUpdatedAtUtcMeta,
        serverUpdatedAtUtc.isAcceptableOrUnknown(
          data['server_updated_at_utc']!,
          _serverUpdatedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_payload_hash')) {
      context.handle(
        _lastSyncedPayloadHashMeta,
        lastSyncedPayloadHash.isAcceptableOrUnknown(
          data['last_synced_payload_hash']!,
          _lastSyncedPayloadHashMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_request_id')) {
      context.handle(
        _lastSyncedRequestIdMeta,
        lastSyncedRequestId.isAcceptableOrUnknown(
          data['last_synced_request_id']!,
          _lastSyncedRequestIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncEntityStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncEntityStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
      serverUpdatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at_utc'],
      ),
      lastSyncedPayloadHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_synced_payload_hash'],
      ),
      lastSyncedRequestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_synced_request_id'],
      ),
    );
  }

  @override
  $SyncEntityStatesTable createAlias(String alias) {
    return $SyncEntityStatesTable(attachedDatabase, alias);
  }
}

class SyncEntityStateRow extends DataClass
    implements Insertable<SyncEntityStateRow> {
  final String id;
  final String aggregateType;
  final String aggregateId;
  final int serverVersion;
  final DateTime? serverUpdatedAtUtc;
  final String? lastSyncedPayloadHash;
  final String? lastSyncedRequestId;
  const SyncEntityStateRow({
    required this.id,
    required this.aggregateType,
    required this.aggregateId,
    required this.serverVersion,
    this.serverUpdatedAtUtc,
    this.lastSyncedPayloadHash,
    this.lastSyncedRequestId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['server_version'] = Variable<int>(serverVersion);
    if (!nullToAbsent || serverUpdatedAtUtc != null) {
      map['server_updated_at_utc'] = Variable<DateTime>(serverUpdatedAtUtc);
    }
    if (!nullToAbsent || lastSyncedPayloadHash != null) {
      map['last_synced_payload_hash'] = Variable<String>(lastSyncedPayloadHash);
    }
    if (!nullToAbsent || lastSyncedRequestId != null) {
      map['last_synced_request_id'] = Variable<String>(lastSyncedRequestId);
    }
    return map;
  }

  SyncEntityStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncEntityStatesCompanion(
      id: Value(id),
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      serverVersion: Value(serverVersion),
      serverUpdatedAtUtc: serverUpdatedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAtUtc),
      lastSyncedPayloadHash: lastSyncedPayloadHash == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedPayloadHash),
      lastSyncedRequestId: lastSyncedRequestId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedRequestId),
    );
  }

  factory SyncEntityStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncEntityStateRow(
      id: serializer.fromJson<String>(json['id']),
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      serverUpdatedAtUtc: serializer.fromJson<DateTime?>(
        json['serverUpdatedAtUtc'],
      ),
      lastSyncedPayloadHash: serializer.fromJson<String?>(
        json['lastSyncedPayloadHash'],
      ),
      lastSyncedRequestId: serializer.fromJson<String?>(
        json['lastSyncedRequestId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'serverUpdatedAtUtc': serializer.toJson<DateTime?>(serverUpdatedAtUtc),
      'lastSyncedPayloadHash': serializer.toJson<String?>(
        lastSyncedPayloadHash,
      ),
      'lastSyncedRequestId': serializer.toJson<String?>(lastSyncedRequestId),
    };
  }

  SyncEntityStateRow copyWith({
    String? id,
    String? aggregateType,
    String? aggregateId,
    int? serverVersion,
    Value<DateTime?> serverUpdatedAtUtc = const Value.absent(),
    Value<String?> lastSyncedPayloadHash = const Value.absent(),
    Value<String?> lastSyncedRequestId = const Value.absent(),
  }) => SyncEntityStateRow(
    id: id ?? this.id,
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    serverVersion: serverVersion ?? this.serverVersion,
    serverUpdatedAtUtc: serverUpdatedAtUtc.present
        ? serverUpdatedAtUtc.value
        : this.serverUpdatedAtUtc,
    lastSyncedPayloadHash: lastSyncedPayloadHash.present
        ? lastSyncedPayloadHash.value
        : this.lastSyncedPayloadHash,
    lastSyncedRequestId: lastSyncedRequestId.present
        ? lastSyncedRequestId.value
        : this.lastSyncedRequestId,
  );
  SyncEntityStateRow copyWithCompanion(SyncEntityStatesCompanion data) {
    return SyncEntityStateRow(
      id: data.id.present ? data.id.value : this.id,
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      serverUpdatedAtUtc: data.serverUpdatedAtUtc.present
          ? data.serverUpdatedAtUtc.value
          : this.serverUpdatedAtUtc,
      lastSyncedPayloadHash: data.lastSyncedPayloadHash.present
          ? data.lastSyncedPayloadHash.value
          : this.lastSyncedPayloadHash,
      lastSyncedRequestId: data.lastSyncedRequestId.present
          ? data.lastSyncedRequestId.value
          : this.lastSyncedRequestId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntityStateRow(')
          ..write('id: $id, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverUpdatedAtUtc: $serverUpdatedAtUtc, ')
          ..write('lastSyncedPayloadHash: $lastSyncedPayloadHash, ')
          ..write('lastSyncedRequestId: $lastSyncedRequestId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    aggregateType,
    aggregateId,
    serverVersion,
    serverUpdatedAtUtc,
    lastSyncedPayloadHash,
    lastSyncedRequestId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncEntityStateRow &&
          other.id == this.id &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.serverVersion == this.serverVersion &&
          other.serverUpdatedAtUtc == this.serverUpdatedAtUtc &&
          other.lastSyncedPayloadHash == this.lastSyncedPayloadHash &&
          other.lastSyncedRequestId == this.lastSyncedRequestId);
}

class SyncEntityStatesCompanion extends UpdateCompanion<SyncEntityStateRow> {
  final Value<String> id;
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<int> serverVersion;
  final Value<DateTime?> serverUpdatedAtUtc;
  final Value<String?> lastSyncedPayloadHash;
  final Value<String?> lastSyncedRequestId;
  final Value<int> rowid;
  const SyncEntityStatesCompanion({
    this.id = const Value.absent(),
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.serverUpdatedAtUtc = const Value.absent(),
    this.lastSyncedPayloadHash = const Value.absent(),
    this.lastSyncedRequestId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncEntityStatesCompanion.insert({
    this.id = const Value.absent(),
    required String aggregateType,
    required String aggregateId,
    this.serverVersion = const Value.absent(),
    this.serverUpdatedAtUtc = const Value.absent(),
    this.lastSyncedPayloadHash = const Value.absent(),
    this.lastSyncedRequestId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId);
  static Insertable<SyncEntityStateRow> custom({
    Expression<String>? id,
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<int>? serverVersion,
    Expression<DateTime>? serverUpdatedAtUtc,
    Expression<String>? lastSyncedPayloadHash,
    Expression<String>? lastSyncedRequestId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (serverVersion != null) 'server_version': serverVersion,
      if (serverUpdatedAtUtc != null)
        'server_updated_at_utc': serverUpdatedAtUtc,
      if (lastSyncedPayloadHash != null)
        'last_synced_payload_hash': lastSyncedPayloadHash,
      if (lastSyncedRequestId != null)
        'last_synced_request_id': lastSyncedRequestId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncEntityStatesCompanion copyWith({
    Value<String>? id,
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<int>? serverVersion,
    Value<DateTime?>? serverUpdatedAtUtc,
    Value<String?>? lastSyncedPayloadHash,
    Value<String?>? lastSyncedRequestId,
    Value<int>? rowid,
  }) {
    return SyncEntityStatesCompanion(
      id: id ?? this.id,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      serverVersion: serverVersion ?? this.serverVersion,
      serverUpdatedAtUtc: serverUpdatedAtUtc ?? this.serverUpdatedAtUtc,
      lastSyncedPayloadHash:
          lastSyncedPayloadHash ?? this.lastSyncedPayloadHash,
      lastSyncedRequestId: lastSyncedRequestId ?? this.lastSyncedRequestId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (serverUpdatedAtUtc.present) {
      map['server_updated_at_utc'] = Variable<DateTime>(
        serverUpdatedAtUtc.value,
      );
    }
    if (lastSyncedPayloadHash.present) {
      map['last_synced_payload_hash'] = Variable<String>(
        lastSyncedPayloadHash.value,
      );
    }
    if (lastSyncedRequestId.present) {
      map['last_synced_request_id'] = Variable<String>(
        lastSyncedRequestId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntityStatesCompanion(')
          ..write('id: $id, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverUpdatedAtUtc: $serverUpdatedAtUtc, ')
          ..write('lastSyncedPayloadHash: $lastSyncedPayloadHash, ')
          ..write('lastSyncedRequestId: $lastSyncedRequestId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncAttemptLogsTable extends SyncAttemptLogs
    with TableInfo<$SyncAttemptLogsTable, SyncAttemptLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncAttemptLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptNumberMeta = const VerificationMeta(
    'attemptNumber',
  );
  @override
  late final GeneratedColumn<int> attemptNumber = GeneratedColumn<int>(
    'attempt_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _httpStatusMeta = const VerificationMeta(
    'httpStatus',
  );
  @override
  late final GeneratedColumn<int> httpStatus = GeneratedColumn<int>(
    'http_status',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _safeErrorCodeMeta = const VerificationMeta(
    'safeErrorCode',
  );
  @override
  late final GeneratedColumn<String> safeErrorCode = GeneratedColumn<String>(
    'safe_error_code',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 96),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _safeErrorMessageMeta = const VerificationMeta(
    'safeErrorMessage',
  );
  @override
  late final GeneratedColumn<String> safeErrorMessage = GeneratedColumn<String>(
    'safe_error_message',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 512),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    attemptNumber,
    startedAt,
    finishedAt,
    outcome,
    httpStatus,
    safeErrorCode,
    safeErrorMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_attempt_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncAttemptLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('attempt_number')) {
      context.handle(
        _attemptNumberMeta,
        attemptNumber.isAcceptableOrUnknown(
          data['attempt_number']!,
          _attemptNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attemptNumberMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_finishedAtMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('http_status')) {
      context.handle(
        _httpStatusMeta,
        httpStatus.isAcceptableOrUnknown(data['http_status']!, _httpStatusMeta),
      );
    }
    if (data.containsKey('safe_error_code')) {
      context.handle(
        _safeErrorCodeMeta,
        safeErrorCode.isAcceptableOrUnknown(
          data['safe_error_code']!,
          _safeErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('safe_error_message')) {
      context.handle(
        _safeErrorMessageMeta,
        safeErrorMessage.isAcceptableOrUnknown(
          data['safe_error_message']!,
          _safeErrorMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncAttemptLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncAttemptLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      attemptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_number'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      httpStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}http_status'],
      ),
      safeErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safe_error_code'],
      ),
      safeErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safe_error_message'],
      ),
    );
  }

  @override
  $SyncAttemptLogsTable createAlias(String alias) {
    return $SyncAttemptLogsTable(attachedDatabase, alias);
  }
}

class SyncAttemptLogRow extends DataClass
    implements Insertable<SyncAttemptLogRow> {
  final String id;
  final String requestId;
  final int attemptNumber;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String outcome;
  final int? httpStatus;
  final String? safeErrorCode;
  final String? safeErrorMessage;
  const SyncAttemptLogRow({
    required this.id,
    required this.requestId,
    required this.attemptNumber,
    required this.startedAt,
    required this.finishedAt,
    required this.outcome,
    this.httpStatus,
    this.safeErrorCode,
    this.safeErrorMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['request_id'] = Variable<String>(requestId);
    map['attempt_number'] = Variable<int>(attemptNumber);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['finished_at'] = Variable<DateTime>(finishedAt);
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || httpStatus != null) {
      map['http_status'] = Variable<int>(httpStatus);
    }
    if (!nullToAbsent || safeErrorCode != null) {
      map['safe_error_code'] = Variable<String>(safeErrorCode);
    }
    if (!nullToAbsent || safeErrorMessage != null) {
      map['safe_error_message'] = Variable<String>(safeErrorMessage);
    }
    return map;
  }

  SyncAttemptLogsCompanion toCompanion(bool nullToAbsent) {
    return SyncAttemptLogsCompanion(
      id: Value(id),
      requestId: Value(requestId),
      attemptNumber: Value(attemptNumber),
      startedAt: Value(startedAt),
      finishedAt: Value(finishedAt),
      outcome: Value(outcome),
      httpStatus: httpStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(httpStatus),
      safeErrorCode: safeErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(safeErrorCode),
      safeErrorMessage: safeErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(safeErrorMessage),
    );
  }

  factory SyncAttemptLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncAttemptLogRow(
      id: serializer.fromJson<String>(json['id']),
      requestId: serializer.fromJson<String>(json['requestId']),
      attemptNumber: serializer.fromJson<int>(json['attemptNumber']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime>(json['finishedAt']),
      outcome: serializer.fromJson<String>(json['outcome']),
      httpStatus: serializer.fromJson<int?>(json['httpStatus']),
      safeErrorCode: serializer.fromJson<String?>(json['safeErrorCode']),
      safeErrorMessage: serializer.fromJson<String?>(json['safeErrorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'requestId': serializer.toJson<String>(requestId),
      'attemptNumber': serializer.toJson<int>(attemptNumber),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime>(finishedAt),
      'outcome': serializer.toJson<String>(outcome),
      'httpStatus': serializer.toJson<int?>(httpStatus),
      'safeErrorCode': serializer.toJson<String?>(safeErrorCode),
      'safeErrorMessage': serializer.toJson<String?>(safeErrorMessage),
    };
  }

  SyncAttemptLogRow copyWith({
    String? id,
    String? requestId,
    int? attemptNumber,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? outcome,
    Value<int?> httpStatus = const Value.absent(),
    Value<String?> safeErrorCode = const Value.absent(),
    Value<String?> safeErrorMessage = const Value.absent(),
  }) => SyncAttemptLogRow(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    attemptNumber: attemptNumber ?? this.attemptNumber,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    outcome: outcome ?? this.outcome,
    httpStatus: httpStatus.present ? httpStatus.value : this.httpStatus,
    safeErrorCode: safeErrorCode.present
        ? safeErrorCode.value
        : this.safeErrorCode,
    safeErrorMessage: safeErrorMessage.present
        ? safeErrorMessage.value
        : this.safeErrorMessage,
  );
  SyncAttemptLogRow copyWithCompanion(SyncAttemptLogsCompanion data) {
    return SyncAttemptLogRow(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      attemptNumber: data.attemptNumber.present
          ? data.attemptNumber.value
          : this.attemptNumber,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      httpStatus: data.httpStatus.present
          ? data.httpStatus.value
          : this.httpStatus,
      safeErrorCode: data.safeErrorCode.present
          ? data.safeErrorCode.value
          : this.safeErrorCode,
      safeErrorMessage: data.safeErrorMessage.present
          ? data.safeErrorMessage.value
          : this.safeErrorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncAttemptLogRow(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('outcome: $outcome, ')
          ..write('httpStatus: $httpStatus, ')
          ..write('safeErrorCode: $safeErrorCode, ')
          ..write('safeErrorMessage: $safeErrorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    requestId,
    attemptNumber,
    startedAt,
    finishedAt,
    outcome,
    httpStatus,
    safeErrorCode,
    safeErrorMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncAttemptLogRow &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.attemptNumber == this.attemptNumber &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.outcome == this.outcome &&
          other.httpStatus == this.httpStatus &&
          other.safeErrorCode == this.safeErrorCode &&
          other.safeErrorMessage == this.safeErrorMessage);
}

class SyncAttemptLogsCompanion extends UpdateCompanion<SyncAttemptLogRow> {
  final Value<String> id;
  final Value<String> requestId;
  final Value<int> attemptNumber;
  final Value<DateTime> startedAt;
  final Value<DateTime> finishedAt;
  final Value<String> outcome;
  final Value<int?> httpStatus;
  final Value<String?> safeErrorCode;
  final Value<String?> safeErrorMessage;
  final Value<int> rowid;
  const SyncAttemptLogsCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.attemptNumber = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.outcome = const Value.absent(),
    this.httpStatus = const Value.absent(),
    this.safeErrorCode = const Value.absent(),
    this.safeErrorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncAttemptLogsCompanion.insert({
    this.id = const Value.absent(),
    required String requestId,
    required int attemptNumber,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String outcome,
    this.httpStatus = const Value.absent(),
    this.safeErrorCode = const Value.absent(),
    this.safeErrorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : requestId = Value(requestId),
       attemptNumber = Value(attemptNumber),
       startedAt = Value(startedAt),
       finishedAt = Value(finishedAt),
       outcome = Value(outcome);
  static Insertable<SyncAttemptLogRow> custom({
    Expression<String>? id,
    Expression<String>? requestId,
    Expression<int>? attemptNumber,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<String>? outcome,
    Expression<int>? httpStatus,
    Expression<String>? safeErrorCode,
    Expression<String>? safeErrorMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (attemptNumber != null) 'attempt_number': attemptNumber,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (outcome != null) 'outcome': outcome,
      if (httpStatus != null) 'http_status': httpStatus,
      if (safeErrorCode != null) 'safe_error_code': safeErrorCode,
      if (safeErrorMessage != null) 'safe_error_message': safeErrorMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncAttemptLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? requestId,
    Value<int>? attemptNumber,
    Value<DateTime>? startedAt,
    Value<DateTime>? finishedAt,
    Value<String>? outcome,
    Value<int?>? httpStatus,
    Value<String?>? safeErrorCode,
    Value<String?>? safeErrorMessage,
    Value<int>? rowid,
  }) {
    return SyncAttemptLogsCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      outcome: outcome ?? this.outcome,
      httpStatus: httpStatus ?? this.httpStatus,
      safeErrorCode: safeErrorCode ?? this.safeErrorCode,
      safeErrorMessage: safeErrorMessage ?? this.safeErrorMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (attemptNumber.present) {
      map['attempt_number'] = Variable<int>(attemptNumber.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (httpStatus.present) {
      map['http_status'] = Variable<int>(httpStatus.value);
    }
    if (safeErrorCode.present) {
      map['safe_error_code'] = Variable<String>(safeErrorCode.value);
    }
    if (safeErrorMessage.present) {
      map['safe_error_message'] = Variable<String>(safeErrorMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncAttemptLogsCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('outcome: $outcome, ')
          ..write('httpStatus: $httpStatus, ')
          ..write('safeErrorCode: $safeErrorCode, ')
          ..write('safeErrorMessage: $safeErrorMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictLogsTable extends SyncConflictLogs
    with TableInfo<$SyncConflictLogsTable, SyncConflictLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conflictCodeMeta = const VerificationMeta(
    'conflictCode',
  );
  @override
  late final GeneratedColumn<String> conflictCode = GeneratedColumn<String>(
    'conflict_code',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 96,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _safeDetailJsonMeta = const VerificationMeta(
    'safeDetailJson',
  );
  @override
  late final GeneratedColumn<String> safeDetailJson = GeneratedColumn<String>(
    'safe_detail_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _detectedAtMeta = const VerificationMeta(
    'detectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> detectedAt = GeneratedColumn<DateTime>(
    'detected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 64),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    aggregateType,
    aggregateId,
    operationType,
    conflictCode,
    baseVersion,
    serverVersion,
    safeDetailJson,
    detectedAt,
    resolvedAt,
    resolution,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflict_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflictLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('conflict_code')) {
      context.handle(
        _conflictCodeMeta,
        conflictCode.isAcceptableOrUnknown(
          data['conflict_code']!,
          _conflictCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conflictCodeMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseVersionMeta);
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('safe_detail_json')) {
      context.handle(
        _safeDetailJsonMeta,
        safeDetailJson.isAcceptableOrUnknown(
          data['safe_detail_json']!,
          _safeDetailJsonMeta,
        ),
      );
    }
    if (data.containsKey('detected_at')) {
      context.handle(
        _detectedAtMeta,
        detectedAt.isAcceptableOrUnknown(data['detected_at']!, _detectedAtMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflictLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflictLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      conflictCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_code'],
      )!,
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
      safeDetailJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safe_detail_json'],
      )!,
      detectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}detected_at'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
    );
  }

  @override
  $SyncConflictLogsTable createAlias(String alias) {
    return $SyncConflictLogsTable(attachedDatabase, alias);
  }
}

class SyncConflictLogRow extends DataClass
    implements Insertable<SyncConflictLogRow> {
  final String id;
  final String requestId;
  final String aggregateType;
  final String aggregateId;
  final String operationType;
  final String conflictCode;
  final int baseVersion;
  final int? serverVersion;
  final String safeDetailJson;
  final DateTime detectedAt;
  final DateTime? resolvedAt;
  final String? resolution;
  const SyncConflictLogRow({
    required this.id,
    required this.requestId,
    required this.aggregateType,
    required this.aggregateId,
    required this.operationType,
    required this.conflictCode,
    required this.baseVersion,
    this.serverVersion,
    required this.safeDetailJson,
    required this.detectedAt,
    this.resolvedAt,
    this.resolution,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['request_id'] = Variable<String>(requestId);
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['operation_type'] = Variable<String>(operationType);
    map['conflict_code'] = Variable<String>(conflictCode);
    map['base_version'] = Variable<int>(baseVersion);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    map['safe_detail_json'] = Variable<String>(safeDetailJson);
    map['detected_at'] = Variable<DateTime>(detectedAt);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    return map;
  }

  SyncConflictLogsCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictLogsCompanion(
      id: Value(id),
      requestId: Value(requestId),
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      operationType: Value(operationType),
      conflictCode: Value(conflictCode),
      baseVersion: Value(baseVersion),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      safeDetailJson: Value(safeDetailJson),
      detectedAt: Value(detectedAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
    );
  }

  factory SyncConflictLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflictLogRow(
      id: serializer.fromJson<String>(json['id']),
      requestId: serializer.fromJson<String>(json['requestId']),
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      conflictCode: serializer.fromJson<String>(json['conflictCode']),
      baseVersion: serializer.fromJson<int>(json['baseVersion']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
      safeDetailJson: serializer.fromJson<String>(json['safeDetailJson']),
      detectedAt: serializer.fromJson<DateTime>(json['detectedAt']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
      resolution: serializer.fromJson<String?>(json['resolution']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'requestId': serializer.toJson<String>(requestId),
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'operationType': serializer.toJson<String>(operationType),
      'conflictCode': serializer.toJson<String>(conflictCode),
      'baseVersion': serializer.toJson<int>(baseVersion),
      'serverVersion': serializer.toJson<int?>(serverVersion),
      'safeDetailJson': serializer.toJson<String>(safeDetailJson),
      'detectedAt': serializer.toJson<DateTime>(detectedAt),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
      'resolution': serializer.toJson<String?>(resolution),
    };
  }

  SyncConflictLogRow copyWith({
    String? id,
    String? requestId,
    String? aggregateType,
    String? aggregateId,
    String? operationType,
    String? conflictCode,
    int? baseVersion,
    Value<int?> serverVersion = const Value.absent(),
    String? safeDetailJson,
    DateTime? detectedAt,
    Value<DateTime?> resolvedAt = const Value.absent(),
    Value<String?> resolution = const Value.absent(),
  }) => SyncConflictLogRow(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    operationType: operationType ?? this.operationType,
    conflictCode: conflictCode ?? this.conflictCode,
    baseVersion: baseVersion ?? this.baseVersion,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    safeDetailJson: safeDetailJson ?? this.safeDetailJson,
    detectedAt: detectedAt ?? this.detectedAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    resolution: resolution.present ? resolution.value : this.resolution,
  );
  SyncConflictLogRow copyWithCompanion(SyncConflictLogsCompanion data) {
    return SyncConflictLogRow(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      conflictCode: data.conflictCode.present
          ? data.conflictCode.value
          : this.conflictCode,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      safeDetailJson: data.safeDetailJson.present
          ? data.safeDetailJson.value
          : this.safeDetailJson,
      detectedAt: data.detectedAt.present
          ? data.detectedAt.value
          : this.detectedAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictLogRow(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('operationType: $operationType, ')
          ..write('conflictCode: $conflictCode, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('safeDetailJson: $safeDetailJson, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('resolution: $resolution')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    requestId,
    aggregateType,
    aggregateId,
    operationType,
    conflictCode,
    baseVersion,
    serverVersion,
    safeDetailJson,
    detectedAt,
    resolvedAt,
    resolution,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflictLogRow &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.operationType == this.operationType &&
          other.conflictCode == this.conflictCode &&
          other.baseVersion == this.baseVersion &&
          other.serverVersion == this.serverVersion &&
          other.safeDetailJson == this.safeDetailJson &&
          other.detectedAt == this.detectedAt &&
          other.resolvedAt == this.resolvedAt &&
          other.resolution == this.resolution);
}

class SyncConflictLogsCompanion extends UpdateCompanion<SyncConflictLogRow> {
  final Value<String> id;
  final Value<String> requestId;
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<String> operationType;
  final Value<String> conflictCode;
  final Value<int> baseVersion;
  final Value<int?> serverVersion;
  final Value<String> safeDetailJson;
  final Value<DateTime> detectedAt;
  final Value<DateTime?> resolvedAt;
  final Value<String?> resolution;
  final Value<int> rowid;
  const SyncConflictLogsCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.conflictCode = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.safeDetailJson = const Value.absent(),
    this.detectedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.resolution = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictLogsCompanion.insert({
    this.id = const Value.absent(),
    required String requestId,
    required String aggregateType,
    required String aggregateId,
    required String operationType,
    required String conflictCode,
    required int baseVersion,
    this.serverVersion = const Value.absent(),
    this.safeDetailJson = const Value.absent(),
    this.detectedAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.resolution = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : requestId = Value(requestId),
       aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId),
       operationType = Value(operationType),
       conflictCode = Value(conflictCode),
       baseVersion = Value(baseVersion);
  static Insertable<SyncConflictLogRow> custom({
    Expression<String>? id,
    Expression<String>? requestId,
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<String>? operationType,
    Expression<String>? conflictCode,
    Expression<int>? baseVersion,
    Expression<int>? serverVersion,
    Expression<String>? safeDetailJson,
    Expression<DateTime>? detectedAt,
    Expression<DateTime>? resolvedAt,
    Expression<String>? resolution,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (operationType != null) 'operation_type': operationType,
      if (conflictCode != null) 'conflict_code': conflictCode,
      if (baseVersion != null) 'base_version': baseVersion,
      if (serverVersion != null) 'server_version': serverVersion,
      if (safeDetailJson != null) 'safe_detail_json': safeDetailJson,
      if (detectedAt != null) 'detected_at': detectedAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (resolution != null) 'resolution': resolution,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? requestId,
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<String>? operationType,
    Value<String>? conflictCode,
    Value<int>? baseVersion,
    Value<int?>? serverVersion,
    Value<String>? safeDetailJson,
    Value<DateTime>? detectedAt,
    Value<DateTime?>? resolvedAt,
    Value<String?>? resolution,
    Value<int>? rowid,
  }) {
    return SyncConflictLogsCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      operationType: operationType ?? this.operationType,
      conflictCode: conflictCode ?? this.conflictCode,
      baseVersion: baseVersion ?? this.baseVersion,
      serverVersion: serverVersion ?? this.serverVersion,
      safeDetailJson: safeDetailJson ?? this.safeDetailJson,
      detectedAt: detectedAt ?? this.detectedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolution: resolution ?? this.resolution,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (conflictCode.present) {
      map['conflict_code'] = Variable<String>(conflictCode.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (safeDetailJson.present) {
      map['safe_detail_json'] = Variable<String>(safeDetailJson.value);
    }
    if (detectedAt.present) {
      map['detected_at'] = Variable<DateTime>(detectedAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictLogsCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('operationType: $operationType, ')
          ..write('conflictCode: $conflictCode, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('safeDetailJson: $safeDetailJson, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('resolution: $resolution, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncFileUploadsTable extends SyncFileUploads
    with TableInfo<$SyncFileUploadsTable, SyncFileUploadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncFileUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorUserIdMeta = const VerificationMeta(
    'actorUserId',
  );
  @override
  late final GeneratedColumn<String> actorUserId = GeneratedColumn<String>(
    'actor_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalFileNameMeta = const VerificationMeta(
    'originalFileName',
  );
  @override
  late final GeneratedColumn<String> originalFileName = GeneratedColumn<String>(
    'original_file_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteBucketMeta = const VerificationMeta(
    'remoteBucket',
  );
  @override
  late final GeneratedColumn<String> remoteBucket = GeneratedColumn<String>(
    'remote_bucket',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteObjectKeyMeta = const VerificationMeta(
    'remoteObjectKey',
  );
  @override
  late final GeneratedColumn<String> remoteObjectKey = GeneratedColumn<String>(
    'remote_object_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteObjectIdMeta = const VerificationMeta(
    'remoteObjectId',
  );
  @override
  late final GeneratedColumn<String> remoteObjectId = GeneratedColumn<String>(
    'remote_object_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptEpochMsMeta =
      const VerificationMeta('nextAttemptEpochMs');
  @override
  late final GeneratedColumn<int> nextAttemptEpochMs = GeneratedColumn<int>(
    'next_attempt_epoch_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _leaseStartedEpochMsMeta =
      const VerificationMeta('leaseStartedEpochMs');
  @override
  late final GeneratedColumn<int> leaseStartedEpochMs = GeneratedColumn<int>(
    'lease_started_epoch_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 96),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMessageMeta = const VerificationMeta(
    'lastErrorMessage',
  );
  @override
  late final GeneratedColumn<String> lastErrorMessage = GeneratedColumn<String>(
    'last_error_message',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 512),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    requestId,
    entityType,
    entityId,
    actorUserId,
    localFilePath,
    originalFileName,
    sha256,
    sizeBytes,
    mimeType,
    remoteBucket,
    remoteObjectKey,
    remoteObjectId,
    status,
    attemptCount,
    nextAttemptEpochMs,
    leaseStartedEpochMs,
    lastErrorCode,
    lastErrorMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_file_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncFileUploadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('actor_user_id')) {
      context.handle(
        _actorUserIdMeta,
        actorUserId.isAcceptableOrUnknown(
          data['actor_user_id']!,
          _actorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actorUserIdMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localFilePathMeta);
    }
    if (data.containsKey('original_file_name')) {
      context.handle(
        _originalFileNameMeta,
        originalFileName.isAcceptableOrUnknown(
          data['original_file_name']!,
          _originalFileNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalFileNameMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('remote_bucket')) {
      context.handle(
        _remoteBucketMeta,
        remoteBucket.isAcceptableOrUnknown(
          data['remote_bucket']!,
          _remoteBucketMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteBucketMeta);
    }
    if (data.containsKey('remote_object_key')) {
      context.handle(
        _remoteObjectKeyMeta,
        remoteObjectKey.isAcceptableOrUnknown(
          data['remote_object_key']!,
          _remoteObjectKeyMeta,
        ),
      );
    }
    if (data.containsKey('remote_object_id')) {
      context.handle(
        _remoteObjectIdMeta,
        remoteObjectId.isAcceptableOrUnknown(
          data['remote_object_id']!,
          _remoteObjectIdMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_epoch_ms')) {
      context.handle(
        _nextAttemptEpochMsMeta,
        nextAttemptEpochMs.isAcceptableOrUnknown(
          data['next_attempt_epoch_ms']!,
          _nextAttemptEpochMsMeta,
        ),
      );
    }
    if (data.containsKey('lease_started_epoch_ms')) {
      context.handle(
        _leaseStartedEpochMsMeta,
        leaseStartedEpochMs.isAcceptableOrUnknown(
          data['lease_started_epoch_ms']!,
          _leaseStartedEpochMsMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_message')) {
      context.handle(
        _lastErrorMessageMeta,
        lastErrorMessage.isAcceptableOrUnknown(
          data['last_error_message']!,
          _lastErrorMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncFileUploadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncFileUploadRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      actorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_user_id'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      )!,
      originalFileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_file_name'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      remoteBucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_bucket'],
      )!,
      remoteObjectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_object_key'],
      ),
      remoteObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_object_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_epoch_ms'],
      )!,
      leaseStartedEpochMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lease_started_epoch_ms'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_message'],
      ),
    );
  }

  @override
  $SyncFileUploadsTable createAlias(String alias) {
    return $SyncFileUploadsTable(attachedDatabase, alias);
  }
}

class SyncFileUploadRow extends DataClass
    implements Insertable<SyncFileUploadRow> {
  final String id;
  final String requestId;
  final String entityType;
  final String entityId;
  final String actorUserId;
  final String localFilePath;
  final String originalFileName;
  final String sha256;
  final int sizeBytes;
  final String mimeType;
  final String remoteBucket;
  final String? remoteObjectKey;
  final String? remoteObjectId;
  final String status;
  final int attemptCount;
  final int nextAttemptEpochMs;
  final int? leaseStartedEpochMs;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  const SyncFileUploadRow({
    required this.id,
    required this.requestId,
    required this.entityType,
    required this.entityId,
    required this.actorUserId,
    required this.localFilePath,
    required this.originalFileName,
    required this.sha256,
    required this.sizeBytes,
    required this.mimeType,
    required this.remoteBucket,
    this.remoteObjectKey,
    this.remoteObjectId,
    required this.status,
    required this.attemptCount,
    required this.nextAttemptEpochMs,
    this.leaseStartedEpochMs,
    this.lastErrorCode,
    this.lastErrorMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['request_id'] = Variable<String>(requestId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['actor_user_id'] = Variable<String>(actorUserId);
    map['local_file_path'] = Variable<String>(localFilePath);
    map['original_file_name'] = Variable<String>(originalFileName);
    map['sha256'] = Variable<String>(sha256);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['mime_type'] = Variable<String>(mimeType);
    map['remote_bucket'] = Variable<String>(remoteBucket);
    if (!nullToAbsent || remoteObjectKey != null) {
      map['remote_object_key'] = Variable<String>(remoteObjectKey);
    }
    if (!nullToAbsent || remoteObjectId != null) {
      map['remote_object_id'] = Variable<String>(remoteObjectId);
    }
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['next_attempt_epoch_ms'] = Variable<int>(nextAttemptEpochMs);
    if (!nullToAbsent || leaseStartedEpochMs != null) {
      map['lease_started_epoch_ms'] = Variable<int>(leaseStartedEpochMs);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorMessage != null) {
      map['last_error_message'] = Variable<String>(lastErrorMessage);
    }
    return map;
  }

  SyncFileUploadsCompanion toCompanion(bool nullToAbsent) {
    return SyncFileUploadsCompanion(
      id: Value(id),
      requestId: Value(requestId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      actorUserId: Value(actorUserId),
      localFilePath: Value(localFilePath),
      originalFileName: Value(originalFileName),
      sha256: Value(sha256),
      sizeBytes: Value(sizeBytes),
      mimeType: Value(mimeType),
      remoteBucket: Value(remoteBucket),
      remoteObjectKey: remoteObjectKey == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteObjectKey),
      remoteObjectId: remoteObjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteObjectId),
      status: Value(status),
      attemptCount: Value(attemptCount),
      nextAttemptEpochMs: Value(nextAttemptEpochMs),
      leaseStartedEpochMs: leaseStartedEpochMs == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseStartedEpochMs),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorMessage: lastErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorMessage),
    );
  }

  factory SyncFileUploadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncFileUploadRow(
      id: serializer.fromJson<String>(json['id']),
      requestId: serializer.fromJson<String>(json['requestId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      actorUserId: serializer.fromJson<String>(json['actorUserId']),
      localFilePath: serializer.fromJson<String>(json['localFilePath']),
      originalFileName: serializer.fromJson<String>(json['originalFileName']),
      sha256: serializer.fromJson<String>(json['sha256']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      remoteBucket: serializer.fromJson<String>(json['remoteBucket']),
      remoteObjectKey: serializer.fromJson<String?>(json['remoteObjectKey']),
      remoteObjectId: serializer.fromJson<String?>(json['remoteObjectId']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptEpochMs: serializer.fromJson<int>(json['nextAttemptEpochMs']),
      leaseStartedEpochMs: serializer.fromJson<int?>(
        json['leaseStartedEpochMs'],
      ),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorMessage: serializer.fromJson<String?>(json['lastErrorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'requestId': serializer.toJson<String>(requestId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'actorUserId': serializer.toJson<String>(actorUserId),
      'localFilePath': serializer.toJson<String>(localFilePath),
      'originalFileName': serializer.toJson<String>(originalFileName),
      'sha256': serializer.toJson<String>(sha256),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'mimeType': serializer.toJson<String>(mimeType),
      'remoteBucket': serializer.toJson<String>(remoteBucket),
      'remoteObjectKey': serializer.toJson<String?>(remoteObjectKey),
      'remoteObjectId': serializer.toJson<String?>(remoteObjectId),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptEpochMs': serializer.toJson<int>(nextAttemptEpochMs),
      'leaseStartedEpochMs': serializer.toJson<int?>(leaseStartedEpochMs),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorMessage': serializer.toJson<String?>(lastErrorMessage),
    };
  }

  SyncFileUploadRow copyWith({
    String? id,
    String? requestId,
    String? entityType,
    String? entityId,
    String? actorUserId,
    String? localFilePath,
    String? originalFileName,
    String? sha256,
    int? sizeBytes,
    String? mimeType,
    String? remoteBucket,
    Value<String?> remoteObjectKey = const Value.absent(),
    Value<String?> remoteObjectId = const Value.absent(),
    String? status,
    int? attemptCount,
    int? nextAttemptEpochMs,
    Value<int?> leaseStartedEpochMs = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorMessage = const Value.absent(),
  }) => SyncFileUploadRow(
    id: id ?? this.id,
    requestId: requestId ?? this.requestId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    actorUserId: actorUserId ?? this.actorUserId,
    localFilePath: localFilePath ?? this.localFilePath,
    originalFileName: originalFileName ?? this.originalFileName,
    sha256: sha256 ?? this.sha256,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    mimeType: mimeType ?? this.mimeType,
    remoteBucket: remoteBucket ?? this.remoteBucket,
    remoteObjectKey: remoteObjectKey.present
        ? remoteObjectKey.value
        : this.remoteObjectKey,
    remoteObjectId: remoteObjectId.present
        ? remoteObjectId.value
        : this.remoteObjectId,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptEpochMs: nextAttemptEpochMs ?? this.nextAttemptEpochMs,
    leaseStartedEpochMs: leaseStartedEpochMs.present
        ? leaseStartedEpochMs.value
        : this.leaseStartedEpochMs,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorMessage: lastErrorMessage.present
        ? lastErrorMessage.value
        : this.lastErrorMessage,
  );
  SyncFileUploadRow copyWithCompanion(SyncFileUploadsCompanion data) {
    return SyncFileUploadRow(
      id: data.id.present ? data.id.value : this.id,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      actorUserId: data.actorUserId.present
          ? data.actorUserId.value
          : this.actorUserId,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      originalFileName: data.originalFileName.present
          ? data.originalFileName.value
          : this.originalFileName,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      remoteBucket: data.remoteBucket.present
          ? data.remoteBucket.value
          : this.remoteBucket,
      remoteObjectKey: data.remoteObjectKey.present
          ? data.remoteObjectKey.value
          : this.remoteObjectKey,
      remoteObjectId: data.remoteObjectId.present
          ? data.remoteObjectId.value
          : this.remoteObjectId,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptEpochMs: data.nextAttemptEpochMs.present
          ? data.nextAttemptEpochMs.value
          : this.nextAttemptEpochMs,
      leaseStartedEpochMs: data.leaseStartedEpochMs.present
          ? data.leaseStartedEpochMs.value
          : this.leaseStartedEpochMs,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorMessage: data.lastErrorMessage.present
          ? data.lastErrorMessage.value
          : this.lastErrorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncFileUploadRow(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('originalFileName: $originalFileName, ')
          ..write('sha256: $sha256, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('remoteBucket: $remoteBucket, ')
          ..write('remoteObjectKey: $remoteObjectKey, ')
          ..write('remoteObjectId: $remoteObjectId, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptEpochMs: $nextAttemptEpochMs, ')
          ..write('leaseStartedEpochMs: $leaseStartedEpochMs, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    requestId,
    entityType,
    entityId,
    actorUserId,
    localFilePath,
    originalFileName,
    sha256,
    sizeBytes,
    mimeType,
    remoteBucket,
    remoteObjectKey,
    remoteObjectId,
    status,
    attemptCount,
    nextAttemptEpochMs,
    leaseStartedEpochMs,
    lastErrorCode,
    lastErrorMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncFileUploadRow &&
          other.id == this.id &&
          other.requestId == this.requestId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.actorUserId == this.actorUserId &&
          other.localFilePath == this.localFilePath &&
          other.originalFileName == this.originalFileName &&
          other.sha256 == this.sha256 &&
          other.sizeBytes == this.sizeBytes &&
          other.mimeType == this.mimeType &&
          other.remoteBucket == this.remoteBucket &&
          other.remoteObjectKey == this.remoteObjectKey &&
          other.remoteObjectId == this.remoteObjectId &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptEpochMs == this.nextAttemptEpochMs &&
          other.leaseStartedEpochMs == this.leaseStartedEpochMs &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorMessage == this.lastErrorMessage);
}

class SyncFileUploadsCompanion extends UpdateCompanion<SyncFileUploadRow> {
  final Value<String> id;
  final Value<String> requestId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> actorUserId;
  final Value<String> localFilePath;
  final Value<String> originalFileName;
  final Value<String> sha256;
  final Value<int> sizeBytes;
  final Value<String> mimeType;
  final Value<String> remoteBucket;
  final Value<String?> remoteObjectKey;
  final Value<String?> remoteObjectId;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<int> nextAttemptEpochMs;
  final Value<int?> leaseStartedEpochMs;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorMessage;
  final Value<int> rowid;
  const SyncFileUploadsCompanion({
    this.id = const Value.absent(),
    this.requestId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.actorUserId = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.originalFileName = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.remoteBucket = const Value.absent(),
    this.remoteObjectKey = const Value.absent(),
    this.remoteObjectId = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptEpochMs = const Value.absent(),
    this.leaseStartedEpochMs = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncFileUploadsCompanion.insert({
    this.id = const Value.absent(),
    required String requestId,
    required String entityType,
    required String entityId,
    required String actorUserId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
    this.remoteObjectKey = const Value.absent(),
    this.remoteObjectId = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptEpochMs = const Value.absent(),
    this.leaseStartedEpochMs = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : requestId = Value(requestId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       actorUserId = Value(actorUserId),
       localFilePath = Value(localFilePath),
       originalFileName = Value(originalFileName),
       sha256 = Value(sha256),
       sizeBytes = Value(sizeBytes),
       mimeType = Value(mimeType),
       remoteBucket = Value(remoteBucket);
  static Insertable<SyncFileUploadRow> custom({
    Expression<String>? id,
    Expression<String>? requestId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? actorUserId,
    Expression<String>? localFilePath,
    Expression<String>? originalFileName,
    Expression<String>? sha256,
    Expression<int>? sizeBytes,
    Expression<String>? mimeType,
    Expression<String>? remoteBucket,
    Expression<String>? remoteObjectKey,
    Expression<String>? remoteObjectId,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<int>? nextAttemptEpochMs,
    Expression<int>? leaseStartedEpochMs,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (requestId != null) 'request_id': requestId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (originalFileName != null) 'original_file_name': originalFileName,
      if (sha256 != null) 'sha256': sha256,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (mimeType != null) 'mime_type': mimeType,
      if (remoteBucket != null) 'remote_bucket': remoteBucket,
      if (remoteObjectKey != null) 'remote_object_key': remoteObjectKey,
      if (remoteObjectId != null) 'remote_object_id': remoteObjectId,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptEpochMs != null)
        'next_attempt_epoch_ms': nextAttemptEpochMs,
      if (leaseStartedEpochMs != null)
        'lease_started_epoch_ms': leaseStartedEpochMs,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncFileUploadsCompanion copyWith({
    Value<String>? id,
    Value<String>? requestId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? actorUserId,
    Value<String>? localFilePath,
    Value<String>? originalFileName,
    Value<String>? sha256,
    Value<int>? sizeBytes,
    Value<String>? mimeType,
    Value<String>? remoteBucket,
    Value<String?>? remoteObjectKey,
    Value<String?>? remoteObjectId,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<int>? nextAttemptEpochMs,
    Value<int?>? leaseStartedEpochMs,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorMessage,
    Value<int>? rowid,
  }) {
    return SyncFileUploadsCompanion(
      id: id ?? this.id,
      requestId: requestId ?? this.requestId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      actorUserId: actorUserId ?? this.actorUserId,
      localFilePath: localFilePath ?? this.localFilePath,
      originalFileName: originalFileName ?? this.originalFileName,
      sha256: sha256 ?? this.sha256,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      remoteBucket: remoteBucket ?? this.remoteBucket,
      remoteObjectKey: remoteObjectKey ?? this.remoteObjectKey,
      remoteObjectId: remoteObjectId ?? this.remoteObjectId,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptEpochMs: nextAttemptEpochMs ?? this.nextAttemptEpochMs,
      leaseStartedEpochMs: leaseStartedEpochMs ?? this.leaseStartedEpochMs,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (actorUserId.present) {
      map['actor_user_id'] = Variable<String>(actorUserId.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (originalFileName.present) {
      map['original_file_name'] = Variable<String>(originalFileName.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (remoteBucket.present) {
      map['remote_bucket'] = Variable<String>(remoteBucket.value);
    }
    if (remoteObjectKey.present) {
      map['remote_object_key'] = Variable<String>(remoteObjectKey.value);
    }
    if (remoteObjectId.present) {
      map['remote_object_id'] = Variable<String>(remoteObjectId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptEpochMs.present) {
      map['next_attempt_epoch_ms'] = Variable<int>(nextAttemptEpochMs.value);
    }
    if (leaseStartedEpochMs.present) {
      map['lease_started_epoch_ms'] = Variable<int>(leaseStartedEpochMs.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorMessage.present) {
      map['last_error_message'] = Variable<String>(lastErrorMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncFileUploadsCompanion(')
          ..write('id: $id, ')
          ..write('requestId: $requestId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('originalFileName: $originalFileName, ')
          ..write('sha256: $sha256, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('remoteBucket: $remoteBucket, ')
          ..write('remoteObjectKey: $remoteObjectKey, ')
          ..write('remoteObjectId: $remoteObjectId, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptEpochMs: $nextAttemptEpochMs, ')
          ..write('leaseStartedEpochMs: $leaseStartedEpochMs, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncPullCursorsTable extends SyncPullCursors
    with TableInfo<$SyncPullCursorsTable, SyncPullCursorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPullCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _actorUserIdMeta = const VerificationMeta(
    'actorUserId',
  );
  @override
  late final GeneratedColumn<String> actorUserId = GeneratedColumn<String>(
    'actor_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeFingerprintMeta = const VerificationMeta(
    'scopeFingerprint',
  );
  @override
  late final GeneratedColumn<String> scopeFingerprint = GeneratedColumn<String>(
    'scope_fingerprint',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 128,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorValueMeta = const VerificationMeta(
    'cursorValue',
  );
  @override
  late final GeneratedColumn<int> cursorValue = GeneratedColumn<int>(
    'cursor_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPulledAtUtcMeta = const VerificationMeta(
    'lastPulledAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> lastPulledAtUtc =
      GeneratedColumn<DateTime>(
        'last_pulled_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastServerTimeUtcMeta = const VerificationMeta(
    'lastServerTimeUtc',
  );
  @override
  late final GeneratedColumn<DateTime> lastServerTimeUtc =
      GeneratedColumn<DateTime>(
        'last_server_time_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSuccessAtUtcMeta = const VerificationMeta(
    'lastSuccessAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> lastSuccessAtUtc =
      GeneratedColumn<DateTime>(
        'last_success_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _appliedChangeCountMeta =
      const VerificationMeta('appliedChangeCount');
  @override
  late final GeneratedColumn<int> appliedChangeCount = GeneratedColumn<int>(
    'applied_change_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    actorUserId,
    scopeFingerprint,
    cursorValue,
    lastPulledAtUtc,
    lastServerTimeUtc,
    lastSuccessAtUtc,
    appliedChangeCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pull_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPullCursorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('actor_user_id')) {
      context.handle(
        _actorUserIdMeta,
        actorUserId.isAcceptableOrUnknown(
          data['actor_user_id']!,
          _actorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actorUserIdMeta);
    }
    if (data.containsKey('scope_fingerprint')) {
      context.handle(
        _scopeFingerprintMeta,
        scopeFingerprint.isAcceptableOrUnknown(
          data['scope_fingerprint']!,
          _scopeFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scopeFingerprintMeta);
    }
    if (data.containsKey('cursor_value')) {
      context.handle(
        _cursorValueMeta,
        cursorValue.isAcceptableOrUnknown(
          data['cursor_value']!,
          _cursorValueMeta,
        ),
      );
    }
    if (data.containsKey('last_pulled_at_utc')) {
      context.handle(
        _lastPulledAtUtcMeta,
        lastPulledAtUtc.isAcceptableOrUnknown(
          data['last_pulled_at_utc']!,
          _lastPulledAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_server_time_utc')) {
      context.handle(
        _lastServerTimeUtcMeta,
        lastServerTimeUtc.isAcceptableOrUnknown(
          data['last_server_time_utc']!,
          _lastServerTimeUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_success_at_utc')) {
      context.handle(
        _lastSuccessAtUtcMeta,
        lastSuccessAtUtc.isAcceptableOrUnknown(
          data['last_success_at_utc']!,
          _lastSuccessAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('applied_change_count')) {
      context.handle(
        _appliedChangeCountMeta,
        appliedChangeCount.isAcceptableOrUnknown(
          data['applied_change_count']!,
          _appliedChangeCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncPullCursorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPullCursorRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_user_id'],
      )!,
      scopeFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_fingerprint'],
      )!,
      cursorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_value'],
      )!,
      lastPulledAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pulled_at_utc'],
      ),
      lastServerTimeUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_server_time_utc'],
      ),
      lastSuccessAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_success_at_utc'],
      ),
      appliedChangeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}applied_change_count'],
      )!,
    );
  }

  @override
  $SyncPullCursorsTable createAlias(String alias) {
    return $SyncPullCursorsTable(attachedDatabase, alias);
  }
}

class SyncPullCursorRow extends DataClass
    implements Insertable<SyncPullCursorRow> {
  final String id;
  final String actorUserId;
  final String scopeFingerprint;
  final int cursorValue;
  final DateTime? lastPulledAtUtc;
  final DateTime? lastServerTimeUtc;
  final DateTime? lastSuccessAtUtc;
  final int appliedChangeCount;
  const SyncPullCursorRow({
    required this.id,
    required this.actorUserId,
    required this.scopeFingerprint,
    required this.cursorValue,
    this.lastPulledAtUtc,
    this.lastServerTimeUtc,
    this.lastSuccessAtUtc,
    required this.appliedChangeCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['actor_user_id'] = Variable<String>(actorUserId);
    map['scope_fingerprint'] = Variable<String>(scopeFingerprint);
    map['cursor_value'] = Variable<int>(cursorValue);
    if (!nullToAbsent || lastPulledAtUtc != null) {
      map['last_pulled_at_utc'] = Variable<DateTime>(lastPulledAtUtc);
    }
    if (!nullToAbsent || lastServerTimeUtc != null) {
      map['last_server_time_utc'] = Variable<DateTime>(lastServerTimeUtc);
    }
    if (!nullToAbsent || lastSuccessAtUtc != null) {
      map['last_success_at_utc'] = Variable<DateTime>(lastSuccessAtUtc);
    }
    map['applied_change_count'] = Variable<int>(appliedChangeCount);
    return map;
  }

  SyncPullCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncPullCursorsCompanion(
      id: Value(id),
      actorUserId: Value(actorUserId),
      scopeFingerprint: Value(scopeFingerprint),
      cursorValue: Value(cursorValue),
      lastPulledAtUtc: lastPulledAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAtUtc),
      lastServerTimeUtc: lastServerTimeUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastServerTimeUtc),
      lastSuccessAtUtc: lastSuccessAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessAtUtc),
      appliedChangeCount: Value(appliedChangeCount),
    );
  }

  factory SyncPullCursorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPullCursorRow(
      id: serializer.fromJson<String>(json['id']),
      actorUserId: serializer.fromJson<String>(json['actorUserId']),
      scopeFingerprint: serializer.fromJson<String>(json['scopeFingerprint']),
      cursorValue: serializer.fromJson<int>(json['cursorValue']),
      lastPulledAtUtc: serializer.fromJson<DateTime?>(json['lastPulledAtUtc']),
      lastServerTimeUtc: serializer.fromJson<DateTime?>(
        json['lastServerTimeUtc'],
      ),
      lastSuccessAtUtc: serializer.fromJson<DateTime?>(
        json['lastSuccessAtUtc'],
      ),
      appliedChangeCount: serializer.fromJson<int>(json['appliedChangeCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actorUserId': serializer.toJson<String>(actorUserId),
      'scopeFingerprint': serializer.toJson<String>(scopeFingerprint),
      'cursorValue': serializer.toJson<int>(cursorValue),
      'lastPulledAtUtc': serializer.toJson<DateTime?>(lastPulledAtUtc),
      'lastServerTimeUtc': serializer.toJson<DateTime?>(lastServerTimeUtc),
      'lastSuccessAtUtc': serializer.toJson<DateTime?>(lastSuccessAtUtc),
      'appliedChangeCount': serializer.toJson<int>(appliedChangeCount),
    };
  }

  SyncPullCursorRow copyWith({
    String? id,
    String? actorUserId,
    String? scopeFingerprint,
    int? cursorValue,
    Value<DateTime?> lastPulledAtUtc = const Value.absent(),
    Value<DateTime?> lastServerTimeUtc = const Value.absent(),
    Value<DateTime?> lastSuccessAtUtc = const Value.absent(),
    int? appliedChangeCount,
  }) => SyncPullCursorRow(
    id: id ?? this.id,
    actorUserId: actorUserId ?? this.actorUserId,
    scopeFingerprint: scopeFingerprint ?? this.scopeFingerprint,
    cursorValue: cursorValue ?? this.cursorValue,
    lastPulledAtUtc: lastPulledAtUtc.present
        ? lastPulledAtUtc.value
        : this.lastPulledAtUtc,
    lastServerTimeUtc: lastServerTimeUtc.present
        ? lastServerTimeUtc.value
        : this.lastServerTimeUtc,
    lastSuccessAtUtc: lastSuccessAtUtc.present
        ? lastSuccessAtUtc.value
        : this.lastSuccessAtUtc,
    appliedChangeCount: appliedChangeCount ?? this.appliedChangeCount,
  );
  SyncPullCursorRow copyWithCompanion(SyncPullCursorsCompanion data) {
    return SyncPullCursorRow(
      id: data.id.present ? data.id.value : this.id,
      actorUserId: data.actorUserId.present
          ? data.actorUserId.value
          : this.actorUserId,
      scopeFingerprint: data.scopeFingerprint.present
          ? data.scopeFingerprint.value
          : this.scopeFingerprint,
      cursorValue: data.cursorValue.present
          ? data.cursorValue.value
          : this.cursorValue,
      lastPulledAtUtc: data.lastPulledAtUtc.present
          ? data.lastPulledAtUtc.value
          : this.lastPulledAtUtc,
      lastServerTimeUtc: data.lastServerTimeUtc.present
          ? data.lastServerTimeUtc.value
          : this.lastServerTimeUtc,
      lastSuccessAtUtc: data.lastSuccessAtUtc.present
          ? data.lastSuccessAtUtc.value
          : this.lastSuccessAtUtc,
      appliedChangeCount: data.appliedChangeCount.present
          ? data.appliedChangeCount.value
          : this.appliedChangeCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPullCursorRow(')
          ..write('id: $id, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('scopeFingerprint: $scopeFingerprint, ')
          ..write('cursorValue: $cursorValue, ')
          ..write('lastPulledAtUtc: $lastPulledAtUtc, ')
          ..write('lastServerTimeUtc: $lastServerTimeUtc, ')
          ..write('lastSuccessAtUtc: $lastSuccessAtUtc, ')
          ..write('appliedChangeCount: $appliedChangeCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    actorUserId,
    scopeFingerprint,
    cursorValue,
    lastPulledAtUtc,
    lastServerTimeUtc,
    lastSuccessAtUtc,
    appliedChangeCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPullCursorRow &&
          other.id == this.id &&
          other.actorUserId == this.actorUserId &&
          other.scopeFingerprint == this.scopeFingerprint &&
          other.cursorValue == this.cursorValue &&
          other.lastPulledAtUtc == this.lastPulledAtUtc &&
          other.lastServerTimeUtc == this.lastServerTimeUtc &&
          other.lastSuccessAtUtc == this.lastSuccessAtUtc &&
          other.appliedChangeCount == this.appliedChangeCount);
}

class SyncPullCursorsCompanion extends UpdateCompanion<SyncPullCursorRow> {
  final Value<String> id;
  final Value<String> actorUserId;
  final Value<String> scopeFingerprint;
  final Value<int> cursorValue;
  final Value<DateTime?> lastPulledAtUtc;
  final Value<DateTime?> lastServerTimeUtc;
  final Value<DateTime?> lastSuccessAtUtc;
  final Value<int> appliedChangeCount;
  final Value<int> rowid;
  const SyncPullCursorsCompanion({
    this.id = const Value.absent(),
    this.actorUserId = const Value.absent(),
    this.scopeFingerprint = const Value.absent(),
    this.cursorValue = const Value.absent(),
    this.lastPulledAtUtc = const Value.absent(),
    this.lastServerTimeUtc = const Value.absent(),
    this.lastSuccessAtUtc = const Value.absent(),
    this.appliedChangeCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPullCursorsCompanion.insert({
    this.id = const Value.absent(),
    required String actorUserId,
    required String scopeFingerprint,
    this.cursorValue = const Value.absent(),
    this.lastPulledAtUtc = const Value.absent(),
    this.lastServerTimeUtc = const Value.absent(),
    this.lastSuccessAtUtc = const Value.absent(),
    this.appliedChangeCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : actorUserId = Value(actorUserId),
       scopeFingerprint = Value(scopeFingerprint);
  static Insertable<SyncPullCursorRow> custom({
    Expression<String>? id,
    Expression<String>? actorUserId,
    Expression<String>? scopeFingerprint,
    Expression<int>? cursorValue,
    Expression<DateTime>? lastPulledAtUtc,
    Expression<DateTime>? lastServerTimeUtc,
    Expression<DateTime>? lastSuccessAtUtc,
    Expression<int>? appliedChangeCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (scopeFingerprint != null) 'scope_fingerprint': scopeFingerprint,
      if (cursorValue != null) 'cursor_value': cursorValue,
      if (lastPulledAtUtc != null) 'last_pulled_at_utc': lastPulledAtUtc,
      if (lastServerTimeUtc != null) 'last_server_time_utc': lastServerTimeUtc,
      if (lastSuccessAtUtc != null) 'last_success_at_utc': lastSuccessAtUtc,
      if (appliedChangeCount != null)
        'applied_change_count': appliedChangeCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPullCursorsCompanion copyWith({
    Value<String>? id,
    Value<String>? actorUserId,
    Value<String>? scopeFingerprint,
    Value<int>? cursorValue,
    Value<DateTime?>? lastPulledAtUtc,
    Value<DateTime?>? lastServerTimeUtc,
    Value<DateTime?>? lastSuccessAtUtc,
    Value<int>? appliedChangeCount,
    Value<int>? rowid,
  }) {
    return SyncPullCursorsCompanion(
      id: id ?? this.id,
      actorUserId: actorUserId ?? this.actorUserId,
      scopeFingerprint: scopeFingerprint ?? this.scopeFingerprint,
      cursorValue: cursorValue ?? this.cursorValue,
      lastPulledAtUtc: lastPulledAtUtc ?? this.lastPulledAtUtc,
      lastServerTimeUtc: lastServerTimeUtc ?? this.lastServerTimeUtc,
      lastSuccessAtUtc: lastSuccessAtUtc ?? this.lastSuccessAtUtc,
      appliedChangeCount: appliedChangeCount ?? this.appliedChangeCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorUserId.present) {
      map['actor_user_id'] = Variable<String>(actorUserId.value);
    }
    if (scopeFingerprint.present) {
      map['scope_fingerprint'] = Variable<String>(scopeFingerprint.value);
    }
    if (cursorValue.present) {
      map['cursor_value'] = Variable<int>(cursorValue.value);
    }
    if (lastPulledAtUtc.present) {
      map['last_pulled_at_utc'] = Variable<DateTime>(lastPulledAtUtc.value);
    }
    if (lastServerTimeUtc.present) {
      map['last_server_time_utc'] = Variable<DateTime>(lastServerTimeUtc.value);
    }
    if (lastSuccessAtUtc.present) {
      map['last_success_at_utc'] = Variable<DateTime>(lastSuccessAtUtc.value);
    }
    if (appliedChangeCount.present) {
      map['applied_change_count'] = Variable<int>(appliedChangeCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPullCursorsCompanion(')
          ..write('id: $id, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('scopeFingerprint: $scopeFingerprint, ')
          ..write('cursorValue: $cursorValue, ')
          ..write('lastPulledAtUtc: $lastPulledAtUtc, ')
          ..write('lastServerTimeUtc: $lastServerTimeUtc, ')
          ..write('lastSuccessAtUtc: $lastSuccessAtUtc, ')
          ..write('appliedChangeCount: $appliedChangeCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncEntitySnapshotsTable extends SyncEntitySnapshots
    with TableInfo<$SyncEntitySnapshotsTable, SyncEntitySnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncEntitySnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverChangedAtUtcMeta =
      const VerificationMeta('serverChangedAtUtc');
  @override
  late final GeneratedColumn<DateTime> serverChangedAtUtc =
      GeneratedColumn<DateTime>(
        'server_changed_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appliedAtUtcMeta = const VerificationMeta(
    'appliedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> appliedAtUtc = GeneratedColumn<DateTime>(
    'applied_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    serverVersion,
    serverChangedAtUtc,
    snapshotJson,
    appliedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_entity_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncEntitySnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverVersionMeta);
    }
    if (data.containsKey('server_changed_at_utc')) {
      context.handle(
        _serverChangedAtUtcMeta,
        serverChangedAtUtc.isAcceptableOrUnknown(
          data['server_changed_at_utc']!,
          _serverChangedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotJsonMeta);
    }
    if (data.containsKey('applied_at_utc')) {
      context.handle(
        _appliedAtUtcMeta,
        appliedAtUtc.isAcceptableOrUnknown(
          data['applied_at_utc']!,
          _appliedAtUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncEntitySnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncEntitySnapshotRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
      serverChangedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_changed_at_utc'],
      ),
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      )!,
      appliedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}applied_at_utc'],
      )!,
    );
  }

  @override
  $SyncEntitySnapshotsTable createAlias(String alias) {
    return $SyncEntitySnapshotsTable(attachedDatabase, alias);
  }
}

class SyncEntitySnapshotRow extends DataClass
    implements Insertable<SyncEntitySnapshotRow> {
  final String id;
  final String entityType;
  final String entityId;
  final int serverVersion;
  final DateTime? serverChangedAtUtc;
  final String snapshotJson;
  final DateTime appliedAtUtc;
  const SyncEntitySnapshotRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.serverVersion,
    this.serverChangedAtUtc,
    required this.snapshotJson,
    required this.appliedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['server_version'] = Variable<int>(serverVersion);
    if (!nullToAbsent || serverChangedAtUtc != null) {
      map['server_changed_at_utc'] = Variable<DateTime>(serverChangedAtUtc);
    }
    map['snapshot_json'] = Variable<String>(snapshotJson);
    map['applied_at_utc'] = Variable<DateTime>(appliedAtUtc);
    return map;
  }

  SyncEntitySnapshotsCompanion toCompanion(bool nullToAbsent) {
    return SyncEntitySnapshotsCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      serverVersion: Value(serverVersion),
      serverChangedAtUtc: serverChangedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(serverChangedAtUtc),
      snapshotJson: Value(snapshotJson),
      appliedAtUtc: Value(appliedAtUtc),
    );
  }

  factory SyncEntitySnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncEntitySnapshotRow(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      serverChangedAtUtc: serializer.fromJson<DateTime?>(
        json['serverChangedAtUtc'],
      ),
      snapshotJson: serializer.fromJson<String>(json['snapshotJson']),
      appliedAtUtc: serializer.fromJson<DateTime>(json['appliedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'serverChangedAtUtc': serializer.toJson<DateTime?>(serverChangedAtUtc),
      'snapshotJson': serializer.toJson<String>(snapshotJson),
      'appliedAtUtc': serializer.toJson<DateTime>(appliedAtUtc),
    };
  }

  SyncEntitySnapshotRow copyWith({
    String? id,
    String? entityType,
    String? entityId,
    int? serverVersion,
    Value<DateTime?> serverChangedAtUtc = const Value.absent(),
    String? snapshotJson,
    DateTime? appliedAtUtc,
  }) => SyncEntitySnapshotRow(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    serverVersion: serverVersion ?? this.serverVersion,
    serverChangedAtUtc: serverChangedAtUtc.present
        ? serverChangedAtUtc.value
        : this.serverChangedAtUtc,
    snapshotJson: snapshotJson ?? this.snapshotJson,
    appliedAtUtc: appliedAtUtc ?? this.appliedAtUtc,
  );
  SyncEntitySnapshotRow copyWithCompanion(SyncEntitySnapshotsCompanion data) {
    return SyncEntitySnapshotRow(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      serverChangedAtUtc: data.serverChangedAtUtc.present
          ? data.serverChangedAtUtc.value
          : this.serverChangedAtUtc,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
      appliedAtUtc: data.appliedAtUtc.present
          ? data.appliedAtUtc.value
          : this.appliedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntitySnapshotRow(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverChangedAtUtc: $serverChangedAtUtc, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('appliedAtUtc: $appliedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    serverVersion,
    serverChangedAtUtc,
    snapshotJson,
    appliedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncEntitySnapshotRow &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.serverVersion == this.serverVersion &&
          other.serverChangedAtUtc == this.serverChangedAtUtc &&
          other.snapshotJson == this.snapshotJson &&
          other.appliedAtUtc == this.appliedAtUtc);
}

class SyncEntitySnapshotsCompanion
    extends UpdateCompanion<SyncEntitySnapshotRow> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> serverVersion;
  final Value<DateTime?> serverChangedAtUtc;
  final Value<String> snapshotJson;
  final Value<DateTime> appliedAtUtc;
  final Value<int> rowid;
  const SyncEntitySnapshotsCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.serverChangedAtUtc = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.appliedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncEntitySnapshotsCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required int serverVersion,
    this.serverChangedAtUtc = const Value.absent(),
    required String snapshotJson,
    this.appliedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       serverVersion = Value(serverVersion),
       snapshotJson = Value(snapshotJson);
  static Insertable<SyncEntitySnapshotRow> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? serverVersion,
    Expression<DateTime>? serverChangedAtUtc,
    Expression<String>? snapshotJson,
    Expression<DateTime>? appliedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (serverVersion != null) 'server_version': serverVersion,
      if (serverChangedAtUtc != null)
        'server_changed_at_utc': serverChangedAtUtc,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (appliedAtUtc != null) 'applied_at_utc': appliedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncEntitySnapshotsCompanion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? serverVersion,
    Value<DateTime?>? serverChangedAtUtc,
    Value<String>? snapshotJson,
    Value<DateTime>? appliedAtUtc,
    Value<int>? rowid,
  }) {
    return SyncEntitySnapshotsCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      serverVersion: serverVersion ?? this.serverVersion,
      serverChangedAtUtc: serverChangedAtUtc ?? this.serverChangedAtUtc,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      appliedAtUtc: appliedAtUtc ?? this.appliedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (serverChangedAtUtc.present) {
      map['server_changed_at_utc'] = Variable<DateTime>(
        serverChangedAtUtc.value,
      );
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (appliedAtUtc.present) {
      map['applied_at_utc'] = Variable<DateTime>(appliedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntitySnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverChangedAtUtc: $serverChangedAtUtc, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('appliedAtUtc: $appliedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncFieldVersionsTable extends SyncFieldVersions
    with TableInfo<$SyncFieldVersionsTable, SyncFieldVersionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncFieldVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldNameMeta = const VerificationMeta(
    'fieldName',
  );
  @override
  late final GeneratedColumn<String> fieldName = GeneratedColumn<String>(
    'field_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionMeta = const VerificationMeta(
    'fieldVersion',
  );
  @override
  late final GeneratedColumn<int> fieldVersion = GeneratedColumn<int>(
    'field_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    fieldName,
    fieldVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_field_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncFieldVersionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('field_name')) {
      context.handle(
        _fieldNameMeta,
        fieldName.isAcceptableOrUnknown(data['field_name']!, _fieldNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldNameMeta);
    }
    if (data.containsKey('field_version')) {
      context.handle(
        _fieldVersionMeta,
        fieldVersion.isAcceptableOrUnknown(
          data['field_version']!,
          _fieldVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fieldVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncFieldVersionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncFieldVersionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      fieldName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_name'],
      )!,
      fieldVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}field_version'],
      )!,
    );
  }

  @override
  $SyncFieldVersionsTable createAlias(String alias) {
    return $SyncFieldVersionsTable(attachedDatabase, alias);
  }
}

class SyncFieldVersionRow extends DataClass
    implements Insertable<SyncFieldVersionRow> {
  final String id;
  final String entityType;
  final String entityId;
  final String fieldName;
  final int fieldVersion;
  const SyncFieldVersionRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.fieldName,
    required this.fieldVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['field_name'] = Variable<String>(fieldName);
    map['field_version'] = Variable<int>(fieldVersion);
    return map;
  }

  SyncFieldVersionsCompanion toCompanion(bool nullToAbsent) {
    return SyncFieldVersionsCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      fieldName: Value(fieldName),
      fieldVersion: Value(fieldVersion),
    );
  }

  factory SyncFieldVersionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncFieldVersionRow(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      fieldName: serializer.fromJson<String>(json['fieldName']),
      fieldVersion: serializer.fromJson<int>(json['fieldVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'fieldName': serializer.toJson<String>(fieldName),
      'fieldVersion': serializer.toJson<int>(fieldVersion),
    };
  }

  SyncFieldVersionRow copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? fieldName,
    int? fieldVersion,
  }) => SyncFieldVersionRow(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    fieldName: fieldName ?? this.fieldName,
    fieldVersion: fieldVersion ?? this.fieldVersion,
  );
  SyncFieldVersionRow copyWithCompanion(SyncFieldVersionsCompanion data) {
    return SyncFieldVersionRow(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      fieldName: data.fieldName.present ? data.fieldName.value : this.fieldName,
      fieldVersion: data.fieldVersion.present
          ? data.fieldVersion.value
          : this.fieldVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncFieldVersionRow(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('fieldName: $fieldName, ')
          ..write('fieldVersion: $fieldVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, entityType, entityId, fieldName, fieldVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncFieldVersionRow &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.fieldName == this.fieldName &&
          other.fieldVersion == this.fieldVersion);
}

class SyncFieldVersionsCompanion extends UpdateCompanion<SyncFieldVersionRow> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> fieldName;
  final Value<int> fieldVersion;
  final Value<int> rowid;
  const SyncFieldVersionsCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.fieldName = const Value.absent(),
    this.fieldVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncFieldVersionsCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String fieldName,
    required int fieldVersion,
    this.rowid = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       fieldName = Value(fieldName),
       fieldVersion = Value(fieldVersion);
  static Insertable<SyncFieldVersionRow> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? fieldName,
    Expression<int>? fieldVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (fieldName != null) 'field_name': fieldName,
      if (fieldVersion != null) 'field_version': fieldVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncFieldVersionsCompanion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? fieldName,
    Value<int>? fieldVersion,
    Value<int>? rowid,
  }) {
    return SyncFieldVersionsCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      fieldName: fieldName ?? this.fieldName,
      fieldVersion: fieldVersion ?? this.fieldVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (fieldName.present) {
      map['field_name'] = Variable<String>(fieldName.value);
    }
    if (fieldVersion.present) {
      map['field_version'] = Variable<int>(fieldVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncFieldVersionsCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('fieldName: $fieldName, ')
          ..write('fieldVersion: $fieldVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncTombstonesTable extends SyncTombstones
    with TableInfo<$SyncTombstonesTable, SyncTombstoneRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tombstonedAtUtcMeta = const VerificationMeta(
    'tombstonedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> tombstonedAtUtc =
      GeneratedColumn<DateTime>(
        'tombstoned_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _appliedAtUtcMeta = const VerificationMeta(
    'appliedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> appliedAtUtc = GeneratedColumn<DateTime>(
    'applied_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: nowUtc,
  );
  static const VerificationMeta _hadLocalRowMeta = const VerificationMeta(
    'hadLocalRow',
  );
  @override
  late final GeneratedColumn<bool> hadLocalRow = GeneratedColumn<bool>(
    'had_local_row',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("had_local_row" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    serverVersion,
    tombstonedAtUtc,
    appliedAtUtc,
    hadLocalRow,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncTombstoneRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverVersionMeta);
    }
    if (data.containsKey('tombstoned_at_utc')) {
      context.handle(
        _tombstonedAtUtcMeta,
        tombstonedAtUtc.isAcceptableOrUnknown(
          data['tombstoned_at_utc']!,
          _tombstonedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('applied_at_utc')) {
      context.handle(
        _appliedAtUtcMeta,
        appliedAtUtc.isAcceptableOrUnknown(
          data['applied_at_utc']!,
          _appliedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('had_local_row')) {
      context.handle(
        _hadLocalRowMeta,
        hadLocalRow.isAcceptableOrUnknown(
          data['had_local_row']!,
          _hadLocalRowMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncTombstoneRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTombstoneRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      )!,
      tombstonedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}tombstoned_at_utc'],
      ),
      appliedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}applied_at_utc'],
      )!,
      hadLocalRow: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}had_local_row'],
      )!,
    );
  }

  @override
  $SyncTombstonesTable createAlias(String alias) {
    return $SyncTombstonesTable(attachedDatabase, alias);
  }
}

class SyncTombstoneRow extends DataClass
    implements Insertable<SyncTombstoneRow> {
  final String id;
  final String entityType;
  final String entityId;
  final int serverVersion;
  final DateTime? tombstonedAtUtc;
  final DateTime appliedAtUtc;
  final bool hadLocalRow;
  const SyncTombstoneRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.serverVersion,
    this.tombstonedAtUtc,
    required this.appliedAtUtc,
    required this.hadLocalRow,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['server_version'] = Variable<int>(serverVersion);
    if (!nullToAbsent || tombstonedAtUtc != null) {
      map['tombstoned_at_utc'] = Variable<DateTime>(tombstonedAtUtc);
    }
    map['applied_at_utc'] = Variable<DateTime>(appliedAtUtc);
    map['had_local_row'] = Variable<bool>(hadLocalRow);
    return map;
  }

  SyncTombstonesCompanion toCompanion(bool nullToAbsent) {
    return SyncTombstonesCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      serverVersion: Value(serverVersion),
      tombstonedAtUtc: tombstonedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(tombstonedAtUtc),
      appliedAtUtc: Value(appliedAtUtc),
      hadLocalRow: Value(hadLocalRow),
    );
  }

  factory SyncTombstoneRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTombstoneRow(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      tombstonedAtUtc: serializer.fromJson<DateTime?>(json['tombstonedAtUtc']),
      appliedAtUtc: serializer.fromJson<DateTime>(json['appliedAtUtc']),
      hadLocalRow: serializer.fromJson<bool>(json['hadLocalRow']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'tombstonedAtUtc': serializer.toJson<DateTime?>(tombstonedAtUtc),
      'appliedAtUtc': serializer.toJson<DateTime>(appliedAtUtc),
      'hadLocalRow': serializer.toJson<bool>(hadLocalRow),
    };
  }

  SyncTombstoneRow copyWith({
    String? id,
    String? entityType,
    String? entityId,
    int? serverVersion,
    Value<DateTime?> tombstonedAtUtc = const Value.absent(),
    DateTime? appliedAtUtc,
    bool? hadLocalRow,
  }) => SyncTombstoneRow(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    serverVersion: serverVersion ?? this.serverVersion,
    tombstonedAtUtc: tombstonedAtUtc.present
        ? tombstonedAtUtc.value
        : this.tombstonedAtUtc,
    appliedAtUtc: appliedAtUtc ?? this.appliedAtUtc,
    hadLocalRow: hadLocalRow ?? this.hadLocalRow,
  );
  SyncTombstoneRow copyWithCompanion(SyncTombstonesCompanion data) {
    return SyncTombstoneRow(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      tombstonedAtUtc: data.tombstonedAtUtc.present
          ? data.tombstonedAtUtc.value
          : this.tombstonedAtUtc,
      appliedAtUtc: data.appliedAtUtc.present
          ? data.appliedAtUtc.value
          : this.appliedAtUtc,
      hadLocalRow: data.hadLocalRow.present
          ? data.hadLocalRow.value
          : this.hadLocalRow,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstoneRow(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('tombstonedAtUtc: $tombstonedAtUtc, ')
          ..write('appliedAtUtc: $appliedAtUtc, ')
          ..write('hadLocalRow: $hadLocalRow')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    serverVersion,
    tombstonedAtUtc,
    appliedAtUtc,
    hadLocalRow,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTombstoneRow &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.serverVersion == this.serverVersion &&
          other.tombstonedAtUtc == this.tombstonedAtUtc &&
          other.appliedAtUtc == this.appliedAtUtc &&
          other.hadLocalRow == this.hadLocalRow);
}

class SyncTombstonesCompanion extends UpdateCompanion<SyncTombstoneRow> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> serverVersion;
  final Value<DateTime?> tombstonedAtUtc;
  final Value<DateTime> appliedAtUtc;
  final Value<bool> hadLocalRow;
  final Value<int> rowid;
  const SyncTombstonesCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.tombstonedAtUtc = const Value.absent(),
    this.appliedAtUtc = const Value.absent(),
    this.hadLocalRow = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncTombstonesCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required int serverVersion,
    this.tombstonedAtUtc = const Value.absent(),
    this.appliedAtUtc = const Value.absent(),
    this.hadLocalRow = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       serverVersion = Value(serverVersion);
  static Insertable<SyncTombstoneRow> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? serverVersion,
    Expression<DateTime>? tombstonedAtUtc,
    Expression<DateTime>? appliedAtUtc,
    Expression<bool>? hadLocalRow,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (serverVersion != null) 'server_version': serverVersion,
      if (tombstonedAtUtc != null) 'tombstoned_at_utc': tombstonedAtUtc,
      if (appliedAtUtc != null) 'applied_at_utc': appliedAtUtc,
      if (hadLocalRow != null) 'had_local_row': hadLocalRow,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncTombstonesCompanion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? serverVersion,
    Value<DateTime?>? tombstonedAtUtc,
    Value<DateTime>? appliedAtUtc,
    Value<bool>? hadLocalRow,
    Value<int>? rowid,
  }) {
    return SyncTombstonesCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      serverVersion: serverVersion ?? this.serverVersion,
      tombstonedAtUtc: tombstonedAtUtc ?? this.tombstonedAtUtc,
      appliedAtUtc: appliedAtUtc ?? this.appliedAtUtc,
      hadLocalRow: hadLocalRow ?? this.hadLocalRow,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (tombstonedAtUtc.present) {
      map['tombstoned_at_utc'] = Variable<DateTime>(tombstonedAtUtc.value);
    }
    if (appliedAtUtc.present) {
      map['applied_at_utc'] = Variable<DateTime>(appliedAtUtc.value);
    }
    if (hadLocalRow.present) {
      map['had_local_row'] = Variable<bool>(hadLocalRow.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstonesCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('tombstonedAtUtc: $tombstonedAtUtc, ')
          ..write('appliedAtUtc: $appliedAtUtc, ')
          ..write('hadLocalRow: $hadLocalRow, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncPullLogsTable extends SyncPullLogs
    with TableInfo<$SyncPullLogsTable, SyncPullLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPullLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newUuidV4,
  );
  static const VerificationMeta _actorUserIdMeta = const VerificationMeta(
    'actorUserId',
  );
  @override
  late final GeneratedColumn<String> actorUserId = GeneratedColumn<String>(
    'actor_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeFingerprintMeta = const VerificationMeta(
    'scopeFingerprint',
  );
  @override
  late final GeneratedColumn<String> scopeFingerprint = GeneratedColumn<String>(
    'scope_fingerprint',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 128),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fromCursorMeta = const VerificationMeta(
    'fromCursor',
  );
  @override
  late final GeneratedColumn<int> fromCursor = GeneratedColumn<int>(
    'from_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toCursorMeta = const VerificationMeta(
    'toCursor',
  );
  @override
  late final GeneratedColumn<int> toCursor = GeneratedColumn<int>(
    'to_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changeCountMeta = const VerificationMeta(
    'changeCount',
  );
  @override
  late final GeneratedColumn<int> changeCount = GeneratedColumn<int>(
    'change_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tombstoneCountMeta = const VerificationMeta(
    'tombstoneCount',
  );
  @override
  late final GeneratedColumn<int> tombstoneCount = GeneratedColumn<int>(
    'tombstone_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _conflictCountMeta = const VerificationMeta(
    'conflictCount',
  );
  @override
  late final GeneratedColumn<int> conflictCount = GeneratedColumn<int>(
    'conflict_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _safeErrorCodeMeta = const VerificationMeta(
    'safeErrorCode',
  );
  @override
  late final GeneratedColumn<String> safeErrorCode = GeneratedColumn<String>(
    'safe_error_code',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 96),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _safeErrorMessageMeta = const VerificationMeta(
    'safeErrorMessage',
  );
  @override
  late final GeneratedColumn<String> safeErrorMessage = GeneratedColumn<String>(
    'safe_error_message',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(maxTextLength: 512),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    actorUserId,
    scopeFingerprint,
    fromCursor,
    toCursor,
    changeCount,
    tombstoneCount,
    conflictCount,
    outcome,
    safeErrorCode,
    safeErrorMessage,
    startedAt,
    finishedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pull_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPullLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('actor_user_id')) {
      context.handle(
        _actorUserIdMeta,
        actorUserId.isAcceptableOrUnknown(
          data['actor_user_id']!,
          _actorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actorUserIdMeta);
    }
    if (data.containsKey('scope_fingerprint')) {
      context.handle(
        _scopeFingerprintMeta,
        scopeFingerprint.isAcceptableOrUnknown(
          data['scope_fingerprint']!,
          _scopeFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('from_cursor')) {
      context.handle(
        _fromCursorMeta,
        fromCursor.isAcceptableOrUnknown(data['from_cursor']!, _fromCursorMeta),
      );
    } else if (isInserting) {
      context.missing(_fromCursorMeta);
    }
    if (data.containsKey('to_cursor')) {
      context.handle(
        _toCursorMeta,
        toCursor.isAcceptableOrUnknown(data['to_cursor']!, _toCursorMeta),
      );
    } else if (isInserting) {
      context.missing(_toCursorMeta);
    }
    if (data.containsKey('change_count')) {
      context.handle(
        _changeCountMeta,
        changeCount.isAcceptableOrUnknown(
          data['change_count']!,
          _changeCountMeta,
        ),
      );
    }
    if (data.containsKey('tombstone_count')) {
      context.handle(
        _tombstoneCountMeta,
        tombstoneCount.isAcceptableOrUnknown(
          data['tombstone_count']!,
          _tombstoneCountMeta,
        ),
      );
    }
    if (data.containsKey('conflict_count')) {
      context.handle(
        _conflictCountMeta,
        conflictCount.isAcceptableOrUnknown(
          data['conflict_count']!,
          _conflictCountMeta,
        ),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('safe_error_code')) {
      context.handle(
        _safeErrorCodeMeta,
        safeErrorCode.isAcceptableOrUnknown(
          data['safe_error_code']!,
          _safeErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('safe_error_message')) {
      context.handle(
        _safeErrorMessageMeta,
        safeErrorMessage.isAcceptableOrUnknown(
          data['safe_error_message']!,
          _safeErrorMessageMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_finishedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncPullLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPullLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_user_id'],
      )!,
      scopeFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_fingerprint'],
      ),
      fromCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}from_cursor'],
      )!,
      toCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_cursor'],
      )!,
      changeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}change_count'],
      )!,
      tombstoneCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tombstone_count'],
      )!,
      conflictCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conflict_count'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      safeErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safe_error_code'],
      ),
      safeErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safe_error_message'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      )!,
    );
  }

  @override
  $SyncPullLogsTable createAlias(String alias) {
    return $SyncPullLogsTable(attachedDatabase, alias);
  }
}

class SyncPullLogRow extends DataClass implements Insertable<SyncPullLogRow> {
  final String id;
  final String actorUserId;
  final String? scopeFingerprint;
  final int fromCursor;
  final int toCursor;
  final int changeCount;
  final int tombstoneCount;
  final int conflictCount;
  final String outcome;
  final String? safeErrorCode;
  final String? safeErrorMessage;
  final DateTime startedAt;
  final DateTime finishedAt;
  const SyncPullLogRow({
    required this.id,
    required this.actorUserId,
    this.scopeFingerprint,
    required this.fromCursor,
    required this.toCursor,
    required this.changeCount,
    required this.tombstoneCount,
    required this.conflictCount,
    required this.outcome,
    this.safeErrorCode,
    this.safeErrorMessage,
    required this.startedAt,
    required this.finishedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['actor_user_id'] = Variable<String>(actorUserId);
    if (!nullToAbsent || scopeFingerprint != null) {
      map['scope_fingerprint'] = Variable<String>(scopeFingerprint);
    }
    map['from_cursor'] = Variable<int>(fromCursor);
    map['to_cursor'] = Variable<int>(toCursor);
    map['change_count'] = Variable<int>(changeCount);
    map['tombstone_count'] = Variable<int>(tombstoneCount);
    map['conflict_count'] = Variable<int>(conflictCount);
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || safeErrorCode != null) {
      map['safe_error_code'] = Variable<String>(safeErrorCode);
    }
    if (!nullToAbsent || safeErrorMessage != null) {
      map['safe_error_message'] = Variable<String>(safeErrorMessage);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    map['finished_at'] = Variable<DateTime>(finishedAt);
    return map;
  }

  SyncPullLogsCompanion toCompanion(bool nullToAbsent) {
    return SyncPullLogsCompanion(
      id: Value(id),
      actorUserId: Value(actorUserId),
      scopeFingerprint: scopeFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(scopeFingerprint),
      fromCursor: Value(fromCursor),
      toCursor: Value(toCursor),
      changeCount: Value(changeCount),
      tombstoneCount: Value(tombstoneCount),
      conflictCount: Value(conflictCount),
      outcome: Value(outcome),
      safeErrorCode: safeErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(safeErrorCode),
      safeErrorMessage: safeErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(safeErrorMessage),
      startedAt: Value(startedAt),
      finishedAt: Value(finishedAt),
    );
  }

  factory SyncPullLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPullLogRow(
      id: serializer.fromJson<String>(json['id']),
      actorUserId: serializer.fromJson<String>(json['actorUserId']),
      scopeFingerprint: serializer.fromJson<String?>(json['scopeFingerprint']),
      fromCursor: serializer.fromJson<int>(json['fromCursor']),
      toCursor: serializer.fromJson<int>(json['toCursor']),
      changeCount: serializer.fromJson<int>(json['changeCount']),
      tombstoneCount: serializer.fromJson<int>(json['tombstoneCount']),
      conflictCount: serializer.fromJson<int>(json['conflictCount']),
      outcome: serializer.fromJson<String>(json['outcome']),
      safeErrorCode: serializer.fromJson<String?>(json['safeErrorCode']),
      safeErrorMessage: serializer.fromJson<String?>(json['safeErrorMessage']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'actorUserId': serializer.toJson<String>(actorUserId),
      'scopeFingerprint': serializer.toJson<String?>(scopeFingerprint),
      'fromCursor': serializer.toJson<int>(fromCursor),
      'toCursor': serializer.toJson<int>(toCursor),
      'changeCount': serializer.toJson<int>(changeCount),
      'tombstoneCount': serializer.toJson<int>(tombstoneCount),
      'conflictCount': serializer.toJson<int>(conflictCount),
      'outcome': serializer.toJson<String>(outcome),
      'safeErrorCode': serializer.toJson<String?>(safeErrorCode),
      'safeErrorMessage': serializer.toJson<String?>(safeErrorMessage),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime>(finishedAt),
    };
  }

  SyncPullLogRow copyWith({
    String? id,
    String? actorUserId,
    Value<String?> scopeFingerprint = const Value.absent(),
    int? fromCursor,
    int? toCursor,
    int? changeCount,
    int? tombstoneCount,
    int? conflictCount,
    String? outcome,
    Value<String?> safeErrorCode = const Value.absent(),
    Value<String?> safeErrorMessage = const Value.absent(),
    DateTime? startedAt,
    DateTime? finishedAt,
  }) => SyncPullLogRow(
    id: id ?? this.id,
    actorUserId: actorUserId ?? this.actorUserId,
    scopeFingerprint: scopeFingerprint.present
        ? scopeFingerprint.value
        : this.scopeFingerprint,
    fromCursor: fromCursor ?? this.fromCursor,
    toCursor: toCursor ?? this.toCursor,
    changeCount: changeCount ?? this.changeCount,
    tombstoneCount: tombstoneCount ?? this.tombstoneCount,
    conflictCount: conflictCount ?? this.conflictCount,
    outcome: outcome ?? this.outcome,
    safeErrorCode: safeErrorCode.present
        ? safeErrorCode.value
        : this.safeErrorCode,
    safeErrorMessage: safeErrorMessage.present
        ? safeErrorMessage.value
        : this.safeErrorMessage,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
  );
  SyncPullLogRow copyWithCompanion(SyncPullLogsCompanion data) {
    return SyncPullLogRow(
      id: data.id.present ? data.id.value : this.id,
      actorUserId: data.actorUserId.present
          ? data.actorUserId.value
          : this.actorUserId,
      scopeFingerprint: data.scopeFingerprint.present
          ? data.scopeFingerprint.value
          : this.scopeFingerprint,
      fromCursor: data.fromCursor.present
          ? data.fromCursor.value
          : this.fromCursor,
      toCursor: data.toCursor.present ? data.toCursor.value : this.toCursor,
      changeCount: data.changeCount.present
          ? data.changeCount.value
          : this.changeCount,
      tombstoneCount: data.tombstoneCount.present
          ? data.tombstoneCount.value
          : this.tombstoneCount,
      conflictCount: data.conflictCount.present
          ? data.conflictCount.value
          : this.conflictCount,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      safeErrorCode: data.safeErrorCode.present
          ? data.safeErrorCode.value
          : this.safeErrorCode,
      safeErrorMessage: data.safeErrorMessage.present
          ? data.safeErrorMessage.value
          : this.safeErrorMessage,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPullLogRow(')
          ..write('id: $id, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('scopeFingerprint: $scopeFingerprint, ')
          ..write('fromCursor: $fromCursor, ')
          ..write('toCursor: $toCursor, ')
          ..write('changeCount: $changeCount, ')
          ..write('tombstoneCount: $tombstoneCount, ')
          ..write('conflictCount: $conflictCount, ')
          ..write('outcome: $outcome, ')
          ..write('safeErrorCode: $safeErrorCode, ')
          ..write('safeErrorMessage: $safeErrorMessage, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    actorUserId,
    scopeFingerprint,
    fromCursor,
    toCursor,
    changeCount,
    tombstoneCount,
    conflictCount,
    outcome,
    safeErrorCode,
    safeErrorMessage,
    startedAt,
    finishedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPullLogRow &&
          other.id == this.id &&
          other.actorUserId == this.actorUserId &&
          other.scopeFingerprint == this.scopeFingerprint &&
          other.fromCursor == this.fromCursor &&
          other.toCursor == this.toCursor &&
          other.changeCount == this.changeCount &&
          other.tombstoneCount == this.tombstoneCount &&
          other.conflictCount == this.conflictCount &&
          other.outcome == this.outcome &&
          other.safeErrorCode == this.safeErrorCode &&
          other.safeErrorMessage == this.safeErrorMessage &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt);
}

class SyncPullLogsCompanion extends UpdateCompanion<SyncPullLogRow> {
  final Value<String> id;
  final Value<String> actorUserId;
  final Value<String?> scopeFingerprint;
  final Value<int> fromCursor;
  final Value<int> toCursor;
  final Value<int> changeCount;
  final Value<int> tombstoneCount;
  final Value<int> conflictCount;
  final Value<String> outcome;
  final Value<String?> safeErrorCode;
  final Value<String?> safeErrorMessage;
  final Value<DateTime> startedAt;
  final Value<DateTime> finishedAt;
  final Value<int> rowid;
  const SyncPullLogsCompanion({
    this.id = const Value.absent(),
    this.actorUserId = const Value.absent(),
    this.scopeFingerprint = const Value.absent(),
    this.fromCursor = const Value.absent(),
    this.toCursor = const Value.absent(),
    this.changeCount = const Value.absent(),
    this.tombstoneCount = const Value.absent(),
    this.conflictCount = const Value.absent(),
    this.outcome = const Value.absent(),
    this.safeErrorCode = const Value.absent(),
    this.safeErrorMessage = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPullLogsCompanion.insert({
    this.id = const Value.absent(),
    required String actorUserId,
    this.scopeFingerprint = const Value.absent(),
    required int fromCursor,
    required int toCursor,
    this.changeCount = const Value.absent(),
    this.tombstoneCount = const Value.absent(),
    this.conflictCount = const Value.absent(),
    required String outcome,
    this.safeErrorCode = const Value.absent(),
    this.safeErrorMessage = const Value.absent(),
    required DateTime startedAt,
    required DateTime finishedAt,
    this.rowid = const Value.absent(),
  }) : actorUserId = Value(actorUserId),
       fromCursor = Value(fromCursor),
       toCursor = Value(toCursor),
       outcome = Value(outcome),
       startedAt = Value(startedAt),
       finishedAt = Value(finishedAt);
  static Insertable<SyncPullLogRow> custom({
    Expression<String>? id,
    Expression<String>? actorUserId,
    Expression<String>? scopeFingerprint,
    Expression<int>? fromCursor,
    Expression<int>? toCursor,
    Expression<int>? changeCount,
    Expression<int>? tombstoneCount,
    Expression<int>? conflictCount,
    Expression<String>? outcome,
    Expression<String>? safeErrorCode,
    Expression<String>? safeErrorMessage,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (actorUserId != null) 'actor_user_id': actorUserId,
      if (scopeFingerprint != null) 'scope_fingerprint': scopeFingerprint,
      if (fromCursor != null) 'from_cursor': fromCursor,
      if (toCursor != null) 'to_cursor': toCursor,
      if (changeCount != null) 'change_count': changeCount,
      if (tombstoneCount != null) 'tombstone_count': tombstoneCount,
      if (conflictCount != null) 'conflict_count': conflictCount,
      if (outcome != null) 'outcome': outcome,
      if (safeErrorCode != null) 'safe_error_code': safeErrorCode,
      if (safeErrorMessage != null) 'safe_error_message': safeErrorMessage,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPullLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? actorUserId,
    Value<String?>? scopeFingerprint,
    Value<int>? fromCursor,
    Value<int>? toCursor,
    Value<int>? changeCount,
    Value<int>? tombstoneCount,
    Value<int>? conflictCount,
    Value<String>? outcome,
    Value<String?>? safeErrorCode,
    Value<String?>? safeErrorMessage,
    Value<DateTime>? startedAt,
    Value<DateTime>? finishedAt,
    Value<int>? rowid,
  }) {
    return SyncPullLogsCompanion(
      id: id ?? this.id,
      actorUserId: actorUserId ?? this.actorUserId,
      scopeFingerprint: scopeFingerprint ?? this.scopeFingerprint,
      fromCursor: fromCursor ?? this.fromCursor,
      toCursor: toCursor ?? this.toCursor,
      changeCount: changeCount ?? this.changeCount,
      tombstoneCount: tombstoneCount ?? this.tombstoneCount,
      conflictCount: conflictCount ?? this.conflictCount,
      outcome: outcome ?? this.outcome,
      safeErrorCode: safeErrorCode ?? this.safeErrorCode,
      safeErrorMessage: safeErrorMessage ?? this.safeErrorMessage,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorUserId.present) {
      map['actor_user_id'] = Variable<String>(actorUserId.value);
    }
    if (scopeFingerprint.present) {
      map['scope_fingerprint'] = Variable<String>(scopeFingerprint.value);
    }
    if (fromCursor.present) {
      map['from_cursor'] = Variable<int>(fromCursor.value);
    }
    if (toCursor.present) {
      map['to_cursor'] = Variable<int>(toCursor.value);
    }
    if (changeCount.present) {
      map['change_count'] = Variable<int>(changeCount.value);
    }
    if (tombstoneCount.present) {
      map['tombstone_count'] = Variable<int>(tombstoneCount.value);
    }
    if (conflictCount.present) {
      map['conflict_count'] = Variable<int>(conflictCount.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (safeErrorCode.present) {
      map['safe_error_code'] = Variable<String>(safeErrorCode.value);
    }
    if (safeErrorMessage.present) {
      map['safe_error_message'] = Variable<String>(safeErrorMessage.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPullLogsCompanion(')
          ..write('id: $id, ')
          ..write('actorUserId: $actorUserId, ')
          ..write('scopeFingerprint: $scopeFingerprint, ')
          ..write('fromCursor: $fromCursor, ')
          ..write('toCursor: $toCursor, ')
          ..write('changeCount: $changeCount, ')
          ..write('tombstoneCount: $tombstoneCount, ')
          ..write('conflictCount: $conflictCount, ')
          ..write('outcome: $outcome, ')
          ..write('safeErrorCode: $safeErrorCode, ')
          ..write('safeErrorMessage: $safeErrorMessage, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $BranchesTable branches = $BranchesTable(this);
  late final $RoomsTable rooms = $RoomsTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ItemCategoriesTable itemCategories = $ItemCategoriesTable(this);
  late final $ItemsTable items = $ItemsTable(this);
  late final $ItemBatchesTable itemBatches = $ItemBatchesTable(this);
  late final $StockLocationsTable stockLocations = $StockLocationsTable(this);
  late final $StockBalancesTable stockBalances = $StockBalancesTable(this);
  late final $StockMovementsTable stockMovements = $StockMovementsTable(this);
  late final $StockOpnamesTable stockOpnames = $StockOpnamesTable(this);
  late final $StockOpnameLinesTable stockOpnameLines = $StockOpnameLinesTable(
    this,
  );
  late final $PurchaseRequestsTable purchaseRequests = $PurchaseRequestsTable(
    this,
  );
  late final $PurchaseRequestOpnamesTable purchaseRequestOpnames =
      $PurchaseRequestOpnamesTable(this);
  late final $PurchaseRequestLinesTable purchaseRequestLines =
      $PurchaseRequestLinesTable(this);
  late final $DeliveryOrdersTable deliveryOrders = $DeliveryOrdersTable(this);
  late final $DeliveryOrderLinesTable deliveryOrderLines =
      $DeliveryOrderLinesTable(this);
  late final $GoodReceiptsTable goodReceipts = $GoodReceiptsTable(this);
  late final $GoodReceiptLinesTable goodReceiptLines = $GoodReceiptLinesTable(
    this,
  );
  late final $DistributionsTable distributions = $DistributionsTable(this);
  late final $DistributionLinesTable distributionLines =
      $DistributionLinesTable(this);
  late final $DisposalsTable disposals = $DisposalsTable(this);
  late final $DisposalLinesTable disposalLines = $DisposalLinesTable(this);
  late final $ConsumptionsTable consumptions = $ConsumptionsTable(this);
  late final $ConsumptionLinesTable consumptionLines = $ConsumptionLinesTable(
    this,
  );
  late final $GoodsReturnsTable goodsReturns = $GoodsReturnsTable(this);
  late final $GoodsReturnLinesTable goodsReturnLines = $GoodsReturnLinesTable(
    this,
  );
  late final $ExportLogsTable exportLogs = $ExportLogsTable(this);
  late final $ImportLogsTable importLogs = $ImportLogsTable(this);
  late final $SyncDevicesTable syncDevices = $SyncDevicesTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $SyncEntityStatesTable syncEntityStates = $SyncEntityStatesTable(
    this,
  );
  late final $SyncAttemptLogsTable syncAttemptLogs = $SyncAttemptLogsTable(
    this,
  );
  late final $SyncConflictLogsTable syncConflictLogs = $SyncConflictLogsTable(
    this,
  );
  late final $SyncFileUploadsTable syncFileUploads = $SyncFileUploadsTable(
    this,
  );
  late final $SyncPullCursorsTable syncPullCursors = $SyncPullCursorsTable(
    this,
  );
  late final $SyncEntitySnapshotsTable syncEntitySnapshots =
      $SyncEntitySnapshotsTable(this);
  late final $SyncFieldVersionsTable syncFieldVersions =
      $SyncFieldVersionsTable(this);
  late final $SyncTombstonesTable syncTombstones = $SyncTombstonesTable(this);
  late final $SyncPullLogsTable syncPullLogs = $SyncPullLogsTable(this);
  late final Index idxStockBalancesBatched = Index(
    'idx_stock_balances_batched',
    'CREATE UNIQUE INDEX idx_stock_balances_batched ON stock_balances (location_id, item_id, batch_id) WHERE batch_id IS NOT NULL',
  );
  late final Index idxStockBalancesUnbatched = Index(
    'idx_stock_balances_unbatched',
    'CREATE UNIQUE INDEX idx_stock_balances_unbatched ON stock_balances (location_id, item_id) WHERE batch_id IS NULL',
  );
  late final Index idxStockMovementsItem = Index(
    'idx_stock_movements_item',
    'CREATE INDEX idx_stock_movements_item ON stock_movements (item_id, created_at)',
  );
  late final Index idxStockMovementsRef = Index(
    'idx_stock_movements_ref',
    'CREATE INDEX idx_stock_movements_ref ON stock_movements (ref_doc_type, ref_doc_id)',
  );
  late final Index idxStockOpnamesBranchStatus = Index(
    'idx_stock_opnames_branch_status',
    'CREATE INDEX idx_stock_opnames_branch_status ON stock_opnames (branch_id, status)',
  );
  late final Index idxStockOpnamesRoomPeriod = Index(
    'idx_stock_opnames_room_period',
    'CREATE UNIQUE INDEX idx_stock_opnames_room_period ON stock_opnames (room_id, period_year, period_week) WHERE deleted_at IS NULL',
  );
  late final Index idxStockOpnamesCountedByStatus = Index(
    'idx_stock_opnames_counted_by_status',
    'CREATE INDEX idx_stock_opnames_counted_by_status ON stock_opnames (counted_by, status)',
  );
  late final Index idxStockOpnamesDocNumber = Index(
    'idx_stock_opnames_doc_number',
    'CREATE UNIQUE INDEX idx_stock_opnames_doc_number ON stock_opnames (doc_number) WHERE deleted_at IS NULL',
  );
  late final Index idxStockOpnameLinesOpname = Index(
    'idx_stock_opname_lines_opname',
    'CREATE INDEX idx_stock_opname_lines_opname ON stock_opname_lines (opname_id)',
  );
  late final Index idxStockOpnameLinesItem = Index(
    'idx_stock_opname_lines_item',
    'CREATE INDEX idx_stock_opname_lines_item ON stock_opname_lines (item_id)',
  );
  late final Index idxStockOpnameLinesBatched = Index(
    'idx_stock_opname_lines_batched',
    'CREATE UNIQUE INDEX idx_stock_opname_lines_batched ON stock_opname_lines (opname_id, item_id, batch_id) WHERE batch_id IS NOT NULL AND deleted_at IS NULL',
  );
  late final Index idxStockOpnameLinesUnbatched = Index(
    'idx_stock_opname_lines_unbatched',
    'CREATE UNIQUE INDEX idx_stock_opname_lines_unbatched ON stock_opname_lines (opname_id, item_id) WHERE batch_id IS NULL AND deleted_at IS NULL',
  );
  late final Index idxPurchaseRequestsBranchStatus = Index(
    'idx_purchase_requests_branch_status',
    'CREATE INDEX idx_purchase_requests_branch_status ON purchase_requests (branch_id, status)',
  );
  late final Index idxPurchaseRequestsRequestedByStatus = Index(
    'idx_purchase_requests_requested_by_status',
    'CREATE INDEX idx_purchase_requests_requested_by_status ON purchase_requests (requested_by, status)',
  );
  late final Index idxPurchaseRequestsCreatedAt = Index(
    'idx_purchase_requests_created_at',
    'CREATE INDEX idx_purchase_requests_created_at ON purchase_requests (created_at)',
  );
  late final Index idxPurchaseRequestsNeededDate = Index(
    'idx_purchase_requests_needed_date',
    'CREATE INDEX idx_purchase_requests_needed_date ON purchase_requests (needed_date)',
  );
  late final Index idxPurchaseRequestsActiveBranch = Index(
    'idx_purchase_requests_active_branch',
    'CREATE UNIQUE INDEX idx_purchase_requests_active_branch ON purchase_requests (branch_id) WHERE status IN (\'submitted\', \'processing\') AND deleted_at IS NULL',
  );
  late final Index idxPurchaseRequestsDocNumber = Index(
    'idx_purchase_requests_doc_number',
    'CREATE UNIQUE INDEX idx_purchase_requests_doc_number ON purchase_requests (doc_number) WHERE deleted_at IS NULL',
  );
  late final Index idxPurchaseRequestOpnamesPr = Index(
    'idx_purchase_request_opnames_pr',
    'CREATE INDEX idx_purchase_request_opnames_pr ON purchase_request_opnames (pr_id)',
  );
  late final Index idxPurchaseRequestOpnamesOpname = Index(
    'idx_purchase_request_opnames_opname',
    'CREATE INDEX idx_purchase_request_opnames_opname ON purchase_request_opnames (opname_id)',
  );
  late final Index idxPurchaseRequestOpnamesUnique = Index(
    'idx_purchase_request_opnames_unique',
    'CREATE UNIQUE INDEX idx_purchase_request_opnames_unique ON purchase_request_opnames (pr_id, opname_id) WHERE deleted_at IS NULL',
  );
  late final Index idxPurchaseRequestLinesPr = Index(
    'idx_purchase_request_lines_pr',
    'CREATE INDEX idx_purchase_request_lines_pr ON purchase_request_lines (pr_id)',
  );
  late final Index idxPurchaseRequestLinesItem = Index(
    'idx_purchase_request_lines_item',
    'CREATE INDEX idx_purchase_request_lines_item ON purchase_request_lines (item_id)',
  );
  late final Index idxPurchaseRequestLinesItemUnique = Index(
    'idx_purchase_request_lines_item_unique',
    'CREATE UNIQUE INDEX idx_purchase_request_lines_item_unique ON purchase_request_lines (pr_id, item_id) WHERE deleted_at IS NULL',
  );
  late final Index idxDeliveryOrdersPrStatus = Index(
    'idx_delivery_orders_pr_status',
    'CREATE INDEX idx_delivery_orders_pr_status ON delivery_orders (pr_id, status)',
  );
  late final Index idxDeliveryOrdersStatusCreated = Index(
    'idx_delivery_orders_status_created',
    'CREATE INDEX idx_delivery_orders_status_created ON delivery_orders (status, created_at)',
  );
  late final Index idxDeliveryOrdersPreparedByStatus = Index(
    'idx_delivery_orders_prepared_by_status',
    'CREATE INDEX idx_delivery_orders_prepared_by_status ON delivery_orders (prepared_by, status)',
  );
  late final Index idxDeliveryOrdersShippedAt = Index(
    'idx_delivery_orders_shipped_at',
    'CREATE INDEX idx_delivery_orders_shipped_at ON delivery_orders (shipped_at)',
  );
  late final Index idxDeliveryOrdersDocNumber = Index(
    'idx_delivery_orders_doc_number',
    'CREATE UNIQUE INDEX idx_delivery_orders_doc_number ON delivery_orders (doc_number) WHERE deleted_at IS NULL',
  );
  late final Index idxDeliveryOrderLinesDo = Index(
    'idx_delivery_order_lines_do',
    'CREATE INDEX idx_delivery_order_lines_do ON delivery_order_lines (do_id)',
  );
  late final Index idxDeliveryOrderLinesPrLine = Index(
    'idx_delivery_order_lines_pr_line',
    'CREATE INDEX idx_delivery_order_lines_pr_line ON delivery_order_lines (pr_line_id)',
  );
  late final Index idxDeliveryOrderLinesItem = Index(
    'idx_delivery_order_lines_item',
    'CREATE INDEX idx_delivery_order_lines_item ON delivery_order_lines (item_id)',
  );
  late final Index idxDeliveryOrderLinesBatch = Index(
    'idx_delivery_order_lines_batch',
    'CREATE INDEX idx_delivery_order_lines_batch ON delivery_order_lines (batch_id)',
  );
  late final Index idxDeliveryOrderLinesBatched = Index(
    'idx_delivery_order_lines_batched',
    'CREATE UNIQUE INDEX idx_delivery_order_lines_batched ON delivery_order_lines (do_id, pr_line_id, batch_id) WHERE batch_id IS NOT NULL AND deleted_at IS NULL',
  );
  late final Index idxDeliveryOrderLinesUnbatched = Index(
    'idx_delivery_order_lines_unbatched',
    'CREATE UNIQUE INDEX idx_delivery_order_lines_unbatched ON delivery_order_lines (do_id, pr_line_id) WHERE batch_id IS NULL AND deleted_at IS NULL',
  );
  late final Index idxGoodReceiptsReceivedByStatus = Index(
    'idx_good_receipts_received_by_status',
    'CREATE INDEX idx_good_receipts_received_by_status ON good_receipts (received_by, status)',
  );
  late final Index idxGoodReceiptsStatusCreated = Index(
    'idx_good_receipts_status_created',
    'CREATE INDEX idx_good_receipts_status_created ON good_receipts (status, created_at)',
  );
  late final Index idxGoodReceiptsPostedAt = Index(
    'idx_good_receipts_posted_at',
    'CREATE INDEX idx_good_receipts_posted_at ON good_receipts (posted_at)',
  );
  late final Index idxGoodReceiptsDo = Index(
    'idx_good_receipts_do',
    'CREATE UNIQUE INDEX idx_good_receipts_do ON good_receipts (do_id)',
  );
  late final Index idxGoodReceiptsDocNumber = Index(
    'idx_good_receipts_doc_number',
    'CREATE UNIQUE INDEX idx_good_receipts_doc_number ON good_receipts (doc_number) WHERE deleted_at IS NULL',
  );
  late final Index idxGoodReceiptLinesGr = Index(
    'idx_good_receipt_lines_gr',
    'CREATE INDEX idx_good_receipt_lines_gr ON good_receipt_lines (gr_id)',
  );
  late final Index idxGoodReceiptLinesDoLine = Index(
    'idx_good_receipt_lines_do_line',
    'CREATE INDEX idx_good_receipt_lines_do_line ON good_receipt_lines (do_line_id)',
  );
  late final Index idxGoodReceiptLinesItem = Index(
    'idx_good_receipt_lines_item',
    'CREATE INDEX idx_good_receipt_lines_item ON good_receipt_lines (item_id)',
  );
  late final Index idxGoodReceiptLinesBatch = Index(
    'idx_good_receipt_lines_batch',
    'CREATE INDEX idx_good_receipt_lines_batch ON good_receipt_lines (batch_id)',
  );
  late final Index idxGoodReceiptLinesStatus = Index(
    'idx_good_receipt_lines_status',
    'CREATE INDEX idx_good_receipt_lines_status ON good_receipt_lines (line_status)',
  );
  late final Index idxGoodReceiptLinesUnique = Index(
    'idx_good_receipt_lines_unique',
    'CREATE UNIQUE INDEX idx_good_receipt_lines_unique ON good_receipt_lines (gr_id, do_line_id)',
  );
  late final Index idxDistributionsBranchStatus = Index(
    'idx_distributions_branch_status',
    'CREATE INDEX idx_distributions_branch_status ON distributions (branch_id, status)',
  );
  late final Index idxDistributionsDistributedByStatus = Index(
    'idx_distributions_distributed_by_status',
    'CREATE INDEX idx_distributions_distributed_by_status ON distributions (distributed_by, status)',
  );
  late final Index idxDistributionsCreatedAt = Index(
    'idx_distributions_created_at',
    'CREATE INDEX idx_distributions_created_at ON distributions (created_at)',
  );
  late final Index idxDistributionsPostedAt = Index(
    'idx_distributions_posted_at',
    'CREATE INDEX idx_distributions_posted_at ON distributions (posted_at)',
  );
  late final Index idxDistributionsDocNumber = Index(
    'idx_distributions_doc_number',
    'CREATE UNIQUE INDEX idx_distributions_doc_number ON distributions (doc_number) WHERE deleted_at IS NULL',
  );
  late final Index idxDistributionLinesDistribution = Index(
    'idx_distribution_lines_distribution',
    'CREATE INDEX idx_distribution_lines_distribution ON distribution_lines (distribution_id)',
  );
  late final Index idxDistributionLinesRoom = Index(
    'idx_distribution_lines_room',
    'CREATE INDEX idx_distribution_lines_room ON distribution_lines (room_id)',
  );
  late final Index idxDistributionLinesItem = Index(
    'idx_distribution_lines_item',
    'CREATE INDEX idx_distribution_lines_item ON distribution_lines (item_id)',
  );
  late final Index idxDistributionLinesBatch = Index(
    'idx_distribution_lines_batch',
    'CREATE INDEX idx_distribution_lines_batch ON distribution_lines (batch_id)',
  );
  late final Index idxDistributionLinesBatched = Index(
    'idx_distribution_lines_batched',
    'CREATE UNIQUE INDEX idx_distribution_lines_batched ON distribution_lines (distribution_id, room_id, item_id, batch_id) WHERE batch_id IS NOT NULL AND deleted_at IS NULL',
  );
  late final Index idxDistributionLinesUnbatched = Index(
    'idx_distribution_lines_unbatched',
    'CREATE UNIQUE INDEX idx_distribution_lines_unbatched ON distribution_lines (distribution_id, room_id, item_id) WHERE batch_id IS NULL AND deleted_at IS NULL',
  );
  late final Index idxDisposalsSourceLocationStatus = Index(
    'idx_disposals_source_location_status',
    'CREATE INDEX idx_disposals_source_location_status ON disposals (source_location_id, status)',
  );
  late final Index idxDisposalsCreatedByStatus = Index(
    'idx_disposals_created_by_status',
    'CREATE INDEX idx_disposals_created_by_status ON disposals (created_by, status)',
  );
  late final Index idxDisposalsPostedByStatus = Index(
    'idx_disposals_posted_by_status',
    'CREATE INDEX idx_disposals_posted_by_status ON disposals (posted_by, status)',
  );
  late final Index idxDisposalsCreatedAt = Index(
    'idx_disposals_created_at',
    'CREATE INDEX idx_disposals_created_at ON disposals (created_at)',
  );
  late final Index idxDisposalsPostedAt = Index(
    'idx_disposals_posted_at',
    'CREATE INDEX idx_disposals_posted_at ON disposals (posted_at)',
  );
  late final Index idxDisposalsDocNumber = Index(
    'idx_disposals_doc_number',
    'CREATE UNIQUE INDEX idx_disposals_doc_number ON disposals (doc_number)',
  );
  late final Index idxDisposalLinesDisposal = Index(
    'idx_disposal_lines_disposal',
    'CREATE INDEX idx_disposal_lines_disposal ON disposal_lines (disposal_id)',
  );
  late final Index idxDisposalLinesItem = Index(
    'idx_disposal_lines_item',
    'CREATE INDEX idx_disposal_lines_item ON disposal_lines (item_id)',
  );
  late final Index idxDisposalLinesBatch = Index(
    'idx_disposal_lines_batch',
    'CREATE INDEX idx_disposal_lines_batch ON disposal_lines (batch_id)',
  );
  late final Index idxDisposalLinesPosition = Index(
    'idx_disposal_lines_position',
    'CREATE UNIQUE INDEX idx_disposal_lines_position ON disposal_lines (disposal_id, item_id, batch_id) WHERE deleted_at IS NULL',
  );
  late final Index idxConsumptionsBranchStatus = Index(
    'idx_consumptions_branch_status',
    'CREATE INDEX idx_consumptions_branch_status ON consumptions (branch_id, status)',
  );
  late final Index idxConsumptionsRoomStatus = Index(
    'idx_consumptions_room_status',
    'CREATE INDEX idx_consumptions_room_status ON consumptions (room_id, status)',
  );
  late final Index idxConsumptionsCreatedByStatus = Index(
    'idx_consumptions_created_by_status',
    'CREATE INDEX idx_consumptions_created_by_status ON consumptions (created_by, status)',
  );
  late final Index idxConsumptionsPostedByStatus = Index(
    'idx_consumptions_posted_by_status',
    'CREATE INDEX idx_consumptions_posted_by_status ON consumptions (posted_by, status)',
  );
  late final Index idxConsumptionsCreatedAt = Index(
    'idx_consumptions_created_at',
    'CREATE INDEX idx_consumptions_created_at ON consumptions (created_at)',
  );
  late final Index idxConsumptionsPostedAt = Index(
    'idx_consumptions_posted_at',
    'CREATE INDEX idx_consumptions_posted_at ON consumptions (posted_at)',
  );
  late final Index idxConsumptionsDocNumber = Index(
    'idx_consumptions_doc_number',
    'CREATE UNIQUE INDEX idx_consumptions_doc_number ON consumptions (doc_number)',
  );
  late final Index idxConsumptionLinesConsumption = Index(
    'idx_consumption_lines_consumption',
    'CREATE INDEX idx_consumption_lines_consumption ON consumption_lines (consumption_id)',
  );
  late final Index idxConsumptionLinesItem = Index(
    'idx_consumption_lines_item',
    'CREATE INDEX idx_consumption_lines_item ON consumption_lines (item_id)',
  );
  late final Index idxConsumptionLinesBatch = Index(
    'idx_consumption_lines_batch',
    'CREATE INDEX idx_consumption_lines_batch ON consumption_lines (batch_id)',
  );
  late final Index idxConsumptionLinesBatched = Index(
    'idx_consumption_lines_batched',
    'CREATE UNIQUE INDEX idx_consumption_lines_batched ON consumption_lines (consumption_id, item_id, batch_id) WHERE batch_id IS NOT NULL AND deleted_at IS NULL',
  );
  late final Index idxConsumptionLinesUnbatched = Index(
    'idx_consumption_lines_unbatched',
    'CREATE UNIQUE INDEX idx_consumption_lines_unbatched ON consumption_lines (consumption_id, item_id) WHERE batch_id IS NULL AND deleted_at IS NULL',
  );
  late final Index idxGoodsReturnsBranchStatus = Index(
    'idx_goods_returns_branch_status',
    'CREATE INDEX idx_goods_returns_branch_status ON goods_returns (branch_id, status)',
  );
  late final Index idxGoodsReturnsCreatedByStatus = Index(
    'idx_goods_returns_created_by_status',
    'CREATE INDEX idx_goods_returns_created_by_status ON goods_returns (created_by, status)',
  );
  late final Index idxGoodsReturnsShippedByStatus = Index(
    'idx_goods_returns_shipped_by_status',
    'CREATE INDEX idx_goods_returns_shipped_by_status ON goods_returns (shipped_by, status)',
  );
  late final Index idxGoodsReturnsReceivedByStatus = Index(
    'idx_goods_returns_received_by_status',
    'CREATE INDEX idx_goods_returns_received_by_status ON goods_returns (received_by, status)',
  );
  late final Index idxGoodsReturnsCreatedAt = Index(
    'idx_goods_returns_created_at',
    'CREATE INDEX idx_goods_returns_created_at ON goods_returns (created_at)',
  );
  late final Index idxGoodsReturnsShippedAt = Index(
    'idx_goods_returns_shipped_at',
    'CREATE INDEX idx_goods_returns_shipped_at ON goods_returns (shipped_at)',
  );
  late final Index idxGoodsReturnsReceivedAt = Index(
    'idx_goods_returns_received_at',
    'CREATE INDEX idx_goods_returns_received_at ON goods_returns (received_at)',
  );
  late final Index idxGoodsReturnsGr = Index(
    'idx_goods_returns_gr',
    'CREATE UNIQUE INDEX idx_goods_returns_gr ON goods_returns (gr_id)',
  );
  late final Index idxGoodsReturnsDocNumber = Index(
    'idx_goods_returns_doc_number',
    'CREATE UNIQUE INDEX idx_goods_returns_doc_number ON goods_returns (doc_number)',
  );
  late final Index idxGoodsReturnLinesReturn = Index(
    'idx_goods_return_lines_return',
    'CREATE INDEX idx_goods_return_lines_return ON goods_return_lines (goods_return_id)',
  );
  late final Index idxGoodsReturnLinesGrLine = Index(
    'idx_goods_return_lines_gr_line',
    'CREATE INDEX idx_goods_return_lines_gr_line ON goods_return_lines (gr_line_id)',
  );
  late final Index idxGoodsReturnLinesItem = Index(
    'idx_goods_return_lines_item',
    'CREATE INDEX idx_goods_return_lines_item ON goods_return_lines (item_id)',
  );
  late final Index idxGoodsReturnLinesBatch = Index(
    'idx_goods_return_lines_batch',
    'CREATE INDEX idx_goods_return_lines_batch ON goods_return_lines (batch_id)',
  );
  late final Index idxGoodsReturnLinesGrLineUnique = Index(
    'idx_goods_return_lines_gr_line_unique',
    'CREATE UNIQUE INDEX idx_goods_return_lines_gr_line_unique ON goods_return_lines (gr_line_id)',
  );
  late final Index idxGoodsReturnLinesUnique = Index(
    'idx_goods_return_lines_unique',
    'CREATE UNIQUE INDEX idx_goods_return_lines_unique ON goods_return_lines (goods_return_id, gr_line_id)',
  );
  late final Index idxExportLogsActor = Index(
    'idx_export_logs_actor',
    'CREATE INDEX idx_export_logs_actor ON export_logs (exported_by, created_at)',
  );
  late final Index idxExportLogsType = Index(
    'idx_export_logs_type',
    'CREATE INDEX idx_export_logs_type ON export_logs (report_type, created_at)',
  );
  late final Index idxExportLogsFormat = Index(
    'idx_export_logs_format',
    'CREATE INDEX idx_export_logs_format ON export_logs (format, created_at)',
  );
  late final Index idxExportLogsScope = Index(
    'idx_export_logs_scope',
    'CREATE INDEX idx_export_logs_scope ON export_logs (scope_type, created_at)',
  );
  late final Index idxExportLogsBranch = Index(
    'idx_export_logs_branch',
    'CREATE INDEX idx_export_logs_branch ON export_logs (branch_id, created_at)',
  );
  late final Index idxExportLogsLocation = Index(
    'idx_export_logs_location',
    'CREATE INDEX idx_export_logs_location ON export_logs (location_id, created_at)',
  );
  late final Index idxExportLogsCategory = Index(
    'idx_export_logs_category',
    'CREATE INDEX idx_export_logs_category ON export_logs (category_id, created_at)',
  );
  late final Index idxExportLogsItem = Index(
    'idx_export_logs_item',
    'CREATE INDEX idx_export_logs_item ON export_logs (item_id, created_at)',
  );
  late final Index idxExportLogsCreatedAt = Index(
    'idx_export_logs_created_at',
    'CREATE INDEX idx_export_logs_created_at ON export_logs (created_at)',
  );
  late final Index idxImportLogsEntityStatus = Index(
    'idx_import_logs_entity_status',
    'CREATE INDEX idx_import_logs_entity_status ON import_logs (entity, status, created_at)',
  );
  late final Index idxImportLogsStatus = Index(
    'idx_import_logs_status',
    'CREATE INDEX idx_import_logs_status ON import_logs (status, created_at)',
  );
  late final Index idxImportLogsActor = Index(
    'idx_import_logs_actor',
    'CREATE INDEX idx_import_logs_actor ON import_logs (imported_by, created_at)',
  );
  late final Index idxImportLogsCreatedAt = Index(
    'idx_import_logs_created_at',
    'CREATE INDEX idx_import_logs_created_at ON import_logs (created_at)',
  );
  late final Index idxImportLogsSha256 = Index(
    'idx_import_logs_sha256',
    'CREATE INDEX idx_import_logs_sha256 ON import_logs (file_sha256)',
  );
  late final Index idxImportLogsSync = Index(
    'idx_import_logs_sync',
    'CREATE INDEX idx_import_logs_sync ON import_logs (sync_status, created_at)',
  );
  late final Index idxSyncDevicesInstall = Index(
    'idx_sync_devices_install',
    'CREATE UNIQUE INDEX idx_sync_devices_install ON sync_devices (app_install_id)',
  );
  late final Index idxSyncOutboxDue = Index(
    'idx_sync_outbox_due',
    'CREATE INDEX idx_sync_outbox_due ON sync_outbox (status, next_attempt_epoch_ms)',
  );
  late final Index idxSyncOutboxActorStatus = Index(
    'idx_sync_outbox_actor_status',
    'CREATE INDEX idx_sync_outbox_actor_status ON sync_outbox (actor_user_id, status)',
  );
  late final Index idxSyncOutboxAggregate = Index(
    'idx_sync_outbox_aggregate',
    'CREATE INDEX idx_sync_outbox_aggregate ON sync_outbox (aggregate_type, aggregate_id)',
  );
  late final Index idxSyncOutboxRequest = Index(
    'idx_sync_outbox_request',
    'CREATE UNIQUE INDEX idx_sync_outbox_request ON sync_outbox (request_id)',
  );
  late final Index idxSyncOutboxDevice = Index(
    'idx_sync_outbox_device',
    'CREATE INDEX idx_sync_outbox_device ON sync_outbox (device_id)',
  );
  late final Index idxSyncEntityStatesAggregate = Index(
    'idx_sync_entity_states_aggregate',
    'CREATE UNIQUE INDEX idx_sync_entity_states_aggregate ON sync_entity_states (aggregate_type, aggregate_id)',
  );
  late final Index idxSyncAttemptLogsRequest = Index(
    'idx_sync_attempt_logs_request',
    'CREATE INDEX idx_sync_attempt_logs_request ON sync_attempt_logs (request_id, attempt_number)',
  );
  late final Index idxSyncConflictLogsRequest = Index(
    'idx_sync_conflict_logs_request',
    'CREATE INDEX idx_sync_conflict_logs_request ON sync_conflict_logs (request_id)',
  );
  late final Index idxSyncConflictLogsAggregate = Index(
    'idx_sync_conflict_logs_aggregate',
    'CREATE INDEX idx_sync_conflict_logs_aggregate ON sync_conflict_logs (aggregate_type, aggregate_id)',
  );
  late final Index idxSyncFileUploadsRequest = Index(
    'idx_sync_file_uploads_request',
    'CREATE UNIQUE INDEX idx_sync_file_uploads_request ON sync_file_uploads (request_id)',
  );
  late final Index idxSyncFileUploadsStatus = Index(
    'idx_sync_file_uploads_status',
    'CREATE INDEX idx_sync_file_uploads_status ON sync_file_uploads (status)',
  );
  late final Index idxSyncFileUploadsActorStatus = Index(
    'idx_sync_file_uploads_actor_status',
    'CREATE INDEX idx_sync_file_uploads_actor_status ON sync_file_uploads (actor_user_id, status)',
  );
  late final Index idxSyncPullCursorsScope = Index(
    'idx_sync_pull_cursors_scope',
    'CREATE UNIQUE INDEX idx_sync_pull_cursors_scope ON sync_pull_cursors (actor_user_id, scope_fingerprint)',
  );
  late final Index idxSyncEntitySnapshotsEntity = Index(
    'idx_sync_entity_snapshots_entity',
    'CREATE UNIQUE INDEX idx_sync_entity_snapshots_entity ON sync_entity_snapshots (entity_type, entity_id)',
  );
  late final Index idxSyncFieldVersionsField = Index(
    'idx_sync_field_versions_field',
    'CREATE UNIQUE INDEX idx_sync_field_versions_field ON sync_field_versions (entity_type, entity_id, field_name)',
  );
  late final Index idxSyncTombstonesEntity = Index(
    'idx_sync_tombstones_entity',
    'CREATE UNIQUE INDEX idx_sync_tombstones_entity ON sync_tombstones (entity_type, entity_id)',
  );
  late final Index idxSyncPullLogsFinished = Index(
    'idx_sync_pull_logs_finished',
    'CREATE INDEX idx_sync_pull_logs_finished ON sync_pull_logs (finished_at)',
  );
  late final Index idxSyncPullLogsActor = Index(
    'idx_sync_pull_logs_actor',
    'CREATE INDEX idx_sync_pull_logs_actor ON sync_pull_logs (actor_user_id)',
  );
  late final MasterDataDao masterDataDao = MasterDataDao(this as AppDatabase);
  late final MasterAdminDao masterAdminDao = MasterAdminDao(
    this as AppDatabase,
  );
  late final InventoryDao inventoryDao = InventoryDao(this as AppDatabase);
  late final OpnameDao opnameDao = OpnameDao(this as AppDatabase);
  late final PurchaseRequestDao purchaseRequestDao = PurchaseRequestDao(
    this as AppDatabase,
  );
  late final DeliveryOrderDao deliveryOrderDao = DeliveryOrderDao(
    this as AppDatabase,
  );
  late final GoodReceiptDao goodReceiptDao = GoodReceiptDao(
    this as AppDatabase,
  );
  late final DistributionDao distributionDao = DistributionDao(
    this as AppDatabase,
  );
  late final DisposalDao disposalDao = DisposalDao(this as AppDatabase);
  late final ConsumptionDao consumptionDao = ConsumptionDao(
    this as AppDatabase,
  );
  late final GoodsReturnDao goodsReturnDao = GoodsReturnDao(
    this as AppDatabase,
  );
  late final ReportingDao reportingDao = ReportingDao(this as AppDatabase);
  late final SyncDao syncDao = SyncDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    branches,
    rooms,
    users,
    itemCategories,
    items,
    itemBatches,
    stockLocations,
    stockBalances,
    stockMovements,
    stockOpnames,
    stockOpnameLines,
    purchaseRequests,
    purchaseRequestOpnames,
    purchaseRequestLines,
    deliveryOrders,
    deliveryOrderLines,
    goodReceipts,
    goodReceiptLines,
    distributions,
    distributionLines,
    disposals,
    disposalLines,
    consumptions,
    consumptionLines,
    goodsReturns,
    goodsReturnLines,
    exportLogs,
    importLogs,
    syncDevices,
    syncOutbox,
    syncEntityStates,
    syncAttemptLogs,
    syncConflictLogs,
    syncFileUploads,
    syncPullCursors,
    syncEntitySnapshots,
    syncFieldVersions,
    syncTombstones,
    syncPullLogs,
    idxStockBalancesBatched,
    idxStockBalancesUnbatched,
    idxStockMovementsItem,
    idxStockMovementsRef,
    idxStockOpnamesBranchStatus,
    idxStockOpnamesRoomPeriod,
    idxStockOpnamesCountedByStatus,
    idxStockOpnamesDocNumber,
    idxStockOpnameLinesOpname,
    idxStockOpnameLinesItem,
    idxStockOpnameLinesBatched,
    idxStockOpnameLinesUnbatched,
    idxPurchaseRequestsBranchStatus,
    idxPurchaseRequestsRequestedByStatus,
    idxPurchaseRequestsCreatedAt,
    idxPurchaseRequestsNeededDate,
    idxPurchaseRequestsActiveBranch,
    idxPurchaseRequestsDocNumber,
    idxPurchaseRequestOpnamesPr,
    idxPurchaseRequestOpnamesOpname,
    idxPurchaseRequestOpnamesUnique,
    idxPurchaseRequestLinesPr,
    idxPurchaseRequestLinesItem,
    idxPurchaseRequestLinesItemUnique,
    idxDeliveryOrdersPrStatus,
    idxDeliveryOrdersStatusCreated,
    idxDeliveryOrdersPreparedByStatus,
    idxDeliveryOrdersShippedAt,
    idxDeliveryOrdersDocNumber,
    idxDeliveryOrderLinesDo,
    idxDeliveryOrderLinesPrLine,
    idxDeliveryOrderLinesItem,
    idxDeliveryOrderLinesBatch,
    idxDeliveryOrderLinesBatched,
    idxDeliveryOrderLinesUnbatched,
    idxGoodReceiptsReceivedByStatus,
    idxGoodReceiptsStatusCreated,
    idxGoodReceiptsPostedAt,
    idxGoodReceiptsDo,
    idxGoodReceiptsDocNumber,
    idxGoodReceiptLinesGr,
    idxGoodReceiptLinesDoLine,
    idxGoodReceiptLinesItem,
    idxGoodReceiptLinesBatch,
    idxGoodReceiptLinesStatus,
    idxGoodReceiptLinesUnique,
    idxDistributionsBranchStatus,
    idxDistributionsDistributedByStatus,
    idxDistributionsCreatedAt,
    idxDistributionsPostedAt,
    idxDistributionsDocNumber,
    idxDistributionLinesDistribution,
    idxDistributionLinesRoom,
    idxDistributionLinesItem,
    idxDistributionLinesBatch,
    idxDistributionLinesBatched,
    idxDistributionLinesUnbatched,
    idxDisposalsSourceLocationStatus,
    idxDisposalsCreatedByStatus,
    idxDisposalsPostedByStatus,
    idxDisposalsCreatedAt,
    idxDisposalsPostedAt,
    idxDisposalsDocNumber,
    idxDisposalLinesDisposal,
    idxDisposalLinesItem,
    idxDisposalLinesBatch,
    idxDisposalLinesPosition,
    idxConsumptionsBranchStatus,
    idxConsumptionsRoomStatus,
    idxConsumptionsCreatedByStatus,
    idxConsumptionsPostedByStatus,
    idxConsumptionsCreatedAt,
    idxConsumptionsPostedAt,
    idxConsumptionsDocNumber,
    idxConsumptionLinesConsumption,
    idxConsumptionLinesItem,
    idxConsumptionLinesBatch,
    idxConsumptionLinesBatched,
    idxConsumptionLinesUnbatched,
    idxGoodsReturnsBranchStatus,
    idxGoodsReturnsCreatedByStatus,
    idxGoodsReturnsShippedByStatus,
    idxGoodsReturnsReceivedByStatus,
    idxGoodsReturnsCreatedAt,
    idxGoodsReturnsShippedAt,
    idxGoodsReturnsReceivedAt,
    idxGoodsReturnsGr,
    idxGoodsReturnsDocNumber,
    idxGoodsReturnLinesReturn,
    idxGoodsReturnLinesGrLine,
    idxGoodsReturnLinesItem,
    idxGoodsReturnLinesBatch,
    idxGoodsReturnLinesGrLineUnique,
    idxGoodsReturnLinesUnique,
    idxExportLogsActor,
    idxExportLogsType,
    idxExportLogsFormat,
    idxExportLogsScope,
    idxExportLogsBranch,
    idxExportLogsLocation,
    idxExportLogsCategory,
    idxExportLogsItem,
    idxExportLogsCreatedAt,
    idxImportLogsEntityStatus,
    idxImportLogsStatus,
    idxImportLogsActor,
    idxImportLogsCreatedAt,
    idxImportLogsSha256,
    idxImportLogsSync,
    idxSyncDevicesInstall,
    idxSyncOutboxDue,
    idxSyncOutboxActorStatus,
    idxSyncOutboxAggregate,
    idxSyncOutboxRequest,
    idxSyncOutboxDevice,
    idxSyncEntityStatesAggregate,
    idxSyncAttemptLogsRequest,
    idxSyncConflictLogsRequest,
    idxSyncConflictLogsAggregate,
    idxSyncFileUploadsRequest,
    idxSyncFileUploadsStatus,
    idxSyncFileUploadsActorStatus,
    idxSyncPullCursorsScope,
    idxSyncEntitySnapshotsEntity,
    idxSyncFieldVersionsField,
    idxSyncTombstonesEntity,
    idxSyncPullLogsFinished,
    idxSyncPullLogsActor,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}
