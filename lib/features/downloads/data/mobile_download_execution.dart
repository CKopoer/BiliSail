import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import 'http_download_transfer.dart';

abstract final class MobileDownloadExecution {
  static const channel = MethodChannel('dev.bilisail/background_downloads');

  static Future<void> setActive(
    bool active,
    Future<void> Function() onTimeout,
  ) async {
    channel.setMethodCallHandler(
      active
          ? (call) async {
              if (call.method == 'timeout') await onTimeout();
            }
          : null,
    );
    try {
      await channel.invokeMethod<void>('setActive', active);
    } on MissingPluginException {
      if (active) throw const AppFailure(AppFailureKind.unknown, '后台下载服务不可用');
    } on PlatformException {
      throw const AppFailure(AppFailureKind.permission, '系统未允许后台下载，请回到应用后重试');
    }
  }
}

final class IosBackgroundTransfer implements BackgroundTrackTransfer {
  const IosBackgroundTransfer();

  static int _nextId = 0;

  @override
  bool get inBackground => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden || AppLifecycleState.paused => true,
    _ => false,
  };

  @override
  void Function() onHide(void Function() callback) =>
      AppLifecycleListener(onHide: callback).dispose;

  @override
  Future<TrackHttpResponse> fetch(
    Uri url,
    Map<String, String> headers,
    RequestCancellation cancellation,
    DateTime? deadline,
  ) async {
    const channel = MobileDownloadExecution.channel;
    final id = ++_nextId;
    final pending = channel.invokeMapMethod<String, Object?>('fetch', {
      'id': id,
      'url': url.toString(),
      'headers': headers,
      'timeout':
          (deadline?.difference(DateTime.now()) ?? const Duration(hours: 3))
              .inSeconds
              .clamp(1, 10800),
    });
    var finished = false;
    cancellation.onCancel(() {
      if (!finished) unawaited(channel.invokeMethod<void>('cancel', id));
    });
    try {
      final response = await pending;
      if (response case {
        'file': final String path,
        'status': final int status,
        'length': final int length,
      }) {
        final file = File(path);
        return TrackHttpResponse(
          status: status,
          length: length,
          range: response['range'] as String?,
          etag: response['etag'] as String?,
          body: file.openRead(),
          stagedFile: file,
        );
      }
      throw const AppFailure(AppFailureKind.protocol, '后台下载响应无效');
    } on PlatformException catch (error) {
      if (cancellation.isCancelled) {
        throw const AppFailure(AppFailureKind.cancelled, '下载已取消');
      }
      if (error.code == 'storage') {
        throw const AppFailure(AppFailureKind.storage, '后台下载临时文件不可用');
      }
      if (error.code == 'request' || error.code == 'response') {
        throw const AppFailure(AppFailureKind.protocol, '后台下载请求或响应无效');
      }
      if (error.code == 'timeout') throw TimeoutException('后台下载超时');
      throw const SocketException('后台下载连接中断');
    } finally {
      finished = true;
    }
  }
}
