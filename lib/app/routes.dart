/// Route paths and names, in one place so feature modules never hard-code
/// strings.
///
/// Deliberately separate from `router.dart`: the router imports every page, and
/// pages need these constants to navigate. Keeping the constants in their own
/// library means a page can navigate without importing the router that builds
/// it, so there is no import cycle between the two.
abstract final class AppRoutes {
  static const String home = '/';
  static const String homeName = 'home';

  static const String opname = '/opname';
  static const String opnameName = 'opname';

  /// Nested under [opname], so the full path is `/opname/review`.
  static const String opnameReview = 'review';
  static const String opnameReviewName = 'opnameReview';

  static const String opnameReviewDetail = ':id';
  static const String opnameReviewDetailName = 'opnameReviewDetail';

  /// Declared after `review` so `/opname/review` is never matched as an id.
  static const String opnameDetail = ':id';
  static const String opnameDetailName = 'opnameDetail';

  // --- Purchase Request (Milestone 3) ---------------------------------------

  /// The Kepala Cabang's own requests.
  static const String purchaseRequests = '/purchase-requests';
  static const String purchaseRequestsName = 'purchaseRequests';

  /// Nested under [purchaseRequests], so the full path is
  /// `/purchase-requests/new`. Declared **before** the `:id` pattern, or a
  /// literal segment would be matched as a document id.
  static const String purchaseRequestNew = 'new';
  static const String purchaseRequestNewName = 'purchaseRequestNew';

  static const String purchaseRequestDetail = ':id';
  static const String purchaseRequestDetailName = 'purchaseRequestDetail';

  /// `/purchase-requests/{id}/edit` — the draft editor, nested under the detail
  /// route so both share the same `:id`.
  static const String purchaseRequestEdit = 'edit';
  static const String purchaseRequestEditName = 'purchaseRequestEdit';

  /// The central warehouse inbox, across every branch.
  static const String warehousePurchaseRequests =
      '/warehouse/purchase-requests';
  static const String warehousePurchaseRequestsName =
      'warehousePurchaseRequests';

  static const String warehousePurchaseRequestDetail = ':id';
  static const String warehousePurchaseRequestDetailName =
      'warehousePurchaseRequestDetail';

  // --- Delivery Order (Milestone 4) -----------------------------------------

  /// The warehouse's shipments, across every branch.
  static const String warehouseDeliveryOrders = '/warehouse/delivery-orders';
  static const String warehouseDeliveryOrdersName = 'warehouseDeliveryOrders';

  /// `/warehouse/delivery-orders/new/{purchaseRequestId}` — raise a shipment
  /// from one request. Declared **before** the `:id` pattern, or the literal
  /// `new` segment would be matched as a document id.
  static const String warehouseDeliveryOrderNew = 'new/:purchaseRequestId';
  static const String warehouseDeliveryOrderNewName =
      'warehouseDeliveryOrderNew';

  static const String warehouseDeliveryOrderDetail = ':id';
  static const String warehouseDeliveryOrderDetailName =
      'warehouseDeliveryOrderDetail';

  /// `/warehouse/delivery-orders/{id}/edit` — the allocation editor, nested under
  /// the detail route so both share the same `:id`.
  static const String warehouseDeliveryOrderEdit = 'edit';
  static const String warehouseDeliveryOrderEditName =
      'warehouseDeliveryOrderEdit';

  /// `/warehouse/delivery-orders/{id}/waybill` — the Surat Jalan, draft included.
  static const String warehouseDeliveryOrderWaybill = 'waybill';
  static const String warehouseDeliveryOrderWaybillName =
      'warehouseDeliveryOrderWaybill';

  /// The Kepala Cabang's incoming shipments — read-only in this milestone.
  static const String deliveries = '/deliveries';
  static const String deliveriesName = 'deliveries';

  static const String deliveryDetail = ':id';
  static const String deliveryDetailName = 'deliveryDetail';

  static const String deliveryWaybill = 'waybill';
  static const String deliveryWaybillName = 'deliveryWaybill';

  // --- Good Receipt (Milestone 5) -------------------------------------------

  /// The Kepala Cabang's Penerimaan section.
  static const String receipts = '/receipts';
  static const String receiptsName = 'receipts';

  /// `/receipts/new/{deliveryOrderId}` — start checking one shipment in. Names a
  /// **Delivery Order**, not a receipt: the receipt does not exist yet. Declared
  /// **before** the `:id` pattern, or the literal `new` segment would be matched
  /// as a document id.
  static const String receiptNew = 'new/:deliveryOrderId';
  static const String receiptNewName = 'receiptNew';

  static const String receiptDetail = ':id';
  static const String receiptDetailName = 'receiptDetail';

  /// The warehouse's read-only view of posted receipts, across every branch.
  static const String warehouseGoodReceipts = '/warehouse/good-receipts';
  static const String warehouseGoodReceiptsName = 'warehouseGoodReceipts';

  static const String warehouseGoodReceiptDetail = ':id';
  static const String warehouseGoodReceiptDetailName =
      'warehouseGoodReceiptDetail';

  /// The selisih/retur queue (G-G3/G-G5). A separate top-level path rather than a
  /// child of [warehouseGoodReceipts], because it is a line-level report across
  /// documents rather than a view of one.
  static const String warehouseGoodReceiptDiscrepancies =
      '/warehouse/good-receipt-discrepancies';
  static const String warehouseGoodReceiptDiscrepanciesName =
      'warehouseGoodReceiptDiscrepancies';

  // --- Distribusi (Milestone 6) ---------------------------------------------

  /// The Kepala Cabang's Distribusi section. There is deliberately **no**
  /// `/warehouse/distributions` counterpart: spec §3.1 gives *"Distribusi ke
  /// ruangan"* to `kepala_cabang` alone, and §2.5 makes the movement
  /// branch-internal. A cross-branch view of distributions is a reporting question
  /// (`rekap_distribusi`, §4.2), and the reporting module is a later milestone.
  static const String distributions = '/distributions';
  static const String distributionsName = 'distributions';

  /// Nested under [distributions], so the full path is `/distributions/new`.
  /// Declared **before** the `:id` pattern, or the literal segment would be matched
  /// as a document id.
  static const String distributionNew = 'new';
  static const String distributionNewName = 'distributionNew';

  static const String distributionDetail = ':id';
  static const String distributionDetailName = 'distributionDetail';

  /// `/distributions/{id}/edit` — the multi-room form, nested under the detail route
  /// so both share the same `:id`. A distinct route rather than a mode of the detail
  /// page, because the editor additionally requires the document to still be a draft
  /// (G-S2) and that is a *route* precondition the guard can enforce before anything
  /// is fetched.
  static const String distributionEdit = 'edit';
  static const String distributionEditName = 'distributionEdit';

  // --- Pemusnahan (Milestone 7) ---------------------------------------------

  /// The Petugas Warehouse's Pemusnahan section, reached from *Stok Warehouse*
  /// (spec §4.2: *"daftar kedaluwarsa & pemusnahan (`disposal`)"*).
  ///
  /// Unlike Distribusi, this document has **two** sides — see [disposals] — and
  /// they are disjoint: neither list ever contains one of the other's documents.
  static const String warehouseDisposals = '/warehouse/disposals';
  static const String warehouseDisposalsName = 'warehouseDisposals';

  /// Nested under [warehouseDisposals], so the full path is
  /// `/warehouse/disposals/new`. Declared **before** the `:id` pattern, or the
  /// literal segment would be matched as a document id.
  static const String warehouseDisposalNew = 'new';
  static const String warehouseDisposalNewName = 'warehouseDisposalNew';

  static const String warehouseDisposalDetail = ':id';
  static const String warehouseDisposalDetailName = 'warehouseDisposalDetail';

  /// `/warehouse/disposals/{id}/edit` — the form, nested under the detail route so
  /// both share the same `:id`. A distinct route rather than a mode of the detail
  /// page, because the editor additionally requires the document to still be a
  /// draft (G-S2) and that is a *route* precondition the guard can enforce before
  /// anything is fetched.
  static const String warehouseDisposalEdit = 'edit';
  static const String warehouseDisposalEditName = 'warehouseDisposalEdit';

  /// The Kepala Cabang's Pemusnahan section — their own *Gudang Cabang* and rooms.
  static const String disposals = '/disposals';
  static const String disposalsName = 'disposals';

  static const String disposalNew = 'new';
  static const String disposalNewName = 'disposalNew';

  static const String disposalDetail = ':id';
  static const String disposalDetailName = 'disposalDetail';

  static const String disposalEdit = 'edit';
  static const String disposalEditName = 'disposalEdit';

  // There is deliberately no `/akses-ditolak` route. A refused document route
  // renders `AccessDeniedPage` *in place*, keeping the URL the user typed:
  // redirecting to a dedicated path would tell them, by the address bar alone,
  // that the id they guessed is one the app recognises — which is the thing
  // §6.5 exists to withhold.
}
