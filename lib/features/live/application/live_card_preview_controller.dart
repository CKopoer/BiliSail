import 'package:bili_player/bili_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../../playback/application/card_preview_playback.dart';
import '../domain/live_preview_repository.dart';
import '../domain/live_room.dart';

final livePreviewRepositoryProvider = Provider<LivePreviewRepository?>(
  (ref) => null,
);

final liveCardPreviewControllerProvider = Provider<LiveCardPreviewController>((
  ref,
) {
  ref.watch(
    authControllerProvider.select((state) => (state.status, state.mid)),
  );
  final controller = LiveCardPreviewController(
    repository: ref.watch(livePreviewRepositoryProvider),
    playback: ref.watch(cardPreviewPlaybackProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final class LiveCardPreviewController {
  LiveCardPreviewController({required this.repository, required this.playback});

  final LivePreviewRepository? repository;
  final CardPreviewPlayback playback;
  RequestCancellation? _hover;
  bool _disposed = false;

  Future<CardPreviewSession?> preview(
    RoomId id,
    RequestCancellation cancellation,
  ) async {
    final repository = this.repository;
    if (_disposed ||
        cancellation.isCancelled ||
        !id.isValid ||
        repository == null) {
      return null;
    }
    _hover?.cancel();
    _hover = cancellation;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    bool current() =>
        !_disposed &&
        !cancellation.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch;
    try {
      final info = await repository.loadPreview(id, cancellation: cancellation);
      if (!current() || !info.isLive) return null;
      // Prefer the homepage's AVC fMP4 stream. Retain server URLs unchanged.
      final streams =
          info.streams.where((stream) => stream.urls.isNotEmpty).toList()
            ..sort((a, b) => _priority(a).compareTo(_priority(b)));
      final sources = <ResolvedMediaSource>[];
      final seen = <Uri>{};
      for (final stream in streams) {
        for (final uri in stream.urls) {
          if (!seen.add(uri)) continue;
          final track = MediaTrack(
            uri: uri,
            requestPolicy: MediaRequestPolicy(
              headers: const {
                'Referer': 'https://live.bilibili.com/',
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36',
              },
            ),
            codec: stream.codec,
          );
          sources.add(
            stream.format == 'flv'
                ? ProgressiveSource(track, isLive: true)
                : ManifestSource(track, isLive: true),
          );
          if (sources.length == 3) break;
        }
        if (sources.length == 3) break;
      }
      final result = await playback.startSources(sources, cancellation);
      if (!current()) {
        cancellation.cancel();
        return null;
      }
      return result;
    } on AppFailure {
      cancellation.cancel();
      rethrow;
    }
  }

  static int _priority(LiveStream stream) =>
      (stream.codec == 'avc' ? 0 : 10) +
      switch (stream.format) {
        'fmp4' => 0,
        'ts' => 1,
        'flv' => 2,
        _ => 3,
      };

  void dispose() {
    _disposed = true;
    _hover?.cancel();
  }
}
