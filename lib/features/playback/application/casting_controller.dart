import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../core/platform/casting_support.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/casting.dart';
import '../domain/content_playback.dart';
import 'playback_session.dart';

final castMediaRepositoryProvider = Provider<CastMediaRepository>(
  (ref) => throw UnimplementedError('CastMediaRepository'),
);
final castDeviceRepositoryFactoryProvider =
    Provider<CastDeviceRepository Function()>(
      (ref) => throw UnimplementedError('CastDeviceRepository'),
    );
final castLifetimeTrackerProvider =
    Provider<void Function() Function(RequestCancellation)>(
      (ref) =>
          (_) => () {},
    );

CastMediaRequest? castRequestFor(PlaybackSession session) {
  final media = session.media;
  final detail = session.detail;
  if (!supportsDlnaCasting || media == null || session.isResolving) {
    return null;
  }
  final cid = session.danmakuCid;
  if (cid == null) return null;
  return switch (session.contentTarget) {
    PgcPlaybackTarget(:final episodeId) => CastMediaRequest(
      episodeId: episodeId,
      cid: cid,
      quality: media.quality,
    ),
    null when detail != null => CastMediaRequest(
      aid: detail.aid,
      bvid: detail.summary.id.value,
      cid: cid,
      quality: media.quality,
    ),
    _ => null,
  };
}

enum CastingTransport { playing, paused, stopped }

class CastingController extends ChangeNotifier {
  CastingController({
    required this.request,
    required this.title,
    required this.mediaRepository,
    required this.deviceRepository,
    required this.pauseLocal,
    required this.isCurrent,
    required this.source,
    required void Function() Function(RequestCancellation) trackLifetime,
  }) {
    _untrack = trackLifetime(_lifetime);
    _lifetime.onCancel(_invalidate);
    source.addListener(_sourceChanged);
  }
  final CastMediaRequest request;
  final String title;
  final CastMediaRepository mediaRepository;
  final CastDeviceRepository deviceRepository;
  final Future<void> Function() pauseLocal;
  final bool Function() isCurrent;
  final Listenable source;
  final _lifetime = RequestCancellation();
  late final void Function() _untrack;
  RequestCancellation? _search, _operation;
  final _devices = <String, CastDevice>{};
  List<CastDevice> get devices => List.unmodifiable(_devices.values);
  CastDevice? selected;
  CastingTransport? transport;
  bool searching = false, busy = false, invalidated = false, _disposed = false;
  String? message;

  bool get _current => !_disposed && !_lifetime.isCancelled && isCurrent();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sourceChanged() {
    if (!_current) _lifetime.cancel();
  }

  void _invalidate() {
    _search?.cancel();
    _operation?.cancel();
    deviceRepository.dispose();
    invalidated = true;
    searching = false;
    busy = false;
    message = '播放内容或账号已变化，请关闭后重新打开投屏';
    _notify();
  }

  Future<void> search() async {
    if (!_current || searching) return;
    final token = RequestCancellation();
    _search = token;
    _devices.clear();
    searching = true;
    message = null;
    _notify();
    try {
      await for (final device in deviceRepository.discover(
        cancellation: token,
      )) {
        if (!_current || token.isCancelled) break;
        if (_devices.length < 64 || _devices.containsKey(device.id)) {
          _devices[device.id] = device;
          _notify();
        }
      }
    } on AppFailure catch (error) {
      if (_current && error.kind != AppFailureKind.cancelled) {
        message = error.message;
      }
    } catch (_) {
      if (_current) message = '搜索设备失败，请检查网络后重试';
    } finally {
      token.cancel();
      if (identical(_search, token)) {
        _search = null;
        searching = false;
        _notify();
      }
    }
  }

  Future<void> connect(CastDevice device) => _run((token) async {
    if (selected?.id == device.id) return;
    // Resolve again on each selection so an expired signed URL is not reused.
    final uri = await mediaRepository.resolve(request, cancellation: token);
    if (!_current || token.isCancelled) return;
    if (selected case final previous?) {
      await deviceRepository.command(
        previous,
        CastCommand.stop,
        cancellation: token,
      );
      if (!_current || token.isCancelled) return;
      selected = null;
      transport = null;
    }
    await deviceRepository.setMedia(device, uri, title, cancellation: token);
    if (!_current || token.isCancelled) return;
    await deviceRepository.command(
      device,
      CastCommand.play,
      cancellation: token,
    );
    if (!_current || token.isCancelled) return;
    selected = device;
    transport = CastingTransport.playing;
    await pauseLocal();
  });

  Future<void> control(CastCommand command) => _run((token) async {
    final device = selected;
    if (device == null) return;
    await deviceRepository.command(device, command, cancellation: token);
    if (!_current || token.isCancelled) return;
    transport = switch (command) {
      CastCommand.play => CastingTransport.playing,
      CastCommand.pause => CastingTransport.paused,
      CastCommand.stop => CastingTransport.stopped,
    };
    if (command == CastCommand.stop) selected = null;
  });

  Future<void> _run(Future<void> Function(RequestCancellation) action) async {
    if (!_current || busy) return;
    final token = RequestCancellation();
    _operation = token;
    busy = true;
    message = null;
    _notify();
    try {
      await action(token);
    } on AppFailure catch (error) {
      if (_current && error.kind != AppFailureKind.cancelled) {
        message = error.message;
      }
    } catch (_) {
      if (_current) message = '投屏操作失败，请在电视上检查播放状态后重试';
    } finally {
      token.cancel();
      if (identical(_operation, token)) {
        _operation = null;
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    source.removeListener(_sourceChanged);
    _untrack();
    _lifetime.cancel();
    super.dispose();
  }
}
