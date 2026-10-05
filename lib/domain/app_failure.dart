enum AppFailureKind {
  network,
  timeout,
  cancelled,
  authentication,
  permission,
  rateLimited,
  notFound,
  protocol,
  storage,
  playback,
  unknown,
}

final class AppFailure implements Exception {
  const AppFailure(this.kind, this.message);

  final AppFailureKind kind;
  final String message;

  @override
  String toString() => message;
}
