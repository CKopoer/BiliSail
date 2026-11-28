part of 'playback_session.dart';

typedef FeaturedMediaResolver = Future<PlaybackMedia> Function(
  VideoId video,
  String cid, {
  required int quality,
  required VideoCodecPreference preferredCodec,
  required RequestCancellation cancellation,
});

extension FeaturedSessionPreparation on PlaybackSession {
  /// A visible feed nominates one neighbor. Wait for the selected card to
  /// finish opening before allocating its neighbor's native decoder.
  void setFeaturedNeighbor(
    Object owner,
    (VideoId, String?) current,
    (VideoId, String)? neighbor,
  ) {
    if (_closing || _disposed || featuredStandby == null) return;
    _featuredOwner = owner;
    _featuredCurrent = current;
    _featuredNeighbor = neighbor;
    _prepareFeaturedNeighbor();
  }

  void leaveFeatured(Object owner) {
    if (!identical(owner, _featuredOwner)) return;
    _featuredOwner = null;
    _featuredCurrent = null;
    _featuredNeighbor = null;
    unawaited(featuredStandby?.clear(owner: this));
  }

  void _prepareFeaturedNeighbor() {
    final selected = _featuredCurrent;
    final standby = featuredStandby;
    final resolve = resolveFeatured;
    if (selected == null ||
        standby == null ||
        resolve == null ||
        !_playbackAllowed ||
        _closing ||
        _disposed ||
        _resolving ||
        media == null ||
        contentTarget != null ||
        !sourceMatchesAccount ||
        selected.$1 != detail?.summary.id ||
        (selected.$2 != null && selected.$2 != part?.cid)) {
      return;
    }
    final neighbor = _featuredNeighbor;
    if (neighbor == null || _listeningMode.enabled || neighbor == selected) {
      unawaited(standby.clear(owner: this));
      return;
    }
    final (id, cid) = neighbor;
    final scope = accountScope();
    final settings = _settings;
    final epoch = sessionEpoch();
    final checkpoint = _navigationCheckpoints[(id, (cid, null), null)];
    final restored = checkpoint?.scope == scope && checkpoint?.epoch == epoch
        ? checkpoint
        : null;
    if (restored?.voice.isOriginal == false) {
      unawaited(standby.clear(owner: this));
      return;
    }
    final rate =
        restored?.rate ?? _rateMemory.rateFor(settings.defaultPlaybackRate);
    standby.prepare((scope, epoch, id, cid), (cancel) async {
      if (_retiringEngine case final retired?) await retired;
      void check() {
        if (cancel.isCancelled) {
          throw const AppFailure(AppFailureKind.cancelled, '预加载已取消');
        }
      }

      check();
      final media = await resolve(
        id,
        cid,
        quality: restored?.quality ?? settings.preferredQuality,
        preferredCodec: settings.preferredVideoCodec,
        cancellation: cancel,
      );
      check();
      final audioQuality = restored?.audioQuality;
      final resolved = audioQuality == null
          ? media
          : media.selectAudioQuality(audioQuality);
      // A passthrough/system Dolby route can reserve the hardware audio
      // device even while paused. Open it only when this card owns playback.
      if (resolved.audioQuality == AudioQualityPreference.dolby ||
          AudioQualityPreference.identify(0, resolved.audio?.codec ?? '') ==
              AudioQualityPreference.dolby) {
        throw const AppFailure(AppFailureKind.playback, '杜比音频在切换后打开');
      }
      final position =
          restored?.position ??
          (settings.resumePlayback
              ? await progress.read(scope, id, cid)
              : null);
      check();
      final source = selectPlaybackSource(
        resolved,
        requestedAudioOnly: false,
        isLive: false,
        requestedLiveLine: 0,
      ).source;
      return (
        source: source,
        options: OpenOptions(
          startPosition: position ?? Duration.zero,
          rate: rate,
          volume: 0,
          audioGainDb: _audioGainFor(resolved),
          videoDecoding:
              settings.videoDecoding == VideoDecodingPreference.software
              ? VideoDecodingMode.software
              : VideoDecodingMode.automatic,
          androidVideoOutput:
              settings.androidVideoOutput ==
                  AndroidVideoOutputPreference.directTexture
              ? AndroidVideoOutputMode.directTexture
              : AndroidVideoOutputMode.renderedTexture,
          androidAudioOutput: settings.androidAudioOutput,
          cacheLimits: settings.playbackCacheLimits(live: false),
        ),
      );
    }, owner: this);
  }

  Future<bool> _useFeaturedEngine(
    VideoId id,
    String cid,
    ResolvedMediaSource source,
    OpenOptions options,
    RequestCancellation cancellation,
    bool Function() isCurrent,
  ) async {
    if (_featuredOwner == null || !_playbackAllowed) return false;
    final pending = featuredStandby?.take(
      (accountScope(), sessionEpoch(), id, cid),
      source,
      options,
      cancellation,
      owner: this,
    );
    if (pending == null) return false;
    final ready = await pending;
    if (ready == null) return false;
    if (!isCurrent() || !_playbackAllowed || _featuredOwner == null) {
      _retireFeaturedEngine(ready);
      return false;
    }
    // The old source is already stopped. Bind synchronously so cancellation,
    // account changes and close always have an owner to stop the new engine.
    final old = engine;
    final subscriptions = _subscriptions.toList();
    _subscriptions.clear();
    _engine = ready;
    _listenToEngine(ready);
    _onSnapshot(ready.currentSnapshot);
    _retireFeaturedEngine(old, subscriptions);
    _notify();
    try {
      await ready.setVolume(options.volume).timeout(const Duration(seconds: 2));
    } on Object {
      // The normal foreground open will reset this engine's source and volume.
      return false;
    }
    return true;
  }

  void _retireFeaturedEngine(
    PlayerEngine old, [
    List<StreamSubscription<Object?>> subscriptions = const [],
  ]) {
    Future<void> release() async {
      try {
        await Future.wait([
          for (final subscription in subscriptions) subscription.cancel(),
        ]);
      } finally {
        await old.dispose();
      }
    }

    final retiring = _retiringEngine = release();
    // Keep a failed retirement for close() to report; further preparations
    // wait on it and fall back without allocating another native player.
    retiring.then((_) {
      if (identical(_retiringEngine, retiring)) _retiringEngine = null;
    }).ignore();
  }
}
