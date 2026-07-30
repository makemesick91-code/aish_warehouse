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
  late final MasterDataDao masterDataDao = MasterDataDao(this as AppDatabase);
  late final InventoryDao inventoryDao = InventoryDao(this as AppDatabase);
  late final OpnameDao opnameDao = OpnameDao(this as AppDatabase);
  late final PurchaseRequestDao purchaseRequestDao = PurchaseRequestDao(
    this as AppDatabase,
  );
  late final DeliveryOrderDao deliveryOrderDao = DeliveryOrderDao(
    this as AppDatabase,
  );
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
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}
