import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';

class UserRoleConverter extends TypeConverter<UserRole, String> {
  const UserRoleConverter();

  @override
  UserRole fromSql(String fromDb) => UserRole.fromDbValue(fromDb);

  @override
  String toSql(UserRole value) => value.dbValue;
}

class SyncStatusConverter extends TypeConverter<SyncStatus, String> {
  const SyncStatusConverter();

  @override
  SyncStatus fromSql(String fromDb) => SyncStatus.fromDbValue(fromDb);

  @override
  String toSql(SyncStatus value) => value.dbValue;
}

class StockLocationTypeConverter
    extends TypeConverter<StockLocationType, String> {
  const StockLocationTypeConverter();

  @override
  StockLocationType fromSql(String fromDb) =>
      StockLocationType.fromDbValue(fromDb);

  @override
  String toSql(StockLocationType value) => value.dbValue;
}

class StockOpnameStatusConverter
    extends TypeConverter<StockOpnameStatus, String> {
  const StockOpnameStatusConverter();

  @override
  StockOpnameStatus fromSql(String fromDb) =>
      StockOpnameStatus.fromDbValue(fromDb);

  @override
  String toSql(StockOpnameStatus value) => value.dbValue;
}

class PurchaseRequestStatusConverter
    extends TypeConverter<PurchaseRequestStatus, String> {
  const PurchaseRequestStatusConverter();

  @override
  PurchaseRequestStatus fromSql(String fromDb) =>
      PurchaseRequestStatus.fromDbValue(fromDb);

  @override
  String toSql(PurchaseRequestStatus value) => value.dbValue;
}

class DeliveryOrderStatusConverter
    extends TypeConverter<DeliveryOrderStatus, String> {
  const DeliveryOrderStatusConverter();

  @override
  DeliveryOrderStatus fromSql(String fromDb) =>
      DeliveryOrderStatus.fromDbValue(fromDb);

  @override
  String toSql(DeliveryOrderStatus value) => value.dbValue;
}

class GoodReceiptStatusConverter
    extends TypeConverter<GoodReceiptStatus, String> {
  const GoodReceiptStatusConverter();

  @override
  GoodReceiptStatus fromSql(String fromDb) =>
      GoodReceiptStatus.fromDbValue(fromDb);

  @override
  String toSql(GoodReceiptStatus value) => value.dbValue;
}

class GoodReceiptLineStatusConverter
    extends TypeConverter<GoodReceiptLineStatus, String> {
  const GoodReceiptLineStatusConverter();

  @override
  GoodReceiptLineStatus fromSql(String fromDb) =>
      GoodReceiptLineStatus.fromDbValue(fromDb);

  @override
  String toSql(GoodReceiptLineStatus value) => value.dbValue;
}

class DistributionStatusConverter
    extends TypeConverter<DistributionStatus, String> {
  const DistributionStatusConverter();

  @override
  DistributionStatus fromSql(String fromDb) =>
      DistributionStatus.fromDbValue(fromDb);

  @override
  String toSql(DistributionStatus value) => value.dbValue;
}

class DisposalStatusConverter extends TypeConverter<DisposalStatus, String> {
  const DisposalStatusConverter();

  @override
  DisposalStatus fromSql(String fromDb) => DisposalStatus.fromDbValue(fromDb);

  @override
  String toSql(DisposalStatus value) => value.dbValue;
}

class StockMovementTypeConverter
    extends TypeConverter<StockMovementType, String> {
  const StockMovementTypeConverter();

  @override
  StockMovementType fromSql(String fromDb) =>
      StockMovementType.fromDbValue(fromDb);

  @override
  String toSql(StockMovementType value) => value.dbValue;
}
