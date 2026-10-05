import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../domain/account_overview.dart';
import 'auth_controller.dart';

/// The composition root supplies the inbox indicator without an auth -> messages dependency.
final accountMessageIndicatorProvider = Provider<AccountMessageIndicator>(
  (ref) => const AccountMessageIndicator(),
);

final class AccountMessageIndicator {
  const AccountMessageIndicator({
    this.count = 0,
    this.failed = false,
    this.refresh,
  });
  final int count;
  final bool failed;
  final void Function()? refresh;
}

final accountOverviewRepositoryProvider = Provider<AccountOverviewRepository>(
  (ref) => throw UnimplementedError('AccountOverviewRepository'),
);
final accountOverviewProvider = FutureProvider.autoDispose<AccountOverview?>((
  ref,
) async {
  final account = ref.watch(
    authControllerProvider.select((s) => (s.isSignedIn, s.mid)),
  );
  final mid = account.$2;
  if (!account.$1 || mid == null) return null;
  final cancellation = RequestCancellation();
  ref.onDispose(cancellation.cancel);
  return ref
      .watch(accountOverviewRepositoryProvider)
      .load(mid, cancellation: cancellation);
});
