import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/core_diagnostic_log.dart';
import '../../../domain/app_failure.dart';
import '../domain/download_models.dart';

final class IosDownloadPhotosExporter {
  IosDownloadPhotosExporter(this.diagnostics);

  static const _channel = MethodChannel('dev.bilisail/download_photos');
  final CoreDiagnosticLog? diagnostics;
  Future<void>? _permissionRequest;

  Future<void> requestAccess() => _permissionRequest ??= _requestAccess()
      .whenComplete(() => _permissionRequest = null);

  Future<void> _requestAccess() async {
    try {
      await _channel
          .invokeMethod<void>('requestAccess')
          .timeout(const Duration(minutes: 1));
    } on PlatformException {
      // The download can proceed. Import records the resulting access state.
    } on TimeoutException {
      // Do not hold the queue if the system prompt never completes.
    } on MissingPluginException {
      // Photos access is optional for offline downloads.
    }
  }

  Future<void> save(DownloadTask task) async {
    final media = task.mergedMedia;
    if (media == null) return;
    AppFailureKind? failure;
    try {
      await _channel
          .invokeMethod<void>('saveVideo', {
            'scopeDirectory': p.basename(p.dirname(task.directory)),
            'taskId': task.id,
            'fileName': media.fileName,
          })
          .timeout(const Duration(minutes: 2));
    } on PlatformException catch (error) {
      failure = switch (error.code) {
        'permission' => AppFailureKind.permission,
        'unsupported' => AppFailureKind.playback,
        'missing' => AppFailureKind.notFound,
        _ => AppFailureKind.storage,
      };
    } on TimeoutException {
      failure = AppFailureKind.timeout;
    } on MissingPluginException {
      failure = AppFailureKind.storage;
    }
    diagnostics?.record(
      CoreDiagnosticEvent.downloadPhotosExport,
      mediaFormat: media.output.name,
      outcome: failure == null
          ? CoreDiagnosticOutcome.success
          : CoreDiagnosticOutcome.failed,
      error: failure == null ? null : AppFailure(failure, ''),
    );
  }
}
