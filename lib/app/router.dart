import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/enums/app_enums.dart';
import '../core/supabase/supabase_client_provider.dart';
import '../core/session/current_user_session.dart';
import '../features/auth/domain/models/auth_models.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/delivery/domain/services/delivery_order_access_policy.dart';
import '../features/consumption/domain/services/consumption_access_policy.dart';
import '../features/goods_return/domain/services/goods_return_access_policy.dart';
import '../features/disposal/domain/services/disposal_access_policy.dart';
import '../features/distribution/domain/services/distribution_access_policy.dart';
import '../features/good_receipt/domain/services/good_receipt_access_policy.dart';
import '../features/opname/domain/services/opname_access_policy.dart';
import '../features/purchase_request/domain/services/purchase_request_access_policy.dart';
import '../features/master/domain/services/master_admin_access_policy.dart';
import '../features/reports/domain/services/report_access_policy.dart';
import 'guards/consumption_route_guard.dart';
import 'guards/goods_return_route_guard.dart';
import 'guards/delivery_order_route_guard.dart';
import 'guards/disposal_route_guard.dart';
import 'guards/distribution_route_guard.dart';
import 'guards/good_receipt_route_guard.dart';
import 'guards/master_admin_route_guard.dart';
import 'guards/opname_route_guard.dart';
import 'guards/purchase_request_route_guard.dart';
import 'guards/reporting_route_guard.dart';
import 'routes.dart';
import '../features/dashboard/presentation/pages/development_home_page.dart';
import '../features/consumption/presentation/pages/branch_consumption_list_page.dart';
import '../features/consumption/presentation/pages/consumption_detail_page.dart';
import '../features/consumption/presentation/pages/consumption_form_page.dart';
import '../features/consumption/presentation/pages/consumption_list_page.dart';
import '../features/goods_return/presentation/pages/branch_goods_return_list_page.dart';
import '../features/goods_return/presentation/pages/goods_return_detail_page.dart';
import '../features/goods_return/presentation/pages/warehouse_goods_return_pages.dart';
import '../features/delivery/presentation/pages/branch_delivery_list_page.dart';
import '../features/delivery/presentation/pages/delivery_order_create_page.dart';
import '../features/delivery/presentation/pages/delivery_order_detail_page.dart';
import '../features/delivery/presentation/pages/delivery_order_form_page.dart';
import '../features/delivery/presentation/pages/delivery_waybill_page.dart';
import '../features/delivery/presentation/pages/warehouse_delivery_order_list_page.dart';
import '../features/disposal/presentation/pages/disposal_detail_page.dart';
import '../features/disposal/presentation/pages/disposal_form_page.dart';
import '../features/disposal/presentation/pages/disposal_list_page.dart';
import '../features/distribution/presentation/pages/distribution_detail_page.dart';
import '../features/distribution/presentation/pages/distribution_form_page.dart';
import '../features/distribution/presentation/pages/distribution_list_page.dart';
import '../features/good_receipt/presentation/pages/branch_good_receipt_list_page.dart';
import '../features/good_receipt/presentation/pages/good_receipt_detail_page.dart';
import '../features/good_receipt/presentation/pages/good_receipt_start_page.dart';
import '../features/good_receipt/presentation/pages/warehouse_good_receipt_discrepancy_page.dart';
import '../features/good_receipt/presentation/pages/warehouse_good_receipt_list_page.dart';
import '../features/master/presentation/pages/import_log_detail_page.dart';
import '../features/master/presentation/pages/master_dashboard_page.dart';
import '../features/master/presentation/pages/master_entity_form_page.dart';
import '../features/master/presentation/pages/master_entity_list_pages.dart';
import '../features/master/presentation/pages/master_import_page.dart';
import '../features/master/domain/models/master_admin_models.dart';
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
import '../features/reports/presentation/pages/export_history_page.dart';
import '../features/reports/presentation/pages/report_page.dart';
import '../features/sync/presentation/pages/sync_center_page.dart';

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
  final productionAuthEnabled = ref.read(supabaseConfigProvider).enabled;
  return GoRouter(
    initialLocation: productionAuthEnabled
        ? AppRoutes.authLoading
        : AppRoutes.home,
    debugLogDiagnostics: false,
    // Re-evaluate the guards whenever the acting user changes.
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (productionAuthEnabled) {
        final auth = ref.read(authStateProvider);
        if (auth.isLoading) {
          return location == AppRoutes.authLoading
              ? null
              : AppRoutes.authLoading;
        }
        if (auth.hasError) {
          return location == AppRoutes.login ? null : AppRoutes.login;
        }
        final authState = auth.value;
        if (authState is! AuthAuthenticated) {
          return location == AppRoutes.login ? null : AppRoutes.login;
        }
        if (location == AppRoutes.login || location == AppRoutes.authLoading) {
          return AppRoutes.home;
        }
      }

      final session = ref.read(currentSessionValueProvider);
      // Still loading, or master data has not been seeded: let the page render
      // its own empty state rather than bouncing the user around.
      if (session == null) return null;

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

      // Pemusnahan. The first document with two symmetric sides, so the redirect
      // asks the cheap section half of the rule twice — once per scope — and the
      // warehouse branch is tested first because its path is a different prefix
      // (`/warehouse/…`) rather than a nested one. Whether a *document* may be
      // opened, and on the editor whether it is still a draft, is the guard's
      // question, because only the database knows which shelf a document drew from.
      DisposalAccess disposalSectionFor(DisposalRouteKind kind) =>
          DisposalAccessPolicy.forSection(user: session.user, kind: kind);

      if (location.startsWith(AppRoutes.warehouseDisposals)) {
        return disposalSectionFor(DisposalRouteKind.warehouseList).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.disposals)) {
        return disposalSectionFor(DisposalRouteKind.branchList).isGranted
            ? null
            : AppRoutes.home;
      }

      // Pemakaian. Two sections again, and this time they are *different roles* on
      // *different paths* rather than two scopes of one: `/consumptions` is the Perawat's
      // own work and `/branch-consumptions` is the Kepala Cabang's read-only history. The
      // branch prefix is tested first because it is a separate top-level path, not a
      // nested one — a shared prefix is exactly the kind of thing an IDOR hides in, which
      // is why §25 keeps the two apart. Whether a *document* may be opened — and, on the
      // editor, whether it is still a draft and still the acting nurse's — is the guard's
      // question, because only the database knows who created it.
      ConsumptionAccess consumptionSectionFor(ConsumptionRouteKind kind) =>
          ConsumptionAccessPolicy.forSection(user: session.user, kind: kind);

      if (location.startsWith(AppRoutes.branchConsumptions)) {
        return consumptionSectionFor(ConsumptionRouteKind.branchList).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.consumptions)) {
        return consumptionSectionFor(ConsumptionRouteKind.nurseList).isGranted
            ? null
            : AppRoutes.home;
      }

      // Retur Barang. Two sections, two roles, two top-level paths — and unlike every
      // pair above, the Warehouse side is deliberately **not** branch-scoped: the goods
      // all arrive at one building, so a Petugas Warehouse works one queue across every
      // branch (§15). What keeps them out of a branch's private work is the *status*
      // scope, which lives in the DAO predicate rather than here. The
      // `/warehouse/returns` prefix is tested first because `/returns` is a prefix of
      // nothing it shares — the two paths are disjoint on purpose, which is what stops
      // a redirect having to decide between them by role.
      GoodsReturnAccess goodsReturnSectionFor(GoodsReturnRouteKind kind) =>
          GoodsReturnAccessPolicy.forSection(user: session.user, kind: kind);

      if (location.startsWith(AppRoutes.warehouseReturns)) {
        return goodsReturnSectionFor(
              GoodsReturnRouteKind.warehouseList,
            ).isGranted
            ? null
            : AppRoutes.home;
      }
      if (location.startsWith(AppRoutes.returns)) {
        return goodsReturnSectionFor(GoodsReturnRouteKind.branchList).isGranted
            ? null
            : AppRoutes.home;
      }

      // Laporan. The audit trail is tested first because `/reports` is its prefix —
      // the one place in this router where two reporting paths do share one, and
      // getting the order wrong would let every role through to the Super Admin's
      // screen on the strength of the shorter match.
      //
      // The rule is [ReportAccessPolicy]'s, as everywhere above: restating
      // "super admin only" here would be a second copy that has to agree with the
      // guard's by hand.
      if (location.startsWith(AppRoutes.exportHistory)) {
        return ReportAccessPolicy.forSection(
              user: session.user,
              kind: ReportRouteKind.exportHistory,
            ).isGranted
            ? null
            : AppRoutes.reports;
      }
      if (location.startsWith(AppRoutes.reports)) {
        return ReportAccessPolicy.forSection(
              user: session.user,
              kind: ReportRouteKind.reports,
            ).isGranted
            ? null
            : AppRoutes.home;
      }
      // `/master` and `/imports` are Super Admin-only in their entirety (G-M1),
      // unlike `/reports` — which every role may enter and whose *contents*
      // differ. The redirect sends the other three home rather than to a
      // dedicated refusal path: a distinct URL would confirm, by the address bar
      // alone, that the section exists and they were kept out of it.
      //
      // The policy is asked rather than the role compared, so this and
      // `MasterAdminSectionGuard` cannot disagree by hand.
      if (location.startsWith(AppRoutes.master) ||
          location.startsWith(AppRoutes.imports)) {
        return MasterAdminAccessPolicy.forSection(
              user: session.user,
              kind: location.startsWith(AppRoutes.imports)
                  ? MasterAdminRouteKind.imports
                  : MasterAdminRouteKind.master,
            ).isGranted
            ? null
            : AppRoutes.home;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.authLoading,
        name: AppRoutes.authLoadingName,
        builder: (context, state) => const AuthLoadingPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const DevelopmentHomePage(),
      ),
      GoRoute(
        path: AppRoutes.sync,
        name: AppRoutes.syncName,
        builder: (context, state) => const SyncCenterPage(),
      ),
      // Declared before `/reports`, so the literal `export-history` segment is
      // never matched as part of the reporting section's own path.
      GoRoute(
        path: AppRoutes.exportHistory,
        name: AppRoutes.exportHistoryName,
        builder: (context, state) => const ReportingSectionGuard(
          kind: ReportRouteKind.exportHistory,
          builder: _exportHistoryPage,
        ),
      ),
      GoRoute(
        path: AppRoutes.reports,
        name: AppRoutes.reportsName,
        builder: (context, state) => const ReportingSectionGuard(
          kind: ReportRouteKind.reports,
          builder: _reportPage,
        ),
      ),
      // --- Master Data & Template Import (Milestone 11) ---------------------
      //
      // `/imports` is declared before `/master` for no ordering reason — they
      // share no prefix — but both sit above the workflow routes so the
      // Super Admin's two sections read together.
      GoRoute(
        path: AppRoutes.imports,
        name: AppRoutes.importsName,
        builder: (context, state) => const MasterAdminSectionGuard(
          kind: MasterAdminRouteKind.imports,
          builder: _masterImportPage,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.importDetail,
            name: AppRoutes.importDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return MasterAdminSectionGuard(
                kind: MasterAdminRouteKind.importDetail,
                builder: (_) => ImportLogDetailPage(importId: id),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.master,
        name: AppRoutes.masterName,
        builder: (context, state) => const MasterAdminSectionGuard(
          kind: MasterAdminRouteKind.master,
          builder: _masterDashboardPage,
        ),
        routes: [
          _masterEntityRoute(
            path: AppRoutes.masterBranches,
            name: AppRoutes.masterBranchesName,
            entity: MasterEntityType.branches,
            list: _masterBranchList,
          ),
          _masterEntityRoute(
            path: AppRoutes.masterRooms,
            name: AppRoutes.masterRoomsName,
            entity: MasterEntityType.rooms,
            list: _masterRoomList,
          ),
          _masterEntityRoute(
            path: AppRoutes.masterUsers,
            name: AppRoutes.masterUsersName,
            entity: MasterEntityType.users,
            list: _masterUserList,
          ),
          _masterEntityRoute(
            path: AppRoutes.masterCategories,
            name: AppRoutes.masterCategoriesName,
            entity: MasterEntityType.itemCategories,
            list: _masterCategoryList,
          ),
          _masterEntityRoute(
            path: AppRoutes.masterItems,
            name: AppRoutes.masterItemsName,
            entity: MasterEntityType.items,
            list: _masterItemList,
          ),
          _masterEntityRoute(
            path: AppRoutes.masterBatches,
            name: AppRoutes.masterBatchesName,
            entity: MasterEntityType.itemBatches,
            list: _masterBatchList,
          ),
        ],
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
      GoRoute(
        path: AppRoutes.warehouseDisposals,
        name: AppRoutes.warehouseDisposalsName,
        builder: (context, state) => const DisposalSectionGuard(
          kind: DisposalRouteKind.warehouseList,
          builder: warehouseDisposalListPage,
        ),
        routes: [
          // Listed first: the literal `new` segment must win over the `:id`
          // pattern, or `/warehouse/disposals/new` would be read as a document id.
          GoRoute(
            path: AppRoutes.warehouseDisposalNew,
            name: AppRoutes.warehouseDisposalNewName,
            builder: (context, state) => const DisposalSectionGuard(
              kind: DisposalRouteKind.warehouseCreate,
              builder: warehouseDisposalListPage,
            ),
          ),
          GoRoute(
            path: AppRoutes.warehouseDisposalDetail,
            name: AppRoutes.warehouseDisposalDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DisposalRouteGuard(
                kind: DisposalRouteKind.warehouseDocument,
                disposalId: id,
                builder: (_) => DisposalDetailPage(disposalId: id),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.warehouseDisposalEdit,
                name: AppRoutes.warehouseDisposalEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  // A distinct kind, not the same one as the detail route: the
                  // editor additionally requires the document to still be a draft
                  // (G-S2), and the policy is where that is decided.
                  return DisposalRouteGuard(
                    kind: DisposalRouteKind.warehouseDraft,
                    disposalId: id,
                    builder: (_) => DisposalFormPage(
                      disposalId: id,
                      scope: DisposalLocationScope.warehouse,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.disposals,
        name: AppRoutes.disposalsName,
        builder: (context, state) => const DisposalSectionGuard(
          kind: DisposalRouteKind.branchList,
          builder: branchDisposalListPage,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.disposalNew,
            name: AppRoutes.disposalNewName,
            builder: (context, state) => const DisposalSectionGuard(
              kind: DisposalRouteKind.branchCreate,
              builder: branchDisposalListPage,
            ),
          ),
          GoRoute(
            path: AppRoutes.disposalDetail,
            name: AppRoutes.disposalDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DisposalRouteGuard(
                kind: DisposalRouteKind.branchDocument,
                disposalId: id,
                builder: (_) => DisposalDetailPage(disposalId: id),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.disposalEdit,
                name: AppRoutes.disposalEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return DisposalRouteGuard(
                    kind: DisposalRouteKind.branchDraft,
                    disposalId: id,
                    builder: (_) => DisposalFormPage(
                      disposalId: id,
                      scope: DisposalLocationScope.branch,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.consumptions,
        name: AppRoutes.consumptionsName,
        builder: (context, state) => const ConsumptionSectionGuard(
          kind: ConsumptionRouteKind.nurseList,
          builder: _consumptionList,
        ),
        routes: [
          // Listed first: the literal `new` segment must win over the `:id` pattern, or
          // `/consumptions/new` would be read as a document id.
          GoRoute(
            path: AppRoutes.consumptionNew,
            name: AppRoutes.consumptionNewName,
            builder: (context, state) => const ConsumptionSectionGuard(
              kind: ConsumptionRouteKind.nurseCreate,
              builder: _consumptionList,
            ),
          ),
          GoRoute(
            path: AppRoutes.consumptionDetail,
            name: AppRoutes.consumptionDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ConsumptionRouteGuard(
                kind: ConsumptionRouteKind.nurseDocument,
                consumptionId: id,
                builder: (_) => ConsumptionDetailPage(consumptionId: id),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.consumptionEdit,
                name: AppRoutes.consumptionEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  // A distinct kind, not the same one as the detail route: the editor
                  // additionally requires the document to still be a draft (G-S2), and
                  // the policy is where that is decided.
                  return ConsumptionRouteGuard(
                    kind: ConsumptionRouteKind.nurseDraft,
                    consumptionId: id,
                    builder: (_) => ConsumptionFormPage(consumptionId: id),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.returns,
        name: AppRoutes.returnsName,
        builder: (context, state) => const GoodsReturnSectionGuard(
          kind: GoodsReturnRouteKind.branchList,
          builder: _branchGoodsReturnList,
        ),
        routes: [
          // Listed first: a literal segment must win over the `:id` pattern, or
          // `/returns/new/{grId}` would be read as a document id.
          GoRoute(
            path: AppRoutes.returnNew,
            name: AppRoutes.returnNewName,
            builder: (context, state) {
              final grId = state.pathParameters['goodReceiptId']!;
              // Two guards, and both earn their place: the section guard refuses a role
              // that has no business here at all, and the create guard refuses a Good
              // Receipt outside the actor's branch — without either of them loading the
              // receipt first (§27).
              return GoodsReturnSectionGuard(
                kind: GoodsReturnRouteKind.branchCreate,
                builder: (_) => GoodsReturnCreateGuard(
                  goodReceiptId: grId,
                  builder: (_) => GoodsReturnCreatePage(goodReceiptId: grId),
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.returnDetail,
            name: AppRoutes.returnDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return GoodsReturnRouteGuard(
                kind: GoodsReturnRouteKind.branchDocument,
                goodsReturnId: id,
                builder: (_) => GoodsReturnDetailPage(goodsReturnId: id),
              );
            },
            routes: [
              GoRoute(
                path: AppRoutes.returnEdit,
                name: AppRoutes.returnEditName,
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  // The note editor is the detail page in draft mode; the separate route
                  // exists so the guard can additionally require `draft` before anything
                  // is fetched (§27).
                  return GoodsReturnRouteGuard(
                    kind: GoodsReturnRouteKind.branchDraft,
                    goodsReturnId: id,
                    builder: (_) => GoodsReturnDetailPage(goodsReturnId: id),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.warehouseReturns,
        name: AppRoutes.warehouseReturnsName,
        builder: (context, state) => const GoodsReturnSectionGuard(
          kind: GoodsReturnRouteKind.warehouseList,
          builder: _warehouseGoodsReturnList,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.warehouseReturnDetail,
            name: AppRoutes.warehouseReturnDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return GoodsReturnRouteGuard(
                kind: GoodsReturnRouteKind.warehouseDocument,
                goodsReturnId: id,
                builder: (_) =>
                    WarehouseGoodsReturnDetailPage(goodsReturnId: id),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.branchConsumptions,
        name: AppRoutes.branchConsumptionsName,
        builder: (context, state) => const ConsumptionSectionGuard(
          kind: ConsumptionRouteKind.branchList,
          builder: _branchConsumptionList,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.branchConsumptionDetail,
            name: AppRoutes.branchConsumptionDetailName,
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ConsumptionRouteGuard(
                kind: ConsumptionRouteKind.branchDocument,
                consumptionId: id,
                builder: (_) => ConsumptionDetailPage(consumptionId: id),
              );
            },
          ),
        ],
      ),
    ],
  );
});

/// `/consumptions` and `/consumptions/new` both land here.
///
/// The list *is* the create surface: its `Catat Pemakaian` button creates the draft and
/// pushes straight into the editor, because a document has to exist before positions can
/// be validated against it. The `new` route exists so a deep link has somewhere to go, and
/// so the section guard has a `nurseCreate` kind to refuse.
Widget _consumptionList(BuildContext context) => const ConsumptionListPage();

Widget _branchConsumptionList(BuildContext context) =>
    const BranchConsumptionListPage();

/// `/returns` — the Kepala Cabang's Retur section.
///
/// The list *is* the create surface: its `Buat Retur` button snapshots the receipt's
/// rejections in one tap and replaces straight into the detail (§30). The `new` route
/// exists so a deep link has somewhere to land, and so the section guard has a
/// `branchCreate` kind to refuse.
Widget _branchGoodsReturnList(BuildContext context) =>
    const BranchGoodsReturnListPage();

Widget _warehouseGoodsReturnList(BuildContext context) =>
    const WarehouseGoodsReturnListPage();

// Top-level builders so the section guards above can stay `const`.
Widget _reportPage(BuildContext context) => const ReportPage();

Widget _masterDashboardPage(BuildContext context) =>
    const MasterDashboardPage();

Widget _masterImportPage(BuildContext context) => const MasterImportPage();

Widget _masterBranchList(BuildContext context) => const MasterBranchListPage();

Widget _masterRoomList(BuildContext context) => const MasterRoomListPage();

Widget _masterUserList(BuildContext context) => const MasterUserListPage();

Widget _masterCategoryList(BuildContext context) =>
    const MasterCategoryListPage();

Widget _masterItemList(BuildContext context) => const MasterItemListPage();

Widget _masterBatchList(BuildContext context) => const MasterBatchListPage();

/// One list, one create form and one edit form per master entity (§37).
///
/// Built by a helper rather than written out six times, because the ordering
/// inside it is load-bearing and easy to get wrong once: `new` is declared
/// **before** `:id`, or the literal segment is matched as a row id and the create
/// form becomes unreachable.
///
/// Every builder is wrapped in [MasterAdminSectionGuard], not only the list. A
/// nested route is reachable by URL without its parent ever building, so a guard
/// on the section alone would leave `/master/users/{id}` open.
RouteBase _masterEntityRoute({
  required String path,
  required String name,
  required MasterEntityType entity,
  required WidgetBuilder list,
}) => GoRoute(
  path: path,
  name: name,
  builder: (context, state) =>
      MasterAdminSectionGuard(kind: MasterAdminRouteKind.master, builder: list),
  routes: [
    GoRoute(
      path: AppRoutes.masterEntityNew,
      name: '$name-new',
      builder: (context, state) => MasterAdminSectionGuard(
        kind: MasterAdminRouteKind.master,
        builder: (_) => MasterEntityFormPage(entity: entity),
      ),
    ),
    GoRoute(
      path: AppRoutes.masterEntityDetail,
      name: '$name-detail',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return MasterAdminSectionGuard(
          kind: MasterAdminRouteKind.master,
          builder: (_) => MasterEntityFormPage(entity: entity, entityId: id),
        );
      },
    ),
  ],
);

Widget _exportHistoryPage(BuildContext context) => const ExportHistoryPage();

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
    _authSubscription = ref.listen<AsyncValue<AuthState>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
    ref.onDispose(dispose);
  }

  late final ProviderSubscription<CurrentUserSession?> _subscription;
  late final ProviderSubscription<AsyncValue<AuthState>> _authSubscription;

  @override
  void dispose() {
    _subscription.close();
    _authSubscription.close();
    super.dispose();
  }
}
