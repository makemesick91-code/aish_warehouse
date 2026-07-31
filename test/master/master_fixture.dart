import 'dart:typed_data';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/master/data/import/excel_master_import_workbook_parser.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_admin_repository.dart';
import 'package:aish_warehouse/features/master/data/templates/excel_master_template_generator.dart';
import 'package:aish_warehouse/features/master/domain/gateways/master_import_gateways.dart';
import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/repositories/master_admin_repository.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_workbook_validator.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/batch_crud_use_cases.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/branch_crud_use_cases.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/category_crud_use_cases.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/commit_master_import_use_case.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/download_master_template_use_case.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/item_crud_use_cases.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/room_crud_use_cases.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/user_crud_use_cases.dart';
import 'package:aish_warehouse/features/master/domain/use_cases/validate_master_import_use_case.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:excel/excel.dart';

/// In-memory wiring of the master-administration and import stack.
///
/// The three things a unit test cannot do — render a workbook to disk, open a
/// share sheet, open a file picker — are all behind gateways, and this hands in
/// fakes by default. The `.xlsx` bytes themselves are **real**: the template
/// generator and the workbook parser are the production ones, so a round trip
/// through this fixture proves the file this application writes is the file it
/// reads.
class MasterFixture {
  MasterFixture._({
    required this.database,
    required this.repository,
    required this.sourceFileStore,
    required this.templateFileStore,
    required this.shareGateway,
    required this.clock,
  });

  factory MasterFixture.create({
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) {
    final database = AppDatabase(NativeDatabase.memory());
    return MasterFixture._(
      database: database,
      repository: DriftMasterAdminRepository(
        database.masterAdminDao,
        clock: clock,
        idGenerator: idGenerator,
      ),
      sourceFileStore: InMemoryImportSourceFileStore(),
      templateFileStore: InMemoryMasterTemplateFileStore(),
      shareGateway: FakeMasterTemplateShareGateway(),
      clock: clock,
    );
  }

  final AppDatabase database;
  final MasterAdminRepository repository;
  final InMemoryImportSourceFileStore sourceFileStore;
  final InMemoryMasterTemplateFileStore templateFileStore;
  final FakeMasterTemplateShareGateway shareGateway;
  final DateTime Function()? clock;

  static const workbookReader = ExcelMasterImportWorkbookReader();

  Future<void> dispose() => database.close();

  // --- use case factories ------------------------------------------------------

  CreateBranchUseCase get createBranch =>
      CreateBranchUseCase(repository: repository);
  UpdateBranchUseCase get updateBranch =>
      UpdateBranchUseCase(repository: repository);
  SetBranchActiveUseCase get setBranchActive =>
      SetBranchActiveUseCase(repository: repository);

  CreateRoomUseCase get createRoom => CreateRoomUseCase(repository: repository);
  UpdateRoomUseCase get updateRoom => UpdateRoomUseCase(repository: repository);
  SetRoomActiveUseCase get setRoomActive =>
      SetRoomActiveUseCase(repository: repository);

  CreateUserUseCase get createUser => CreateUserUseCase(repository: repository);
  UpdateUserUseCase get updateUser => UpdateUserUseCase(repository: repository);
  SetUserActiveUseCase get setUserActive =>
      SetUserActiveUseCase(repository: repository);

  CreateItemCategoryUseCase get createCategory =>
      CreateItemCategoryUseCase(repository: repository);
  UpdateItemCategoryUseCase get updateCategory =>
      UpdateItemCategoryUseCase(repository: repository);
  ArchiveItemCategoryUseCase get archiveCategory =>
      ArchiveItemCategoryUseCase(repository: repository);
  RestoreItemCategoryUseCase get restoreCategory =>
      RestoreItemCategoryUseCase(repository: repository);

  CreateItemUseCase get createItem => CreateItemUseCase(repository: repository);
  UpdateItemUseCase get updateItem => UpdateItemUseCase(repository: repository);
  SetItemActiveUseCase get setItemActive =>
      SetItemActiveUseCase(repository: repository);

  CreateItemBatchUseCase get createBatch =>
      CreateItemBatchUseCase(repository: repository);
  UpdateItemBatchUseCase get updateBatch =>
      UpdateItemBatchUseCase(repository: repository);
  ArchiveItemBatchUseCase get archiveBatch =>
      ArchiveItemBatchUseCase(repository: repository);
  RestoreItemBatchUseCase get restoreBatch =>
      RestoreItemBatchUseCase(repository: repository);

  DownloadMasterTemplateUseCase downloadTemplate({
    MasterTemplateGenerator? generator,
    MasterTemplateFileStore? fileStore,
    MasterTemplateShareGateway? share,
    DateTime Function()? clock,
  }) => DownloadMasterTemplateUseCase(
    repository: repository,
    generator: generator ?? const ExcelMasterTemplateGenerator(),
    fileStore: fileStore ?? templateFileStore,
    shareGateway: share ?? shareGateway,
    clock: clock ?? this.clock,
  );

  ValidateMasterImportUseCase validateImport({
    ImportSourceFileStore? store,
    MasterImportWorkbookReader? reader,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => ValidateMasterImportUseCase(
    repository: repository,
    workbookReader: reader ?? workbookReader,
    sourceFileStore: store ?? sourceFileStore,
    clock: clock ?? this.clock,
    idGenerator: idGenerator,
  );

  CommitMasterImportUseCase commitImport({
    ImportSourceFileStore? store,
    MasterImportWorkbookReader? reader,
    MasterAdminRepository? repositoryOverride,
    DateTime Function()? clock,
  }) => CommitMasterImportUseCase(
    repository: repositoryOverride ?? repository,
    workbookReader: reader ?? workbookReader,
    sourceFileStore: store ?? sourceFileStore,
    clock: clock ?? this.clock,
  );

  DiscardMasterImportUseCase discardImport({DateTime Function()? clock}) =>
      DiscardMasterImportUseCase(
        repository: repository,
        clock: clock ?? this.clock,
      );

  WatchImportHistoryUseCase get watchImportHistory =>
      WatchImportHistoryUseCase(repository: repository);

  GetImportLogDetailUseCase get importLogDetail =>
      GetImportLogDetailUseCase(repository: repository);

  // --- seeding -------------------------------------------------------------------
  //
  // Deliberately raw SQL for the actor: the production API has no way to create
  // the *first* Super Admin — every writer requires an existing one — and adding
  // a bootstrap writer so a test could reach the state would mean shipping the
  // one API G-M1 exists to withhold.

  Future<String> seedSuperAdmin({
    String id = 'actor-super-admin',
    String email = 'admin@aish.id',
    String fullName = 'Super Admin',
    bool isActive = true,
  }) async {
    await _insertUser(
      id: id,
      email: email,
      fullName: fullName,
      role: UserRole.superAdmin,
      isActive: isActive,
    );
    return id;
  }

  Future<String> seedUser({
    required String id,
    required String email,
    required UserRole role,
    String fullName = 'Pengguna',
    String? branchId,
    bool isActive = true,
  }) async {
    await _insertUser(
      id: id,
      email: email,
      fullName: fullName,
      role: role,
      branchId: branchId,
      isActive: isActive,
    );
    return id;
  }

  Future<void> _insertUser({
    required String id,
    required String email,
    required String fullName,
    required UserRole role,
    String? branchId,
    required bool isActive,
  }) async {
    const stamp = '2026-07-01T00:00:00.000Z';
    await database.customStatement(
      'INSERT INTO users (id, created_at, updated_at, sync_status, full_name, '
      'email, role, branch_id, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        stamp,
        stamp,
        SyncStatus.pending.dbValue,
        fullName,
        email,
        role.dbValue,
        branchId,
        isActive ? 1 : 0,
      ],
    );
  }

  // --- raw reads, so a rollback assertion cannot be fooled by a cache ------------

  Future<int> countOf(String table) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM $table;')
        .getSingle();
    return row.read<int>('c');
  }

  /// A snapshot of every row count G-M3 says a preview may not change.
  Future<Map<String, int>> masterCounts() async => <String, int>{
    for (final table in const [
      'branches',
      'rooms',
      'users',
      'item_categories',
      'items',
      'item_batches',
      'stock_locations',
      'stock_balances',
      'stock_movements',
      'stock_opnames',
      'stock_opname_lines',
      'purchase_requests',
      'purchase_request_lines',
      'delivery_orders',
      'delivery_order_lines',
      'good_receipts',
      'good_receipt_lines',
      'distributions',
      'distribution_lines',
      'disposals',
      'disposal_lines',
      'consumptions',
      'consumption_lines',
      'goods_returns',
      'goods_return_lines',
    ])
      table: await countOf(table),
  };

  /// Every column of every master table that a preview must leave byte-identical.
  ///
  /// Counts alone would not catch an UPDATE, and "no master mutation" is exactly
  /// the claim G-M3 makes.
  Future<String> masterFingerprint() async {
    final buffer = StringBuffer();
    for (final table in const [
      'branches',
      'rooms',
      'users',
      'item_categories',
      'items',
      'item_batches',
      'stock_locations',
    ]) {
      final rows = await database
          .customSelect('SELECT * FROM $table ORDER BY id;')
          .get();
      buffer.write('[$table]');
      for (final row in rows) {
        buffer.write(row.data.toString());
      }
    }
    return buffer.toString();
  }

  Future<List<Map<String, Object?>>> importLogRows() async {
    final rows = await database
        .customSelect(
          'SELECT id, entity, file_name, total_rows, inserted_rows, '
          'updated_rows, failed_rows, error_detail, status, imported_by, '
          'stored_file_path, file_sha256, file_size_bytes, template_version, '
          'sync_status, created_at, updated_at, deleted_at FROM import_logs '
          'ORDER BY created_at, id;',
        )
        .get();
    return rows.map((row) => row.data).toList(growable: false);
  }

  Future<String?> importLogColumn(String id, String column) async {
    final row = await database
        .customSelect(
          'SELECT $column AS value FROM import_logs WHERE id = ?;',
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return row.read<String?>('value');
  }

  Future<String?> columnOf(String table, String id, String column) async {
    final row = await database
        .customSelect(
          'SELECT $column AS value FROM $table WHERE id = ?;',
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return row.read<String?>('value');
  }

  /// `is_active = 0`, bypassing every Dart layer.
  Future<void> deactivateRaw(String table, String id) => database
      .customStatement('UPDATE $table SET is_active = 0 WHERE id = ?;', [id]);

  /// `deleted_at = <now>`, bypassing every Dart layer.
  Future<void> archiveRaw(String table, String id) => database.customStatement(
    'UPDATE $table SET deleted_at = ? WHERE id = ?;',
    [DateTime.utc(2026, 7, 30).toIso8601String(), id],
  );

  /// Inserts a second row whose natural key differs only in case.
  ///
  /// Deliberately raw SQL: the production API refuses it, which is precisely why
  /// the ambiguity rule of §17 needs a helper to be reachable at all. A sync
  /// payload or a hand-edited database can produce this state.
  Future<void> insertCaseVariantItem({
    required String id,
    required String sku,
    required String categoryId,
    String name = 'Varian',
    String unit = 'pcs',
  }) async {
    const stamp = '2026-07-01T00:00:00.000Z';
    await database.customStatement(
      'INSERT INTO items (id, created_at, updated_at, sync_status, sku, name, '
      'category_id, unit, min_stock_room, min_stock_branch, has_expiry, '
      'expiry_alert_days, is_active) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 30, 1);',
      [id, stamp, stamp, 'pending', sku, name, categoryId, unit],
    );
  }

  /// Writes a ledger movement so an item or batch counts as *used* (G-M5).
  ///
  /// Raw SQL because posting a real movement needs a document, a location and a
  /// quantity this fixture does not otherwise care about — and because
  /// `stock_movements` has no writer outside the posting service by design.
  Future<void> markItemUsed({
    required String itemId,
    String? batchId,
    required String actorUserId,
    String movementId = 'mov-1',
  }) async {
    const stamp = '2026-07-05T00:00:00.000Z';
    // `stock_movements` CHECKs that at least one side is a location — goods have
    // to come from somewhere or go somewhere — so an inbound needs a warehouse
    // to arrive at. Created here rather than assumed, and reused across calls.
    final locationId = await _ensureWarehouseLocation();
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, batch_id, to_location_id, qty, movement_type, actor_user_id) '
      "VALUES (?, ?, ?, 'pending', ?, ?, ?, 1000, 'inbound_warehouse', ?);",
      [movementId, stamp, stamp, itemId, batchId, locationId, actorUserId],
    );
  }

  Future<String> _ensureWarehouseLocation() async {
    final existing = await database
        .customSelect(
          "SELECT id FROM stock_locations WHERE type = 'warehouse' LIMIT 1;",
        )
        .get();
    if (existing.isNotEmpty) return existing.single.read<String>('id');
    const stamp = '2026-07-01T00:00:00.000Z';
    await database.customStatement(
      'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
      "type, name) VALUES ('wh-fixture', ?, ?, 'pending', 'warehouse', "
      "'Warehouse Pusat');",
      [stamp, stamp],
    );
    return 'wh-fixture';
  }
}

// --- fake gateways --------------------------------------------------------------

/// An [ImportSourceFileStore] that keeps bytes in a map.
///
/// Real SHA-256, because the commit's hash check is one of the things under test —
/// a fake that returned a constant would make §33's *"verify before reparse"*
/// unassertable.
class InMemoryImportSourceFileStore implements ImportSourceFileStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  /// Set to make the next [storeValidatedSource] fail (§28).
  bool failOnStore = false;

  final List<String> deletedPaths = <String>[];

  @override
  Future<ImportSourceFile> storeValidatedSource({
    required String importId,
    required String originalFileName,
    required Uint8List bytes,
  }) async {
    if (failOnStore) {
      throw ImportSourceFileWriteFailureForTest(originalFileName);
    }
    final path = 'memory://aish_import_audit/$importId/$originalFileName';
    files[path] = Uint8List.fromList(bytes);
    return ImportSourceFile(
      importId: importId,
      fileName: originalFileName,
      path: path,
      sha256: sha256Hex(bytes),
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<Uint8List> readStoredSource({
    required String importId,
    required String storedPath,
  }) async {
    final bytes = files[storedPath];
    if (bytes == null) {
      throw ImportSourceFileMissingFailureForTest(importId);
    }
    return bytes;
  }

  @override
  Future<bool> verifyHash({
    required String storedPath,
    required String expectedSha256,
    required int expectedSizeBytes,
  }) async {
    final bytes = files[storedPath];
    if (bytes == null) return false;
    if (bytes.length != expectedSizeBytes) return false;
    return sha256Hex(bytes) == expectedSha256;
  }

  @override
  Future<bool> exists(String storedPath) async => files.containsKey(storedPath);

  @override
  Future<void> deleteBestEffortForFailedAudit(String storedPath) async {
    deletedPaths.add(storedPath);
    files.remove(storedPath);
  }

  /// Replaces the stored bytes without updating the audit row's hash, so the
  /// commit's tamper check has something to catch.
  void corrupt(String storedPath) {
    files[storedPath] = Uint8List.fromList([0, 1, 2, 3]);
  }

  void remove(String storedPath) => files.remove(storedPath);
}

class InMemoryMasterTemplateFileStore implements MasterTemplateFileStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<MasterTemplateArtifact> writeTemplate({
    required MasterEntityType entity,
    required String version,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = 'memory://aish_master_templates/${entity.dbValue}/$fileName';
    files[path] = Uint8List.fromList(bytes);
    return MasterTemplateArtifact(
      entity: entity,
      version: version,
      fileName: fileName,
      path: path,
      byteLength: bytes.length,
    );
  }

  @override
  Future<bool> exists(MasterTemplateArtifact artifact) async =>
      files.containsKey(artifact.path);

  @override
  Future<Uint8List> readBytes(MasterTemplateArtifact artifact) async =>
      files[artifact.path]!;
}

class FakeMasterTemplateShareGateway implements MasterTemplateShareGateway {
  FakeMasterTemplateShareGateway({
    this.outcome = MasterTemplateShareOutcome.shared,
  });

  MasterTemplateShareOutcome outcome;
  final List<MasterTemplateArtifact> shared = <MasterTemplateArtifact>[];

  @override
  Future<MasterTemplateShareOutcome> shareTemplate(
    MasterTemplateArtifact artifact,
  ) async {
    shared.add(artifact);
    return outcome;
  }
}

/// A picker that hands back whatever a test queued.
class FakeMasterImportFilePicker implements MasterImportFilePicker {
  FakeMasterImportFilePicker([this.next]);

  PickedImportFile? next;
  int callCount = 0;

  @override
  Future<PickedImportFile?> pickWorkbook() async {
    callCount++;
    return next;
  }
}

/// The same SHA-256 the production store computes, so a fixture's hash and a
/// real one are comparable.
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

// --- workbook building ------------------------------------------------------------

/// Builds a real `.xlsx` in the template's shape, for the parser to read back.
///
/// Every option a §15 test needs is a parameter, so a malformed workbook is a
/// call rather than a checked-in binary — which also means these tests describe
/// what is wrong with each file in the test name rather than in a filename.
Uint8List buildWorkbookBytes({
  required MasterEntityType entity,
  List<String>? headers,
  List<Map<String, String>> rows = const [],
  bool includeSampleRow = true,
  Map<String, String>? sampleRow,
  String? templateVersion = MasterTemplateVersion.current,
  bool includeDataSheet = true,
  bool includeInstructionsSheet = true,
  Map<String, String> formulaCells = const {},
  Map<String, int> intCells = const {},
  int? blankRowsAfter,
}) {
  final workbook = Excel.createExcel();
  final defaultSheet = workbook.getDefaultSheet();
  final effectiveHeaders = headers ?? entity.headers;

  if (includeDataSheet) {
    final sheet = workbook[MasterImportWorkbookValidator.dataSheetName];
    for (var column = 0; column < effectiveHeaders.length; column++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
          .value = TextCellValue(
        effectiveHeaders[column],
      );
    }

    var rowIndex = 1;
    if (includeSampleRow) {
      final sample =
          sampleRow ??
          <String, String>{
            for (final header in effectiveHeaders)
              header: entity.sampleSentinels[header] ?? 'contoh',
          };
      for (var column = 0; column < effectiveHeaders.length; column++) {
        sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: rowIndex,
              ),
            )
            .value = TextCellValue(
          sample[effectiveHeaders[column]] ?? '',
        );
      }
      rowIndex++;
    }

    for (final row in rows) {
      for (var column = 0; column < effectiveHeaders.length; column++) {
        final header = effectiveHeaders[column];
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex),
        );
        final formula = formulaCells['${rowIndex + 1}:$header'];
        final intValue = intCells['${rowIndex + 1}:$header'];
        if (formula != null) {
          cell.value = FormulaCellValue(formula);
        } else if (intValue != null) {
          cell.value = IntCellValue(intValue);
        } else {
          cell.value = TextCellValue(row[header] ?? '');
        }
      }
      rowIndex++;
    }

    for (var i = 0; i < (blankRowsAfter ?? 0); i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = TextCellValue(
        '',
      );
      rowIndex++;
    }
  }

  if (includeInstructionsSheet) {
    final sheet = workbook[MasterImportWorkbookValidator.instructionsSheetName];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('Petunjuk Pengisian Template');
    if (templateVersion != null) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue(
        MasterImportWorkbookValidator.versionLabel,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value = TextCellValue(
        templateVersion,
      );
    }
  }

  if (defaultSheet != null &&
      defaultSheet != MasterImportWorkbookValidator.dataSheetName &&
      defaultSheet != MasterImportWorkbookValidator.instructionsSheetName) {
    workbook.delete(defaultSheet);
  }

  return Uint8List.fromList(workbook.encode()!);
}

PickedImportFile pickedFile({
  required MasterEntityType entity,
  List<Map<String, String>> rows = const [],
  String fileName = 'master.xlsx',
  List<String>? headers,
  bool includeSampleRow = true,
  Map<String, String>? sampleRow,
  String? templateVersion = MasterTemplateVersion.current,
  bool includeDataSheet = true,
  bool includeInstructionsSheet = true,
  Map<String, String> formulaCells = const {},
  Map<String, int> intCells = const {},
  int? blankRowsAfter,
}) => PickedImportFile(
  originalFileName: fileName,
  bytes: buildWorkbookBytes(
    entity: entity,
    headers: headers,
    rows: rows,
    includeSampleRow: includeSampleRow,
    sampleRow: sampleRow,
    templateVersion: templateVersion,
    includeDataSheet: includeDataSheet,
    includeInstructionsSheet: includeInstructionsSheet,
    formulaCells: formulaCells,
    intCells: intCells,
    blankRowsAfter: blankRowsAfter,
  ),
);

// --- test-only failures -----------------------------------------------------------

class ImportSourceFileWriteFailureForTest implements Exception {
  ImportSourceFileWriteFailureForTest(this.fileName);
  final String fileName;
}

class ImportSourceFileMissingFailureForTest implements Exception {
  ImportSourceFileMissingFailureForTest(this.importId);
  final String importId;
}
