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

  // There is deliberately no `/akses-ditolak` route. A refused document route
  // renders `AccessDeniedPage` *in place*, keeping the URL the user typed:
  // redirecting to a dedicated path would tell them, by the address bar alone,
  // that the id they guessed is one the app recognises — which is the thing
  // §6.5 exists to withhold.
}
