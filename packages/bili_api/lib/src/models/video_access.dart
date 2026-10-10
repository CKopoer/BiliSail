enum ApiVideoAccessKind { normal, chargingExclusive, paid }

/// Content classification is separate from the current account's entitlement.
final class ApiVideoAccess {
  const ApiVideoAccess({
    this.kind = ApiVideoAccessKind.normal,
    this.canWatch,
    this.canPreview = false,
  });

  final ApiVideoAccessKind kind;

  /// Null when a list does not supply account-specific viewing permission.
  final bool? canWatch;
  final bool canPreview;
}
