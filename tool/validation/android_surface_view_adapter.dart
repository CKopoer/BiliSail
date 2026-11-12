import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A measurement prototype: open and seek on the validated texture path first,
/// then pause and transfer only the decoder output to an HC platform view.
final class AndroidSurfaceViewBenchmark implements VideoCompositionAdapter {
  AndroidSurfaceViewBenchmark({required this.engine});
  final PlayerEngine engine;
  final enabled = ValueNotifier(false);
  final ready = Completer<void>();
  static const channel = MethodChannel('dev.bilisail/surface_benchmark');

  Future<void> transfer() async {
    await engine.pause();
    enabled.value = true;
    await ready.future.timeout(const Duration(seconds: 20));
    await engine.seek(engine.currentSnapshot.position);
    await engine.play();
  }

  @override
  Widget buildVideoSurface(BuildContext context, VideoOutput output) =>
      ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (_, active, _) => active
            ? Center(
                child: AspectRatio(
                  aspectRatio:
                      (engine.currentSnapshot.videoDimensions?.width ?? 16) /
                      (engine.currentSnapshot.videoDimensions?.height ?? 9),
                  child: PlatformViewLink(
                    viewType: 'dev.bilisail/surface_benchmark',
                    surfaceFactory: (_, controller) => AndroidViewSurface(
                      controller: controller as AndroidViewController,
                      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                      gestureRecognizers:
                          const <Factory<OneSequenceGestureRecognizer>>{},
                    ),
                    onCreatePlatformView: (params) {
                      final controller =
                          PlatformViewsService.initExpensiveAndroidView(
                            id: params.id,
                            viewType: 'dev.bilisail/surface_benchmark',
                            layoutDirection: TextDirection.ltr,
                            creationParamsCodec: const StandardMessageCodec(),
                          );
                      controller.addOnPlatformViewCreatedListener(
                        params.onPlatformViewCreated,
                      );
                      controller.addOnPlatformViewCreatedListener((id) async {
                        try {
                          final surface = await channel.invokeMethod<int>(
                            'surface',
                            {'id': id},
                          );
                          if (surface == null || surface <= 0) {
                            throw StateError('Native Surface unavailable');
                          }
                          await (engine as MediaKitEngine)
                              .replaceAndroidSurfaceForBenchmark(surface);
                          if (!ready.isCompleted) ready.complete();
                        } catch (error, stack) {
                          if (!ready.isCompleted) {
                            ready.completeError(error, stack);
                          }
                        }
                      });
                      unawaited(controller.create());
                      return controller;
                    },
                  ),
                ),
              )
            : const FlutterVideoCompositionAdapter().buildVideoSurface(
                context,
                output,
              ),
      );

  @override
  Widget compose(BuildContext context, {required List<Widget> layers}) =>
      const FlutterVideoCompositionAdapter().compose(context, layers: layers);

  void dispose() => enabled.dispose();
}
