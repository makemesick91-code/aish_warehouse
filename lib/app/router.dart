import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session/current_user_session.dart';
import '../features/delivery/domain/services/delivery_order_access_policy.dart';
import '../features/distribution/domain/services/distribution_access_policy.dart';
import '../features/good_receipt/domain/services/good_receipt_access_policy.dart';
import '../features/opname/domain/services/opname_access_policy.dart';
import '../features/purchase_request/domain/services/purchase_request_access_policy.dart';
import 'guards/delivery_order_route_guard.dart';
import 'guards/distribution_route_guard.dart';
import 'guards/good_receipt_route_guard.dart';
import 'guards/opname_route_guard.dart';
import 'guards/purchase_request_route_guard.dart';
import 'routes.dart';
import '../features/dashboard/presentation/pages/development_home_page.dart';
import '../features/delivery/presentation/pages/branch_delivery_list_page.dart';
import '../features/delivery/presentation/pages/delivery_order_create_page.dart';
import '../features/delivery/presentation/pages/delivery_order_detail_page.dart';
import '../features/delivery/presentation/pages/delivery_order_form_page.dart';
import '../features/delivery/presentation/pages/delivery_waybill_page.dart';
import '../features/delivery/presentation/pages/warehouse_delivery_order_list_page.dart';
import '../features/distribution/presentation/pages/distribution_detail_page.dart';
import '../features/distribution/presentation/pages/distribution_form_page.dart';
import '../features/distribution/presentation/pages/distribution_list_page.dart';
import '../features/good_receipt/presentation/pages/branch_good_receipt_list_page.dart';
import '../features/good_receipt/presentation/pages/good_receipt_detail_page.dart';
import '../features/good_receipt/presentation/pages/good_receipt_start_page.dart';
import '../features/good_receipt/presentation/pages/warehouse_good_receipt_discrepancy_page.dart';
import '../features/good_receipt/presentation/pages/warehouse_good_receipt_list_page.dart';
import '../features/opname/presentation/pages/opname_form_page.dart';
import '../features/opname/presentation/pages/opname_list_page.dart';
import '../features/opname/presentation/pages/opname_review_detail_page.dart';
import '../features/opname/presentation/pages/opname_review_list_page.dart';
import '../features/purchase_request/presentation/pages/purchase_request_detail_page.dart';
import '../features/purchase_request/presentation/pages/purchase_request_form_page.dart';
import '../features/purchase_request/presentation/pages/purchase_request_list_page.dart';
import '../features/purchase_request/presentation/pages/purchase_request_wizard_page.dart';
import '../features/purchase_request/presentation/pages/warehouse_purchase_request_detail_page.dart';
import '../features/purchase_request/presentation/pages/warehouse_purchase_request_list_page.dart';

/// Root router.
///
/// Access is decided in two passes, and both matter.
///
/// The **redirect** below is synchronous and answers only what a role can be
/// asked without touching the database: which sections exist for this user. It
/// runs on every navigation, so it has to stay cheap.
///
/// A section check cannot decide a *document*, though. `/opname/{id}` names a
/// row, and whether that row belongs to the acting user's branch is a question
/// only the database can answer. Typing another branch's id into the address
/// bar passes every role check there is, which is why the two detail routes are
/// wrapped in [OpnameRouteGuard]: it resolves the actor and a four-column,
/// branch-scoped lookup before the page is built at all. Until it says yes,
/// the page does not exist and no document stream has been subscribed —
/// nothing to hide, because nothing was fetched.
///
/// Neither pass is the enforcement point for *writes*. Every use case still
/// re-reads the actor from the database and re-applies G-R1/G-R2/G-R4, so a
/// route reached by any other means still cannot change anything.
///
/// When real authentication lands, only [currentSessionProvider] changes; both
/// passes keep working as written.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    // Re-evaluate the guards whenever the acting user changes.
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final session = ref.read(currentSessionValueProvider);
      // Still loading, or master data has not been seeded: let the page render
      // its own empty state rather than bouncing the user around.
      if (session == null) return null;

      final location = state.matchedLocation;

      // The role rule is [OpnameAccessPolicy]'s, not the router's. Restating
      // it here as `session.canReviewOpname` would be a second copy that has
      // to agree with the guard's by hand — and the two are reached by the
      // same user on the same navigation. `session.user` is the row the
      // session was built from, so this is the same input the guard re-reads.
      OpnameAccess sectionFor(OpnameRouteKind kind) =>
          OpnameAccessPolicy.forSection(user: session.user, kind: kind);

      if (location.startsWith(
        '${AppRoutes.opname}/${AppRoutes.opnameReview}',
      )) {
        return sectionFor(OpnameRouteKind.reviewList).isGranted
            ? null
            : AppRoutes.opname;
      }
      if (location.startsWith(AppRoutes.opname)) {
        return sectionFor(OpnameRouteKind.list).isGranted
            ? null
            : AppRoutes.home;
      }

      // Purchase Request. The rule is [PurchaseRequestAccessPolicy]'s, exactly as
      // above: restating "warehouse only" or "kepala cabang only" here would be a
      // second copy that has to agree with the guard's by hand.
      //
      // The warehouse branch is tested first because its path is a different
      // prefix (`/warehouse/…`), not a nested one — checking `/purchase-requests`
      // first would still not match it, but relying on that is one route rename
      // away from being wrong.
      PurchaseRequestAccess purchaseRequestSectionFor(
        PurchaseRequestRouteKind kind,
      ) => PurchaseRequestAccessPolicy.forSection(
        user: session.user,
        kind: kind,
      );

      if (location.startsWith(AppRoutes.warehousePurchaseRequests)) {
        return purchaseRequestSectionFor(
              PurchaseRequestRouteKind.warehouseQueue,
            ).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.purchaseRequests)) {
        return purchaseRequestSectionFor(
              PurchaseRequestRouteKind.branchList,
            ).isGranted
            ? null
            : AppRoutes.home;
      }

      // Delivery Order. Same shape again: the rule is
      // [DeliveryOrderAccessPolicy]'s, and the redirect only asks the cheap
      // section half of it. Whether a *document* may be opened is the guard's
      // question, because only the database knows which branch a shipment is
      // addressed to and whether it has actually been sent.
      DeliveryAccess deliverySectionFor(DeliveryRouteKind kind) =>
          DeliveryOrderAccessPolicy.forSection(user: session.user, kind: kind);

      if (location.startsWith(AppRoutes.warehouseDeliveryOrders)) {
        return deliverySectionFor(DeliveryRouteKind.warehouseList).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.deliveries)) {
        return deliverySectionFor(DeliveryRouteKind.branchList).isGranted
            ? null
            : AppRoutes.home;
      }

      // Good Receipt. Same shape again: the rule is
      // [GoodReceiptAccessPolicy]'s, and the redirect only asks the cheap
      // section half of it. Whether a *document* may be opened is the guard's
      // question, because only the database knows which branch a receipt belongs
      // to and whether it has been posted.
      GoodReceiptAccess receiptSectionFor(GoodReceiptRouteKind kind) =>
          GoodReceiptAccessPolicy.forSection(user: session.user, kind: kind);

      // The discrepancy queue is checked before the receipt list because its path
      // is a sibling prefix rather than a nested one, and relying on the two not
      // colliding is one route rename away from being wrong.
      if (location.startsWith(AppRoutes.warehouseGoodReceiptDiscrepancies)) {
        return receiptSectionFor(
              GoodReceiptRouteKind.warehouseDiscrepancies,
            ).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.warehouseGoodReceipts)) {
        return receiptSectionFor(GoodReceiptRouteKind.warehouseList).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.receipts)) {
        return receiptSectionFor(GoodReceiptRouteKind.branchList).isGranted
            ? null
            : AppRoutes.home;
      }

      // Distribusi. Same shape again, and the simplest of the five: every screen is
      // branch-scoped and there is no warehouse counterpart at all (spec §3.1), so the
      // cheap section half of the rule is a single role-and-branch question. Whether a
      // *document* may be opened — and, on the editor, whether it is still a draft — is
      // the guard's question, because only the database knows.
      if (location.startsWith(AppRoutes.distributions)) {
        return DistributionAccessPolicy.forSection(
              user: session.user,
              kind: DistributionRouteKind.branchList,
            ).isGranted
            ? null
            : AppRoutes.home;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const DevelopmentHomePage(),
      ),
      GoRoute(
        path: AppRoutes.opname,
        name: AppRoutes.opnameName,
        builder: (context, state) => const OpnameListPage(),
        routes: [
          // Listed first: a literal segment must win over the `:id` pattern.
          GoRoute(
            path: AppRoutes.opnameReview,
            name: AppRoutes.opnameReviewName,
            builder: (context, state) => const OpnameReviewListPage(),
            routes: [
              GoRoute(
                path: AppRoutes.opnameReviewDetail,
                name: AppRoutes.opnameReviewDetailName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return OpnameRouteGuard(
                    kind: OpnameRouteKind.reviewDocument,
                    opnameId: id,
                    builder: (_) => OpnameReviewDetailPage(opnameId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.opnameDetail,
            name: AppRoutes.opnameDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return OpnameRouteGuard(
                kind: OpnameRouteKind.document,
                opnameId: id,
                builder: (_) => OpnameFormPage(opnameId: id),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.purchaseRequests,
        name: AppRoutes.purchaseRequestsName,
        builder: (context, state) => const PurchaseRequestSectionGuard(
          kind: PurchaseRequestRouteKind.branchList,
          builder: _purchaseRequestList,
        ),
        routes: [
          // Listed first: a literal segment must win over the `:id` pattern.
          GoRoute(
            path: AppRoutes.purchaseRequestNew,
            name: AppRoutes.purchaseRequestNewName,
            builder: (context, state) => const PurchaseRequestSectionGuard(
              kind: PurchaseRequestRouteKind.branchCreate,
              builder: _purchaseRequestWizard,
            ),
          ),
          GoRoute(
            path: AppRoutes.purchaseRequestDetail,
            name: AppRoutes.purchaseRequestDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PurchaseRequestRouteGuard(
                kind: PurchaseRequestRouteKind.branchDocument,
                prId: id,
                builder: (_) => PurchaseRequestDetailPage(prId: id),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.purchaseRequestEdit,
                name: AppRoutes.purchaseRequestEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  // A distinct kind, not the same one as the detail route: the
                  // editor additionally requires the document to still be a draft
                  // (G-P5), and the policy is where that is decided.
                  return PurchaseRequestRouteGuard(
                    kind: PurchaseRequestRouteKind.branchDraft,
                    prId: id,
                    builder: (_) => PurchaseRequestFormPage(prId: id),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.warehousePurchaseRequests,
        name: AppRoutes.warehousePurchaseRequestsName,
        builder: (context, state) => const PurchaseRequestSectionGuard(
          kind: PurchaseRequestRouteKind.warehouseQueue,
          builder: _warehousePurchaseRequestList,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.warehousePurchaseRequestDetail,
            name: AppRoutes.warehousePurchaseRequestDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return PurchaseRequestRouteGuard(
                kind: PurchaseRequestRouteKind.warehouseDocument,
                prId: id,
                builder: (_) => WarehousePurchaseRequestDetailPage(prId: id),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.warehouseDeliveryOrders,
        name: AppRoutes.warehouseDeliveryOrdersName,
        builder: (context, state) => const DeliverySectionGuard(
          kind: DeliveryRouteKind.warehouseList,
          builder: _warehouseDeliveryList,
        ),
        routes: [
          // Listed first: the literal `new` segment must win over the `:id`
          // pattern, or `/warehouse/delivery-orders/new/{pr}` would be read as a
          // document id followed by a stray segment.
          GoRoute(
            path: AppRoutes.warehouseDeliveryOrderNew,
            name: AppRoutes.warehouseDeliveryOrderNewName,
            builder: (context, state) {
              final prId = state.pathParameters['purchaseRequestId']!;
              return DeliverySectionGuard(
                kind: DeliveryRouteKind.warehouseCreate,
                builder: (_) =>
                    DeliveryOrderCreatePage(purchaseRequestId: prId),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.warehouseDeliveryOrderDetail,
            name: AppRoutes.warehouseDeliveryOrderDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DeliveryOrderRouteGuard(
                kind: DeliveryRouteKind.warehouseDocument,
                doId: id,
                builder: (_) =>
                    DeliveryOrderDetailPage(doId: id, branchScoped: false),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.warehouseDeliveryOrderEdit,
                name: AppRoutes.warehouseDeliveryOrderEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  // A distinct kind, not the same one as the detail route: the
                  // editor additionally requires the document to still be
                  // `preparing` (G-S2), and the policy is where that is decided.
                  return DeliveryOrderRouteGuard(
                    kind: DeliveryRouteKind.warehouseDraft,
                    doId: id,
                    builder: (_) => DeliveryOrderFormPage(doId: id),
                  );
                },
              ),
              GoRoute(
                path: AppRoutes.warehouseDeliveryOrderWaybill,
                name: AppRoutes.warehouseDeliveryOrderWaybillName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return DeliveryOrderRouteGuard(
                    kind: DeliveryRouteKind.warehouseWaybill,
                    doId: id,
                    builder: (_) =>
                        DeliveryWaybillPage(doId: id, branchScoped: false),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.deliveries,
        name: AppRoutes.deliveriesName,
        builder: (context, state) => const DeliverySectionGuard(
          kind: DeliveryRouteKind.branchList,
          builder: _branchDeliveryList,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.deliveryDetail,
            name: AppRoutes.deliveryDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DeliveryOrderRouteGuard(
                kind: DeliveryRouteKind.branchDocument,
                doId: id,
                builder: (_) =>
                    DeliveryOrderDetailPage(doId: id, branchScoped: true),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.deliveryWaybill,
                name: AppRoutes.deliveryWaybillName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return DeliveryOrderRouteGuard(
                    kind: DeliveryRouteKind.branchWaybill,
                    doId: id,
                    builder: (_) =>
                        DeliveryWaybillPage(doId: id, branchScoped: true),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.receipts,
        name: AppRoutes.receiptsName,
        builder: (context, state) => const GoodReceiptSectionGuard(
          kind: GoodReceiptRouteKind.branchList,
          builder: _branchGoodReceiptList,
        ),
        routes: [
          // Listed first: the literal `new` segment must win over the `:id`
          // pattern, or `/receipts/new/{do}` would be read as a receipt id
          // followed by a stray segment.
          GoRoute(
            path: AppRoutes.receiptNew,
            name: AppRoutes.receiptNewName,
            builder: (context, state) {
              final doId = state.pathParameters['deliveryOrderId']!;
              // The create route names a **shipment**, so its guard resolves the
              // Delivery Order's access scope — branch predicate and G-G1's
              // `shipped` predicate both inside the query.
              return GoodReceiptCreateRouteGuard(
                doId: doId,
                builder: (_) => GoodReceiptStartPage(deliveryOrderId: doId),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.receiptDetail,
            name: AppRoutes.receiptDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return GoodReceiptRouteGuard(
                kind: GoodReceiptRouteKind.branchDocument,
                grId: id,
                builder: (_) => GoodReceiptDetailPage(grId: id),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.warehouseGoodReceipts,
        name: AppRoutes.warehouseGoodReceiptsName,
        builder: (context, state) => const GoodReceiptSectionGuard(
          kind: GoodReceiptRouteKind.warehouseList,
          builder: _warehouseGoodReceiptList,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.warehouseGoodReceiptDetail,
            name: AppRoutes.warehouseGoodReceiptDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return GoodReceiptRouteGuard(
                kind: GoodReceiptRouteKind.warehouseDocument,
                grId: id,
                builder: (_) =>
                    GoodReceiptDetailPage(grId: id, branchScoped: false),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.warehouseGoodReceiptDiscrepancies,
        name: AppRoutes.warehouseGoodReceiptDiscrepanciesName,
        builder: (context, state) => const GoodReceiptSectionGuard(
          kind: GoodReceiptRouteKind.warehouseDiscrepancies,
          builder: _warehouseGoodReceiptDiscrepancies,
        ),
      ),
      GoRoute(
        path: AppRoutes.distributions,
        name: AppRoutes.distributionsName,
        builder: (context, state) => const DistributionSectionGuard(
          kind: DistributionRouteKind.branchList,
          builder: _distributionList,
        ),
        routes: [
          // Listed first: the literal `new` segment must win over the `:id` pattern, or
          // `/distributions/new` would be read as a document id.
          GoRoute(
            path: AppRoutes.distributionNew,
            name: AppRoutes.distributionNewName,
            builder: (context, state) => const DistributionSectionGuard(
              kind: DistributionRouteKind.branchCreate,
              builder: _distributionList,
            ),
          ),
          GoRoute(
            path: AppRoutes.distributionDetail,
            name: AppRoutes.distributionDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DistributionRouteGuard(
                kind: DistributionRouteKind.branchDocument,
                distributionId: id,
                builder: (_) => DistributionDetailPage(distributionId: id),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.distributionEdit,
                name: AppRoutes.distributionEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  // A distinct kind, not the same one as the detail route: the editor
                  // additionally requires the document to still be a draft (G-S2), and
                  // the policy is where that is decided.
                  return DistributionRouteGuard(
                    kind: DistributionRouteKind.branchDraft,
                    distributionId: id,
                    builder: (_) => DistributionFormPage(distributionId: id),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

// Top-level builders so the section guards above can stay `const`.
Widget _purchaseRequestList(BuildContext context) =>
    const PurchaseRequestListPage();

Widget _purchaseRequestWizard(BuildContext context) =>
    const PurchaseRequestWizardPage();

Widget _warehousePurchaseRequestList(BuildContext context) =>
    const WarehousePurchaseRequestListPage();

Widget _warehouseDeliveryList(BuildContext context) =>
    const WarehouseDeliveryOrderListPage();

Widget _branchDeliveryList(BuildContext context) =>
    const BranchDeliveryListPage();

Widget _branchGoodReceiptList(BuildContext context) =>
    const BranchGoodReceiptListPage();

Widget _warehouseGoodReceiptList(BuildContext context) =>
    const WarehouseGoodReceiptListPage();

Widget _warehouseGoodReceiptDiscrepancies(BuildContext context) =>
    const WarehouseGoodReceiptDiscrepancyPage();

/// `/distributions` and `/distributions/new` both land here.
///
/// The list *is* the create surface: its `Buat Distribusi` button creates the draft and
/// pushes straight into the editor, because a document has to exist before rooms and
/// items can be validated against it. The `new` route exists so a deep link has
/// somewhere to go, and so the section guard has a `branchCreate` kind to refuse.
Widget _distributionList(BuildContext context) => const DistributionListPage();

/// Bridges the session provider to GoRouter's `refreshListenable`, so switching
/// role re-runs the redirect immediately instead of on the next navigation.
class _SessionRefreshListenable extends ChangeNotifier {
  _SessionRefreshListenable(Ref ref) {
    _subscription = ref.listen<CurrentUserSession?>(
      currentSessionValueProvider,
      (_, _) => notifyListeners(),
    );
    ref.onDispose(dispose);
  }

  late final ProviderSubscription<CurrentUserSession?> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
