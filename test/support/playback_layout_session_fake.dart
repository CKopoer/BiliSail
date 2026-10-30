import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:flutter/foundation.dart';

/// Layout tests need only mode notifications, without constructing an engine.
class PlaybackLayoutSessionFake extends ChangeNotifier
    implements PlaybackSession {
  @override
  bool audioOnly = false;

  @override
  Future<void> setAudioOnly(bool enabled) async {
    audioOnly = enabled;
    notifyListeners();
  }

  void publishMetadata() => notifyListeners();

  bool get hasLayoutListeners => hasListeners;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused layout fixture member: ${invocation.memberName}',
  );
}
