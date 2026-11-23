/// Opt-in playback enhancements ported from BBZQ's quality pipeline.
///
/// The policy is injected by the caller; no setting or account entitlement is
/// inferred here. All switches are off by default.
final class PlaybackEnhancementPolicy {
  const PlaybackEnhancementPolicy({
    this.unlockHighestBitrate = false,
    this.unlimitedQualityTrial = false,
    this.trialUiSync = false,
  });

  static const disabled = PlaybackEnhancementPolicy();

  /// Requests the 8K ceiling and uses BBZQ's explicit quality preference order.
  final bool unlockHighestBitrate;

  /// Asks the server for a quality trial on ordinary video playurl requests.
  final bool unlimitedQualityTrial;

  /// Keeps quality choices mapped to streams actually returned by the server.
  final bool trialUiSync;

  static const highestBitrateQualityOrder = <int>[
    127,
    126,
    125,
    120,
    112,
    116,
    80,
    74,
    64,
    32,
    16,
  ];

  TrialUiSyncReport get uiSyncReport => TrialUiSyncReport(
    enabled: trialUiSync,
    trialRequestsEnabled: unlimitedQualityTrial,
  );
}

/// Describes the only UI synchronization available outside the official host.
///
/// BiliSail already builds PlaybackMedia.qualities from returned DASH tracks.
/// It has no official needVip, vipFree, or trial-marker host fields to hook,
/// so enabling UI sync never claims membership or manufactures those fields.
final class TrialUiSyncReport {
  const TrialUiSyncReport({
    required this.enabled,
    required this.trialRequestsEnabled,
  });

  final bool enabled;
  final bool trialRequestsEnabled;

  bool get qualityOptionsFollowReturnedDashTracks => true;
  bool get rewritesOfficialHostFields => false;
  bool get grantsMembership => false;

  String get behavior {
    if (!enabled) {
      return 'Host-specific trial UI synchronization is disabled. Quality '
          'options still follow server-returned DASH tracks; official host '
          'VIP/trial fields are not rewritten.';
    }
    final trial = trialRequestsEnabled
        ? 'Trial requests are enabled.'
        : 'Trial requests remain disabled.';
    return '$trial Quality options follow server-returned DASH tracks; '
        'official host VIP/trial fields are not rewritten.';
  }
}
