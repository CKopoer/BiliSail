abstract interface class LogExportRepository {
  /// Exports local diagnostics and returns the user-visible saved location.
  Future<String> export();
}
