part of 'playback_session.dart';

const featuredPlaybackHistoryLimit = 8;

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
    if (_featuredHistoryOwner case final previous?
        when !identical(previous, owner)) {
      clearFeaturedVisits(previous);
    }
    _featuredHistoryOwner = owner;
    _featuredOwner = owner;
    _featuredCurrent = current;
    _featuredNeighbor = neighbor;
    // The feed may rebuild with the same card after clearing its history.
    _restoreFeaturedPresentation(detail, part, contentTarget, notify: false);
    _prepareFeaturedNeighbor();
  }

  void setFeaturedSwipePreview(
    Object owner,
    (VideoId, String)? clip, {
    bool keepSelected = false,
  }) {
    if (!identical(owner, _featuredOwner) ||
        _closing ||
        _disposed ||
        !_playbackAllowed) {
      return;
    }
    final preview = _featuredSwipePreview;
    if (keepSelected &&
        clip == null &&
        preview != null &&
        _isFeaturedCurrent(preview)) {
      return;
    }
    if (_featuredSwipePreview == clip) return;
    _featuredSwipePreview = clip;
    _syncFeaturedSwipePreview();
    _prepareFeaturedNeighbor();
  }

  bool _isFeaturedCurrent((VideoId, String) clip) =>
      _featuredCurrent?.$1 == clip.$1 &&
      (_featuredCurrent?.$2 == null || _featuredCurrent?.$2 == clip.$2);

  void _finishFeaturedSwipePreview((VideoId, String)? clip) {
    if (_featuredSwipePreview == null || _featuredSwipePreview != clip) return;
    _featuredSwipePreview = null;
    _syncFeaturedSwipePreview();
  }

  void _syncFeaturedSwipePreview() {
    var clip = _featuredSwipePreview;
    if (clip != null &&
        (!_playbackAllowed ||
            _closing ||
            !sourceMatchesAccount ||
            sleepTimer.elapsed ||
            _listeningMode.enabled ||
            !_featuredPreviewIntent(clip))) {
      clip = null;
    }
    final paused = _featuredPaused;
    final usePaused =
        clip != null &&
        paused?.clip == clip &&
        _usableFeaturedVisit(_featuredVisits[clip], _featuredProfile);
    paused?.preview.show(usePaused);
    featuredStandby?.setVisiblePreview(
      clip == null || usePaused
          ? null
          : (accountScope(), sessionEpoch(), clip.$1, clip.$2),
      owner: this,
    );
  }

  bool _featuredPreviewIntent((VideoId, String) clip) {
    if (_nextSourceIntent case final next?
        when next.id == clip.$1 &&
            (next.cid == null || next.cid == clip.$2) &&
            next.scope == accountScope() &&
            next.epoch == sessionEpoch()) {
      return next.playing;
    }
    final saved = _featuredVisits[clip]?.checkpoint;
    return saved != null &&
            saved.scope == accountScope() &&
            saved.epoch == sessionEpoch()
        ? saved.desiredPlaying
        : _settings.autoPlay;
  }

  void leaveFeatured(Object owner) {
    if (!identical(owner, _featuredOwner)) return;
    _featuredOwner = null;
    _featuredCurrent = null;
    _featuredNeighbor = null;
    _featuredSwipePreview = null;
    unawaited(featuredStandby?.clear(owner: this));
    _discardFeaturedPaused();
    _discardFeaturedClaimed();
  }

  void clearFeaturedVisits(Object owner) {
    if (!identical(owner, _featuredHistoryOwner)) return;
    _featuredHistoryOwner = null;
    _featuredVisits.clear();
    _featuredPlaying = null;
    _featuredPresentation = null;
    _featuredSwipePreview = null;
    unawaited(featuredStandby?.clear(owner: this));
    _discardFeaturedPaused();
    _discardFeaturedClaimed();
  }

  bool hasFeaturedVisit(VideoId video, String? cid) {
    final profile = _featuredProfile;
    if (cid != null) {
      return _usableFeaturedVisit(_featuredVisits[(video, cid)], profile);
    }
    return _featuredVisits.entries.any(
      (entry) =>
          entry.key.$1 == video && _usableFeaturedVisit(entry.value, profile),
    );
  }

  PlayerEngine? featuredPreview(VideoId video, String? cid) {
    if (!_playbackAllowed ||
        _featuredOwner == null ||
        !sourceMatchesAccount ||
        _disposed ||
        _closing) {
      return null;
    }
    if (_featuredClaimed case final claimed?
        when claimed.clip.$1 == video &&
            (cid == null || claimed.clip.$2 == cid)) {
      return claimed.engine;
    }
    if (_featuredPaused case final paused?
        when paused.clip.$1 == video &&
            (cid == null || paused.clip.$2 == cid) &&
            _usableFeaturedVisit(
              _featuredVisits[paused.clip],
              _featuredProfile,
            )) {
      return paused.engine;
    }
    final part =
        cid ?? (_featuredNeighbor?.$1 == video ? _featuredNeighbor?.$2 : null);
    return part == null
        ? null
        : featuredStandby?.preview((
            accountScope(),
            sessionEpoch(),
            video,
            part,
          ), owner: this);
  }

  PlayerEngine? featuredSlotEngine(
    Object owner,
    VideoId video,
    String? cid, {
    required bool allowPreview,
  }) {
    if (cid == null || _audioOnly || _disposed || _closing) return null;
    final active = _featuredPresentation;
    if (active != null &&
        identical(active.owner, owner) &&
        active.scope == accountScope() &&
        active.epoch == sessionEpoch() &&
        active.clip == (video, cid) &&
        identical(active.engine, engine)) {
      return active.engine;
    }
    return allowPreview && identical(owner, _featuredOwner)
        ? featuredPreview(video, cid)
        : null;
  }

  void _markFeaturedPresentation((VideoId, String) clip, PlayerEngine player) {
    if (_featuredHistoryOwner case final owner?) {
      _featuredPresentation = (
        owner: owner,
        clip: clip,
        scope: _scope,
        epoch: _epoch,
        engine: player,
      );
    }
  }

  void _restoreFeaturedPresentation(
    VideoDetail? video,
    VideoPart? selected,
    ContentPlaybackTarget? target, {
    bool notify = true,
  }) {
    if (target != null ||
        _resolving ||
        media == null ||
        !sourceMatchesAccount ||
        !_isFeaturedClip(video, selected)) {
      return;
    }
    final clip = (video!.summary.id, selected!.cid);
    if (_featuredPresentation?.clip == clip &&
        identical(_featuredPresentation?.engine, engine) &&
        identical(_featuredPresentation?.owner, _featuredHistoryOwner)) {
      return;
    }
    // Re-entering the same loaded source can skip opening entirely.
    _markFeaturedPresentation(clip, engine);
    if (notify) _notify();
  }

  Object get _featuredProfile => (
    _settings.preferredQuality,
    _settings.preferredVideoCodec,
    _settings.preferredAudioQuality,
    _settings.mediaCdn,
    _settings.videoDecoding,
    _settings.androidVideoOutput,
    _settings.androidAudioOutput,
    _settings.playbackCacheLimits(live: false),
  );

  bool _isFeaturedClip(VideoDetail? video, VideoPart? part) =>
      _featuredOwner != null &&
      video != null &&
      part != null &&
      part.interactiveEdgeId == null &&
      _isFeaturedCurrent((video.summary.id, part.cid));

  bool _usableFeaturedVisit(_FeaturedVisit? visit, Object profile) {
    if (visit == null ||
        visit.profile != profile ||
        visit.checkpoint.scope != accountScope() ||
        visit.checkpoint.epoch != sessionEpoch()) {
      return false;
    }
    final limit =
        DateTime.now()
            .add(const Duration(seconds: 15))
            .millisecondsSinceEpoch ~/
        1000;
    for (final track in [visit.media.video, ?visit.media.audio]) {
      if (track.urls.isEmpty) return false;
      for (final uri in track.urls) {
        final deadline = int.tryParse(uri.queryParameters['deadline'] ?? '');
        if (deadline != null && deadline <= limit) return false;
      }
    }
    return true;
  }

  void _rememberFeaturedVisit(_PlaybackCheckpoint checkpoint) {
    final playing = _featuredPlaying;
    final resolved = media;
    if (playing == null ||
        resolved == null ||
        !sourceMatchesAccount ||
        error != null) {
      return;
    }
    final (clip, profile) = playing;
    if (checkpoint.videoId != clip.$1 || checkpoint.partKey?.$1 != clip.$2) {
      return;
    }
    _featuredVisits.remove(clip);
    _featuredVisits[clip] = _FeaturedVisit(checkpoint, resolved, profile);
    if (_featuredVisits.length > featuredPlaybackHistoryLimit) {
      final oldest = _featuredVisits.keys.first;
      _featuredVisits.remove(oldest);
      if (_featuredPaused?.clip == oldest) _discardFeaturedPaused();
    }
  }

  bool _canParkFeaturedEngine(PlayerEngine player, PlaybackMedia? media) =>
      media != null &&
      !_featuredDolby(media) &&
      switch (player.currentSnapshot.phase) {
        PlaybackPhase.playing ||
        PlaybackPhase.paused ||
        PlaybackPhase.ready => true,
        _ => false,
      };

  bool _featuredDolby(PlaybackMedia media) =>
      media.audioQuality == AudioQualityPreference.dolby ||
      AudioQualityPreference.identify(
            0,
            media.audio?.codec ?? media.video.embeddedAudioCodec ?? '',
          ) ==
          AudioQualityPreference.dolby;

  void _stopDetachedOwner() {
    if (_featuredOwner != null && _featuredPlaying != null && media != null) {
      final player = engine;
      final generation = _generation;
      // The old card's intent is already saved in its visit checkpoint.
      _featuredWaitingForPanel = true;
      _desiredPlaying = false;
      _cancelRecovery();
      unawaited(() async {
        try {
          await player.pause();
        } on Object {
          if (_activeOwner == null && generation == _generation && !_closing) {
            await stop(clearCheckpoints: false);
          }
        }
      }());
    } else {
      unawaited(stop(clearCheckpoints: false));
    }
  }

  Future<bool> _parkFeaturedEngine(
    PlayerEngine player,
    bool Function() isCurrent,
  ) async {
    try {
      await player.pause();
      if (!isCurrent()) return false;
      await player.setVolume(0);
      return isCurrent();
    } on Object {
      if (isCurrent()) await player.stop();
      return false;
    }
  }

  void _discardFeaturedPaused() {
    final paused = _featuredPaused;
    _featuredPaused = null;
    if (paused != null) {
      paused.preview.release();
      _retireFeaturedEngine(paused.engine, [paused.failures]);
    }
  }

  void _discardFeaturedClaimed() {
    if (_featuredClaimed case final claimed?) {
      _featuredClaimed = null;
      _retireFeaturedEngine(claimed.engine);
      scheduleMicrotask(_notify);
    }
  }

  Future<PlayerEngine?> _takeFeaturedPaused(
    (VideoId, String) clip,
    OpenOptions options,
    bool keepPreviewPlaying,
  ) async {
    final paused = _featuredPaused;
    if (paused == null || paused.clip != clip) return null;
    final snapshot = paused.engine.currentSnapshot;
    if (!switch (snapshot.phase) {
          PlaybackPhase.paused ||
          PlaybackPhase.ready ||
          PlaybackPhase.playing ||
          PlaybackPhase.buffering => true,
          _ => false,
        } ||
        snapshot.volume != 0 ||
        snapshot.rate != options.rate ||
        (paused.preview.startPosition - options.startPosition).abs() >
            const Duration(milliseconds: 250)) {
      _discardFeaturedPaused();
      return null;
    }
    if (!await paused.preview.handoff(keepPlaying: keepPreviewPlaying) ||
        !identical(_featuredPaused, paused)) {
      return null;
    }
    _featuredPaused = null;
    unawaited(paused.failures.cancel());
    return paused.engine;
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
    final preview = _featuredSwipePreview;
    // Don't replace the incoming decoder before the selected card takes it.
    final neighbor = preview != null && !_isFeaturedCurrent(preview)
        ? preview
        : _featuredNeighbor;
    if (neighbor == null || _listeningMode.enabled || neighbor == selected) {
      unawaited(standby.clear(owner: this));
      return;
    }
    final (id, cid) = neighbor;
    final scope = accountScope();
    final settings = _settings;
    final epoch = sessionEpoch();
    final visit = _featuredVisits[neighbor];
    final cached = _usableFeaturedVisit(visit, _featuredProfile)
        ? visit?.media
        : null;
    if (_featuredPaused?.clip == neighbor && cached != null) {
      return;
    }
    final checkpoint =
        visit?.checkpoint ?? _navigationCheckpoints[(id, (cid, null), null)];
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
      void check() {
        if (cancel.isCancelled) {
          throw const AppFailure(AppFailureKind.cancelled, '预加载已取消');
        }
      }

      check();
      final (media, position) = await (
        cached == null
            ? resolve(
                id,
                cid,
                quality: restored?.quality ?? settings.preferredQuality,
                preferredCodec: settings.preferredVideoCodec,
                cancellation: cancel,
              )
            : Future.value(cached),
        restored != null
            ? Future<Duration?>.value(restored.position)
            : settings.resumePlayback
            ? progress.read(scope, id, cid)
            : Future<Duration?>.value(),
      ).wait;
      check();
      final audioQuality = restored?.audioQuality;
      final resolved = audioQuality == null
          ? media
          : media.selectAudioQuality(audioQuality);
      // A passthrough/system Dolby route can reserve the hardware audio
      // device even while paused. Open it only when this card owns playback.
      if (_featuredDolby(resolved)) {
        throw const AppFailure(AppFailureKind.playback, '杜比音频在切换后打开');
      }
      if (_retiringEngine case final retired?) await retired;
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
    _syncFeaturedSwipePreview();
  }

  Future<bool> _useFeaturedEngine(
    VideoId id,
    String cid,
    ResolvedMediaSource source,
    OpenOptions options,
    RequestCancellation cancellation,
    bool Function() isCurrent, {
    required Duration Function() remainingBudget,
    required (VideoId, String)? park,
    required bool useVisited,
  }) async {
    if (_featuredOwner == null || !_playbackAllowed) return false;
    final keepPreviewPlaying = _desiredPlaying && !sleepTimer.elapsed;
    final paused = _featuredPaused;
    var ready = useVisited && paused?.clip == (id, cid)
        ? await _takeFeaturedPaused(
            (id, cid),
            options,
            keepPreviewPlaying,
          ).timeout(
            remainingBudget(),
            onTimeout: () {
              if (identical(_featuredPaused, paused)) _discardFeaturedPaused();
              return null;
            },
          )
        : null;
    final fromParked = ready != null;
    final pending = fromParked
        ? null
        : featuredStandby?.take(
            (accountScope(), sessionEpoch(), id, cid),
            source,
            options,
            cancellation,
            owner: this,
            keepPreviewPlaying: keepPreviewPlaying,
          );
    ready ??= await pending;
    if (ready == null) return false;
    final incoming = ready;
    if (!isCurrent() || !_playbackAllowed || _featuredOwner == null) {
      _retireFeaturedEngine(incoming);
      return false;
    }
    if (fromParked) {
      // The committed reverse swipe uses the parked decoder. Retire the
      // former direction's candidate only once that choice is confirmed.
      unawaited(featuredStandby?.clear(owner: this));
    }
    _featuredClaimed = (clip: (id, cid), engine: incoming);
    void discard() {
      if (identical(_featuredClaimed?.engine, incoming)) {
        _discardFeaturedClaimed();
      }
    }

    cancellation.onCancel(discard);
    bool ownsClaim() =>
        isCurrent() &&
        _playbackAllowed &&
        _featuredOwner != null &&
        identical(_featuredClaimed?.engine, incoming);
    bool wantsPlayback() => _desiredPlaying && !sleepTimer.elapsed;
    try {
      if (incoming case final PlaybackPresentationControl presentation) {
        // Offscreen preparation verifies decoding without waiting for Flutter
        // to consume the texture. The claimed slot stays mounted during this
        // handoff, so the final frame check applies even to a paused card.
        final budget = remainingBudget();
        final limit = featuredStandby!.handoffTimeout;
        final timeout = budget < limit ? budget : limit;
        await presentation
            .confirmPreparedPresentation(timeout)
            .timeout(timeout);
      }
      if (!ownsClaim()) {
        discard();
        return false;
      }
      if (incoming.currentSnapshot.desiredPlaying) {
        final canPlay =
            wantsPlayback() &&
            (audioFocus == null ||
                await _requestAudioFocus(_generation)
                    .timeout(remainingBudget()));
        if (ownsClaim() && (!canPlay || !wantsPlayback())) {
          await incoming.pause().timeout(remainingBudget());
        }
      }
    } on Object {
      discard();
      return false;
    }
    if (!ownsClaim() ||
        incoming.currentSnapshot.phase == PlaybackPhase.failed) {
      discard();
      return false;
    }
    _featuredClaimed = null;
    _markFeaturedPresentation((id, cid), incoming);
    _replaceFeaturedEngine(incoming, park);
    try {
      final budget = remainingBudget();
      const volumeTimeout = Duration(seconds: 2);
      await incoming
          .setVolume(_featuredOpeningVolume)
          .timeout(budget < volumeTimeout ? budget : volumeTimeout);
    } on Object {
      // The normal foreground open will reset this engine's source and volume.
      return false;
    }
    return true;
  }

  double get _featuredOpeningVolume =>
      (_volumeTargetGeneration == _generation ? _volumeTarget : null) ??
      (_tabMuted ? 0 : _openingVolume);

  Future<void> _openWithFeaturedEngine(
    PlayerEngine previous,
    (VideoId, String) clip,
    bool Function() isCurrent,
    Duration Function() remainingBudget,
  ) async {
    final standby = featuredStandby;
    if (standby != null && _playbackAllowed) {
      _discardFeaturedPaused();
      try {
        await _retiringEngine?.timeout(remainingBudget());
        if (!isCurrent()) return;
        _replaceFeaturedEngine(standby.createEngine(), clip);
        return;
      } on Object {
        // Reuse the current engine when a second decoder cannot be allocated.
      }
    }
    if (isCurrent()) await previous.stop();
  }

  void _replaceFeaturedEngine(PlayerEngine ready, (VideoId, String)? park) {
    final old = engine;
    final subscriptions = _subscriptions.toList();
    _subscriptions.clear();
    _engine = ready;
    _listenToEngine(ready);
    _onSnapshot(ready.currentSnapshot);
    if (park == null || !_playbackAllowed) {
      _retireFeaturedEngine(old, subscriptions);
    } else {
      _discardFeaturedPaused();
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      _featuredPaused = _FeaturedPausedEngine(
        park,
        FeaturedMutedPreview(
          old,
          startPosition: old.currentSnapshot.position,
          onFailure: () {
            if (identical(_featuredPaused?.engine, old)) {
              _discardFeaturedPaused();
              _notify();
            }
          },
        ),
        old.failures.listen((_) {
          if (identical(_featuredPaused?.engine, old)) {
            _discardFeaturedPaused();
            _notify();
          }
        }),
      );
    }
    _syncFeaturedSwipePreview();
    _notify();
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

    final retiring = _retiringEngine = Future.wait<void>([
      ?_retiringEngine,
      release(),
    ]).then((_) {});
    // Keep a failed retirement for close() to report; further preparations
    // wait on it and fall back without allocating another native player.
    retiring.then((_) {
      if (identical(_retiringEngine, retiring)) _retiringEngine = null;
    }).ignore();
  }
}

final class _FeaturedVisit {
  const _FeaturedVisit(this.checkpoint, this.media, this.profile);
  final _PlaybackCheckpoint checkpoint;
  final PlaybackMedia media;
  final Object profile;
}

final class _FeaturedPausedEngine {
  const _FeaturedPausedEngine(this.clip, this.preview, this.failures);
  final (VideoId, String) clip;
  final FeaturedMutedPreview preview;
  PlayerEngine get engine => preview.engine;
  final StreamSubscription<PlayerFailure> failures;
}
