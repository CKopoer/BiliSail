import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/android_fvp_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
import 'package:flutter_test/flutter_test.dart';

class _Port extends Fake implements FvpPlayerPort {
  final events = StreamController<FvpNativeStatus>.broadcast(sync: true);
  Completer<FvpMediaInfo>? opening;
  Completer<int>? seeking;
  bool disposed = false;
  @override
  Stream<FvpNativeStatus> get statuses => events.stream;
  @override
  int get positionMilliseconds => 100;
  @override
  int get bufferedMilliseconds => 1000;
  @override
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    bool isLive = false,
  }) async =>
      await opening?.future ??
      const FvpMediaInfo(
        duration: Duration(seconds: 5),
        dimensions: VideoDimensions(320, 180),
        hasAudio: true,
      );
  @override
  Future<int> createTexture() async => 1;
  @override
  Future<bool> confirmVideoFrame() async => true;
  @override
  Future<bool> confirmAudio() async => true;
  @override
  void play() {}
  @override
  void pause() {}
  @override
  Future<void> pauseAndWait() async {}
  @override
  void setVolume(double volume, double gainDb) {}
  @override
  void setRate(double rate) {}
  @override
  void interrupt() {}
  @override
  Future<int> seek(Duration target) async =>
      await seeking?.future ?? target.inMilliseconds;
  @override
  Future<void> cancelSeek() async {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = ProgressiveSource(
    MediaTrack(
      uri: Uri.parse('https://example.com/video?secret=private'),
      requestPolicy: MediaRequestPolicy(),
    ),
  );
  test(
    'worker death during open is logged and terminal, then a new open works',
    () async {
      final first = _Port()..opening = Completer<FvpMediaInfo>();
      final next = _Port();
      var port = first;
      final logs = <PlayerDiagnosticEvent>[];
      final engine = FvpEngine(
        createPlayer: () async => port,
        onDiagnostic: logs.add,
      );
      addTearDown(engine.dispose);
      final failures = <PlayerFailure>[];
      final subscription = engine.failures.listen(failures.add);
      addTearDown(subscription.cancel);
      final opening = engine.open(source, const OpenOptions());
      final checked = expectLater(
        opening,
        throwsA(
          isA<PlayerFailure>().having(
            (e) => e.kind,
            'kind',
            PlayerFailureKind.nativeProcessExited,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      first.events.add(FvpNativeStatus.processExited);
      first.opening!.completeError(const FvpProcessException());
      await checked;
      expect(first.disposed, true);
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      expect(engine.currentSnapshot.desiredPlaying, false);
      expect(failures.single.kind, PlayerFailureKind.nativeProcessExited);
      expect(
        logs.where((e) => e.kind == PlayerDiagnosticKind.nativeProcessExited),
        hasLength(1),
      );
      expect(
        logs.map((e) => e.toJson()).toString(),
        isNot(contains('private')),
      );
      expect(
        logs
            .where((e) => e.kind == PlayerDiagnosticKind.nativeProcessExited)
            .single
            .readinessStage,
        NativeReadinessStage.tracks,
      );
      port = next;
      await engine.open(source, const OpenOptions());
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    },
  );

  test(
    'worker death during playback stops sampling and leaves disposal safe',
    () async {
      final port = _Port();
      final engine = FvpEngine(createPlayer: () async => port);
      await engine.open(source, const OpenOptions(play: true));
      port.events.add(FvpNativeStatus.processExited);
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      expect(engine.currentSnapshot.desiredPlaying, false);
      await engine.dispose();
      expect(port.disposed, true);
    },
  );

  test('worker death during seek cannot resume the failed source', () async {
    final port = _Port();
    final engine = FvpEngine(createPlayer: () async => port);
    await engine.open(source, const OpenOptions(play: true));
    port.seeking = Completer<int>();
    final seek = engine.seek(const Duration(seconds: 2));
    final failed = expectLater(
      seek,
      throwsA(
        isA<PlayerFailure>().having(
          (e) => e.kind,
          'kind',
          PlayerFailureKind.nativeProcessExited,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    port.events.add(FvpNativeStatus.processExited);
    port.seeking!.completeError(const FvpProcessException());
    await failed;
    expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
    expect(engine.currentSnapshot.desiredPlaying, false);
    await engine.dispose();
  });
}
