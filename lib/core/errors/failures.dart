import '../quantity/quantity.dart';

/// Business-rule failures for Aish Warehouse.
///
/// Every guardrail violation throws a specific subtype so the UI can present a
/// meaningful Indonesian message instead of a raw stack trace.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Generic input validation (qty, empty text, illegal combination…).
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

/// The source location does not hold enough stock for the requested posting.
final class InsufficientStockFailure extends AppFailure {
  const InsufficientStockFailure(
    super.message, {
    required this.itemId,
    required this.locationId,
    this.batchId,
    required this.available,
    required this.requested,
  });

  final String itemId;
  final String locationId;
  final String? batchId;
  final Quantity available;
  final Quantity requested;
}

/// Item is tracked per batch (`has_expiry = true`) but no batch was supplied.
final class BatchRequiredFailure extends AppFailure {
  const BatchRequiredFailure(super.message, {required this.itemId});

  final String itemId;
}

/// Item is not tracked per batch but a batch was supplied.
final class BatchNotAllowedFailure extends AppFailure {
  const BatchNotAllowedFailure(super.message, {required this.itemId});

  final String itemId;
}

/// The batch is past its expiry date and cannot be used for this movement.
final class ExpiredBatchFailure extends AppFailure {
  const ExpiredBatchFailure(
    super.message, {
    required this.batchId,
    required this.expiryDate,
  });

  final String batchId;
  final DateTime expiryDate;
}

/// Location is missing, of the wrong type, or source equals destination.
final class InvalidLocationFailure extends AppFailure {
  const InvalidLocationFailure(super.message);
}

/// Attempt to mutate the append-only ledger.
final class MovementImmutableFailure extends AppFailure {
  const MovementImmutableFailure(super.message, {required this.movementId});

  final String movementId;
}

/// A referenced row (item, batch, location, user…) does not exist.
final class EntityNotFoundFailure extends AppFailure {
  const EntityNotFoundFailure(
    super.message, {
    required this.entity,
    required this.id,
  });

  final String entity;
  final String id;
}
