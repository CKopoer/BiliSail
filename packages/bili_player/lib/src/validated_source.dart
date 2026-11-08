import 'player_contract.dart';

/// In-memory preparation plan. Never serialize media addresses or headers.
final class ValidatedSource {
  const ValidatedSource({
    required this.source,
    required this.options,
    required this.media,
    this.audio,
    this.requiresVideo = false,
    this.audioOnly = false,
    this.silent = false,
    this.live = false,
  });

  final ResolvedMediaSource source;
  final OpenOptions options;
  final MediaTrack media;
  final MediaTrack? audio;
  final bool requiresVideo, audioOnly, silent, live;

  static bool validGain(double value) =>
      value.isFinite && value >= -60 && value <= 30;

  static ValidatedSource validate(
    ResolvedMediaSource source,
    OpenOptions options,
    int generation, {
    Set<String> schemes = const {'http', 'https', 'file'},
  }) {
    Never invalid(
      String message, [
      PlayerFailureKind kind = PlayerFailureKind.invalidSource,
    ]) => throw PlayerFailure(kind, message, generation);
    if (options.startPosition < Duration.zero ||
        options.openTimeout <= Duration.zero ||
        !options.rate.isFinite ||
        options.rate <= 0 ||
        !options.volume.isFinite ||
        options.volume < 0 ||
        options.volume > 100 ||
        !validGain(options.audioGainDb) ||
        options.maxBufferAhead <= Duration.zero ||
        options.maxBufferAhead > OpenOptions.maximumBufferAhead) {
      invalid('无效的播放参数');
    }
    final (
      media,
      audio,
      requiresVideo,
      audioOnly,
      silent,
      live,
    ) = switch (source) {
      ProgressiveSource(:final media, :final isAudioOnly, :final isLive) => (
        media,
        null,
        false,
        isAudioOnly,
        false,
        isLive,
      ),
      ManifestSource(:final media, :final isLive) => (
        media,
        null,
        false,
        false,
        false,
        isLive,
      ),
      DashPairSource(
        :final video,
        :final audio,
        :final isIntentionallySilent,
      ) =>
        (
          video,
          audio,
          true,
          false,
          audio == null && isIntentionallySilent,
          false,
        ),
      DashVideoSource(:final video) => (video, null, true, false, true, false),
    };
    if (source is DashPairSource && audio == null && !silent) {
      invalid('DASH 音轨缺失');
    }
    if (source is DashVideoSource && options.volume != 0) invalid('无音轨预览必须静音');
    for (final track in [media, ?audio]) {
      if (!schemes.contains(track.uri.scheme) ||
          track.uri.userInfo.isNotEmpty ||
          (track.uri.scheme != 'file' && track.uri.host.isEmpty)) {
        invalid('不支持的媒体地址');
      }
      final names = <String>{};
      for (final entry in track.requestPolicy.headers.entries) {
        final name = entry.key.toLowerCase();
        if (!{'user-agent', 'referer', 'origin', 'accept'}.contains(name) ||
            !names.add(name) ||
            entry.key.contains(RegExp(r'[\r\n]')) ||
            entry.value.contains(RegExp(r'[\r\n]'))) {
          invalid('不支持的媒体请求头', PlayerFailureKind.unsupportedHeaders);
        }
      }
    }
    Map<String, String> headers(MediaTrack track) => {
      for (final entry in track.requestPolicy.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final first = headers(media);
    if (audio != null) {
      final second = headers(audio);
      if (first.length != second.length ||
          first.entries.any((entry) => second[entry.key] != entry.value)) {
        invalid('分轨请求头必须相同', PlayerFailureKind.unsupportedHeaders);
      }
    }
    const previewWindow = Duration(seconds: 5);
    final effectiveOptions =
        live ||
            (source is DashVideoSource &&
                options.maxBufferAhead > previewWindow)
        ? OpenOptions(
            startPosition: live ? Duration.zero : options.startPosition,
            play: options.play,
            rate: live ? 1 : options.rate,
            volume: options.volume,
            audioGainDb: options.audioGainDb,
            videoDecoding: options.videoDecoding,
            androidVideoOutput: options.androidVideoOutput,
            openTimeout: options.openTimeout,
            retainPresentation: options.retainPresentation,
            maxBufferAhead: source is DashVideoSource
                ? previewWindow
                : options.maxBufferAhead,
          )
        : options;
    return ValidatedSource(
      source: source,
      options: effectiveOptions,
      media: media,
      audio: audio,
      requiresVideo: requiresVideo,
      audioOnly: audioOnly,
      silent: silent,
      live: live,
    );
  }
}
