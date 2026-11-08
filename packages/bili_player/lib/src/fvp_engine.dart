import 'dart:io';

import 'fvp_backend.dart';
import 'fvp_native_player.dart';
import 'player_diagnostics.dart';
import 'shared_player_engine.dart';

/// Fixed MDK entrypoint, including the Android isolated-process port.
final class FvpEngine extends SharedPlayerEngine {
  factory FvpEngine({
    void Function(PlayerDiagnosticEvent)? onDiagnostic,
    int? windowsAdapterIndex,
    Future<FvpPlayerPort> Function()? createPlayer,
  }) {
    late final FvpEngine engine;
    NativeReadinessStage? readinessStage;
    engine = FvpEngine._(
      seekCoalescingDelay: createPlayer == null
          ? const Duration(milliseconds: 40)
          : Duration.zero,
      onDiagnostic: (event) {
        if (event.kind == PlayerDiagnosticKind.openStarted ||
            event.kind == PlayerDiagnosticKind.openReady) {
          readinessStage = null;
        }
        onDiagnostic?.call(
          PlayerDiagnosticEvent(
            kind: event.kind,
            snapshot: event.snapshot,
            readinessStage: readinessStage,
            failureKind: event.failureKind,
            nativeError: event.nativeError,
            nativeErrorCode:
                event.nativeErrorCode ??
                (engine.activeBackend as FvpBackend?)?.processExitStatus,
            stallReason: event.stallReason,
            stalledFor: event.stalledFor,
            audioPosition: event.audioPosition,
          ),
        );
      },
      createBackend: () => FvpBackend(
        createPlayer:
            createPlayer ??
            (() => createFvpNativePlayer(
              windowsAdapterIndex: windowsAdapterIndex,
            )),
        isolated: createPlayer == null && Platform.isAndroid,
        onStage: (stage) {
          readinessStage = stage;
          onDiagnostic?.call(
            PlayerDiagnosticEvent(
              kind: PlayerDiagnosticKind.openStageChanged,
              snapshot: engine.currentSnapshot,
              readinessStage: stage,
            ),
          );
        },
      ),
    );
    return engine;
  }
  FvpEngine._({
    required super.createBackend,
    super.onDiagnostic,
    required super.seekCoalescingDelay,
  }) : super(
         schemes: {'http', 'https', 'file', if (Platform.isAndroid) 'content'},
       );

  // Preserve the historical direct-constructor normalization. The configurable
  // application entrypoint normalizes before selecting either backend.
  @override
  Future<void> seek(Duration target) =>
      super.seek(target < Duration.zero ? Duration.zero : target);
}
