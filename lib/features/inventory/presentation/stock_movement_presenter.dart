import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/enums/app_enums.dart';

/// How a ledger row is worded and coloured on a stock card, in **one** place.
///
/// Every earlier milestone rendered its own document's movements from inside its own
/// screens, so nothing ever had to name a movement *type* in Indonesian. The stock card
/// does — it shows whatever touched a position, whichever document wrote it — and the
/// moment two widgets both spell `consumption` out, they start disagreeing. So the mapping
/// lives here and the widgets read it.
///
/// ### Exhaustive over the enum, tolerant of the string
///
/// [labelOf] switches over [StockMovementType] with no `default`, so adding a movement type
/// fails to compile until it is worded here. [documentLabelOf] cannot do that: `ref_doc_type`
/// is a plain TEXT column and a row written by a later version — or by the sync backend —
/// may carry a code this build has never heard of. It therefore falls back to a safe,
/// non-crashing label that still shows the raw code, because an auditor reading a stock card
/// is better served by *"Dokumen (XYZ)"* than by a blank.
abstract final class StockMovementPresenter {
  /// Indonesian label for one movement type.
  ///
  /// The switch is deliberately exhaustive and `default`-free: a new
  /// [StockMovementType] must be worded here rather than silently rendering as its
  /// database value.
  static String labelOf(StockMovementType type) => switch (type) {
    StockMovementType.inboundWarehouse => 'Barang Masuk',
    StockMovementType.shipment => 'Pengiriman',
    StockMovementType.goodReceipt => 'Penerimaan',
    StockMovementType.distribution => 'Distribusi',
    StockMovementType.opnameAdjustment => 'Penyesuaian Opname',
    // Milestone 8. The one label this hardening adds; every other line above is the
    // wording the earlier milestones' own screens already used.
    StockMovementType.consumption => 'Pemakaian',
    // Milestone 9. Narrowed from the placeholder *"Retur"* the previous milestone
    // carried: the ledger now has exactly one kind of `return` row and it always
    // credits the Warehouse (§22/§34), so naming the destination is the difference
    // between a label an auditor can act on and one they have to look up.
    StockMovementType.itemReturn => 'Retur ke Warehouse',
    StockMovementType.disposal => 'Pemusnahan',
    StockMovementType.reversal => 'Pembalikan',
  };

  /// A short description of what a movement did to the balance being looked at.
  ///
  /// Derived from the two location columns rather than from the type, because that is what
  /// the ledger actually asserts: a row with no destination took stock out of the system,
  /// and one with no source brought it in from outside. §2.2 states both shapes directly.
  static String directionLabelOf({
    required String? fromLocationId,
    required String? toLocationId,
  }) {
    if (fromLocationId != null && toLocationId != null) return 'Perpindahan';
    if (toLocationId != null) return 'Masuk';
    if (fromLocationId != null) return 'Keluar';
    // `stock_movements` has a CHECK requiring one of the two, so this is unreachable on a
    // healthy row — worded rather than asserted so a corrupt row renders instead of
    // crashing a screen an auditor is trying to read.
    return 'Tidak diketahui';
  }

  /// Sign shown beside the quantity, from the perspective of [locationId].
  ///
  /// `null` when the movement does not touch that location at all, which is how a caller
  /// that passed a location the row has nothing to do with renders no sign rather than a
  /// misleading one.
  static String? signFor({
    required String? locationId,
    required String? fromLocationId,
    required String? toLocationId,
  }) {
    if (locationId == null) return null;
    if (toLocationId == locationId) return '+';
    if (fromLocationId == locationId) return '−';
    return null;
  }

  /// Colour for one movement type: green for anything that raises a balance, red for
  /// anything that removes stock from the system, blue for a transfer, orange for a
  /// correction.
  static Color colorOf(StockMovementType type) => switch (type) {
    StockMovementType.inboundWarehouse ||
    StockMovementType.goodReceipt => AppColors.success,
    StockMovementType.shipment ||
    StockMovementType.distribution ||
    StockMovementType.itemReturn => AppColors.primary,
    // Both leave the system with nothing on the other side (§19/G-E7), so both read as
    // the loss they are.
    StockMovementType.consumption ||
    StockMovementType.disposal => AppColors.danger,
    StockMovementType.opnameAdjustment ||
    StockMovementType.reversal => AppColors.warning,
  };

  /// Icon for one movement type.
  static IconData iconOf(StockMovementType type) => switch (type) {
    StockMovementType.inboundWarehouse => Icons.input,
    StockMovementType.shipment => Icons.local_shipping_outlined,
    StockMovementType.goodReceipt => Icons.move_to_inbox_outlined,
    StockMovementType.distribution => Icons.outbound_outlined,
    StockMovementType.opnameAdjustment => Icons.rule,
    StockMovementType.consumption => Icons.medical_services_outlined,
    StockMovementType.itemReturn => Icons.undo,
    StockMovementType.disposal => Icons.delete_forever_outlined,
    StockMovementType.reversal => Icons.settings_backup_restore,
  };

  /// Indonesian label for a `ref_doc_type` code.
  ///
  /// A `String` switch rather than an enum one, because [RefDocType] is a set of constants
  /// on a TEXT column: a row written by a later version or by the sync backend may carry a
  /// code this build does not know. Unknown codes fall through to [unknownDocumentLabel],
  /// which shows the raw value — an auditor is better served by *"Dokumen (XYZ)"* than by
  /// nothing at all.
  static String documentLabelOf(String? refDocType) => switch (refDocType) {
    null => noDocumentLabel,
    RefDocType.stockOpname => 'dokumen Stok Opname',
    RefDocType.purchaseRequest => 'dokumen Purchase Request',
    RefDocType.deliveryOrder => 'dokumen Surat Jalan',
    RefDocType.goodReceipt => 'dokumen Penerimaan',
    RefDocType.distribution => 'dokumen Distribusi',
    RefDocType.disposal => 'dokumen Pemusnahan',
    // Milestone 8.
    RefDocType.consumption => 'dokumen Pemakaian',
    // Milestone 9.
    RefDocType.goodsReturn => 'dokumen Retur',
    RefDocType.seed => 'saldo awal',
    _ => unknownDocumentLabel(refDocType),
  };

  /// Shown when a movement carries no document reference at all — a hand-posted
  /// adjustment, or a seeded opening balance written before `ref_doc_type` was recorded.
  static const String noDocumentLabel = 'Tanpa dokumen';

  /// The safe fallback for a `ref_doc_type` this build does not recognise.
  static String unknownDocumentLabel(String refDocType) =>
      'Dokumen ($refDocType)';

  /// Shown in place of a document number when the referenced document cannot be resolved.
  ///
  /// Two different situations produce it and both are legitimate:
  ///
  /// * the caller is not *scoped* to that document — a nurse looking at a room's stock card
  ///   sees a distribution row whose Distribusi belongs to the branch head, and the number
  ///   is simply not theirs to read;
  /// * the document row is physically gone.
  ///
  /// Neither may hide the movement (§6): the stock left the shelf either way, and a stock
  /// card that dropped the row would be a stock card that does not add up.
  static const String unresolvedDocumentLabel = 'Referensi tidak tersedia';

  /// Shown in place of a master row's name when it can no longer be resolved.
  static const String unresolvedMasterLabel = 'Data historis tidak tersedia';
}
