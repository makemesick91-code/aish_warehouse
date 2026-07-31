import '../../../../core/enums/app_enums.dart';
import '../gateways/master_import_gateways.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_template_catalog.dart';
import 'master_admin_guard.dart';

/// What a completed download produced.
class MasterTemplateDownloadResult {
  const MasterTemplateDownloadResult({
    required this.artifact,
    required this.shareOutcome,
  });

  final MasterTemplateArtifact artifact;

  /// How the share sheet ended. A cancellation is **not** a failure: the file
  /// exists on the device either way, and the screen says so (§26).
  final MasterTemplateShareOutcome shareOutcome;
}

/// Builds, writes and shares one entity's template (G-M2, §26).
///
/// ### Fresh on every download, never cached
///
/// The *Petunjuk* sheet's value lists — branch codes, category names, expiry item
/// SKUs — are read from Drift at generation time. A cached template would teach
/// an operator to type a category that was archived last week, and they would
/// find out one upload later.
///
/// ### It writes nothing to the database
///
/// In particular **no `import_logs` row**. Downloading a template is not an
/// import: nothing has been validated, no file has been uploaded, and an audit row
/// describing it would be a row with no source file, no counts and no meaning
/// (§25).
///
/// ### Offline
///
/// Every step is local: the catalogue is Dart, the workbook is written by a pure
/// Dart package, the file goes to app-private storage, and the share sheet hands
/// the OS a file the app already owns. No network, and no storage permission.
class DownloadMasterTemplateUseCase with MasterAdminGuard {
  DownloadMasterTemplateUseCase({
    required this.repository,
    required this.generator,
    required this.fileStore,
    required this.shareGateway,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  @override
  final MasterAdminRepository repository;

  final MasterTemplateGenerator generator;
  final MasterTemplateFileStore fileStore;
  final MasterTemplateShareGateway shareGateway;
  final DateTime Function() _clock;

  Future<MasterTemplateDownloadResult> call({
    required String actorUserId,
    required MasterEntityType entity,
  }) async {
    await requireSuperAdmin(actorUserId);

    final definition = MasterTemplateCatalog.definitionFor(
      entity: entity,
      generatedAtUtc: _clock().toUtc(),
      reference: await _referenceDataFor(entity),
    );

    final bytes = await generator.generate(definition);
    final artifact = await fileStore.writeTemplate(
      entity: entity,
      version: definition.version,
      fileName: definition.fileName,
      bytes: bytes,
    );
    final outcome = await shareGateway.shareTemplate(artifact);

    return MasterTemplateDownloadResult(
      artifact: artifact,
      shareOutcome: outcome,
    );
  }

  /// Only the lists this entity's *Petunjuk* sheet actually shows.
  ///
  /// A category template does not enumerate every SKU in the clinic group, and a
  /// branch template reads nothing at all — loading the union would make the
  /// cheapest template as slow as the most expensive one.
  Future<MasterTemplateReferenceData> _referenceDataFor(
    MasterEntityType entity,
  ) async {
    switch (entity) {
      case MasterEntityType.branches:
      case MasterEntityType.itemCategories:
        return const MasterTemplateReferenceData();
      case MasterEntityType.rooms:
        return MasterTemplateReferenceData(
          branchCodes: await _activeBranchCodes(),
        );
      case MasterEntityType.users:
        return MasterTemplateReferenceData(
          branchCodes: await _activeBranchCodes(),
        );
      case MasterEntityType.items:
        return MasterTemplateReferenceData(
          categoryNames: await _liveCategoryNames(),
        );
      case MasterEntityType.itemBatches:
        return MasterTemplateReferenceData(
          expiryItemSkus: await _expiryItemSkus(),
        );
    }
  }

  Future<List<String>> _activeBranchCodes() async {
    final views = await repository.listBranches(const MasterListFilter());
    return views.map((view) => view.branch.code).toList()..sort();
  }

  Future<List<String>> _liveCategoryNames() async {
    final views = await repository.listCategories(const MasterListFilter());
    return views.map((view) => view.category.name).toList()..sort();
  }

  /// Only `has_expiry = true` items. Listing every SKU would invite exactly the
  /// row the batch validator then has to refuse (§14.6).
  Future<List<String>> _expiryItemSkus() async {
    final views = await repository.listItems(
      const MasterListFilter(hasExpiry: true),
    );
    return views.map((view) => view.item.sku).toList()..sort();
  }
}

/// Reads the import audit (G-M6, §36). Super Admin only.
class WatchImportHistoryUseCase with MasterAdminGuard {
  WatchImportHistoryUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  /// A stream of the audit, newest first.
  ///
  /// The role check runs **before** the stream is opened, and a refusal yields an
  /// empty stream rather than throwing into it: a provider that emitted an error
  /// object carrying a row count would leak the one thing §37 says a refusal must
  /// not (§53).
  Stream<List<ImportLog>> call({
    required String actorUserId,
    ImportHistoryFilter filter = const ImportHistoryFilter(),
  }) async* {
    final actor = await repository.adminUserById(actorUserId);
    if (actor == null || !actor.isActive || actor.role != UserRole.superAdmin) {
      yield const <ImportLog>[];
      return;
    }
    yield* repository.watchImportHistory(filter);
  }
}

/// One audit row in full (§36). Super Admin only.
class GetImportLogDetailUseCase with MasterAdminGuard {
  GetImportLogDetailUseCase({required this.repository});

  @override
  final MasterAdminRepository repository;

  /// Returns `null` for an unauthorized actor **and** for an id that does not
  /// exist.
  ///
  /// The same answer for both, deliberately. Telling them apart would let anyone
  /// who reaches the route enumerate which import ids are real, and the detail
  /// screen has no use for the distinction: it renders *"tidak ditemukan"* either
  /// way (§37).
  Future<ImportLogDetail?> call({
    required String actorUserId,
    required String importId,
  }) async {
    final actor = await repository.adminUserById(actorUserId);
    if (actor == null || !actor.isActive || actor.role != UserRole.superAdmin) {
      return null;
    }
    return repository.importLogDetail(importId);
  }
}
