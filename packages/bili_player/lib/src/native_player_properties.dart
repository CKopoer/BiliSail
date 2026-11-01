import 'package:media_kit/media_kit.dart' as mk;

/// Keep the engine's async port while using PiliPlus's synchronous properties.
extension NativePlayerProperties on mk.NativePlayer {
  Future<void> setPropertyAsync(String name, String value) async {
    setProperty(name, value);
  }

  Future<String> getPropertyAsync(String name) async => getProperty(name);

  /// The pinned core allocates one byte for MPV_FORMAT_FLAG, which requires a
  /// C int. Use its public playlist and string APIs to avoid that unsafe path.
  Future<void> openPausedMedia(mk.Media media) async {
    current.clear();
    await stop(open: true);
    setProperty('pause', 'yes');
    await add(media);
    await command(const ['playlist-play-index', '0']);
  }

  Future<void> playWithStringFlag() async {
    throwIfDisposed();
    // Let the core publish its own property confirmation. Its stream
    // controllers are protected; the engine already owns the user's intent.
    isPlayingStateChangeAllowed = true;
    if (state.completed) {
      await seek(Duration.zero);
      await command(const ['playlist-play-index', '0']);
    }
    setProperty('pause', 'no');
  }

  Future<void> pauseWithStringFlag() async {
    throwIfDisposed();
    isPlayingStateChangeAllowed = true;
    isBufferingStateChangeAllowed = false;
    setProperty('pause', 'yes');
  }
}
