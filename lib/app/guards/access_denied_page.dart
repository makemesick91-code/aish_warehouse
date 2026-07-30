import 'package:flutter/material.dart';

import '../../core/errors/failure_presenter.dart';
import '../theme.dart';

/// The screen every refused route lands on.
///
/// It names nothing: not the document, not the branch that owns it, not whether
/// the id exists. "Belongs to another branch" and "does not exist" are
/// deliberately indistinguishable, because telling them apart would turn the
/// address bar into a way to enumerate documents across the clinic group
/// (§6.5).
///
/// It lives beside the guards rather than inside one, so the next module with
/// something to refuse — Purchase Request, Good Receipt — reuses this screen
/// instead of importing from `features/opname/` or writing a second one.
class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  /// Lets tests and screens address this state without matching on prose.
  static const Key pageKey = ValueKey('accessDenied');

  static const String title = 'Akses Ditolak';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: pageKey,
      appBar: AppBar(title: const Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                accessDeniedMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
