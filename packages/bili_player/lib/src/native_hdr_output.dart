import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'native_player_properties.dart';
import 'player_contract.dart';

const _channel = MethodChannel('bilisail/hdr_video');

bool get usesAppleMetalOutput => Platform.isIOS || Platform.isMacOS;

bool hasCompatibleHdrBase({
  required String profile,
  required String matrix,
  required String primaries,
  required String transfer,
}) =>
    profile == '8' &&
    (matrix == 'bt.2020-ncl' || matrix == 'bt.2020-cl') &&
    primaries == 'bt.2020' &&
    (transfer == 'pq' || transfer == 'hlg');

bool isNativeHdrSource({
  required String profile,
  required String transfer,
  required String matrix,
  required bool hdrHint,
}) =>
    profile == '5' ||
    profile == '8' ||
    matrix == 'dolbyvision' ||
    transfer == 'pq' ||
    transfer == 'hlg' ||
    (hdrHint &&
        (transfer.isEmpty || transfer == 'auto' || transfer == 'unknown'));

/// The target owns the display surface. The same mpv clock and audio track
/// continue running when the surface moves between inline and fullscreen.
final class NativeHdrOutput {
  NativeHdrOutput._(
    this.id,
    this.viewId,
    this.dimensions,
    this.transfer,
    this._original,
  );

  final int id;
  final int viewId;
  final VideoDimensions dimensions;
  final String transfer;
  final Map<String, String> _original;

  static Future<String?> supportedTransfer(int viewId) async {
    try {
      return await _channel
          .invokeMethod<String>('supported', {'view': viewId})
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<NativeHdrOutput?> tryOpen(
    mk.Player player,
    VideoDimensions size,
    int viewId,
    String transfer, {
    required bool dolby,
    required String profile,
  }) async {
    int? id;
    try {
      final creating = _channel.invokeMethod<int>('create', {
        'width': size.width,
        'height': size.height,
        'view': viewId,
        'transfer': transfer,
      });
      id = await creating.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          unawaited(
            creating
                .then<void>((lateId) async {
                  if (lateId != null) {
                    await _channel.invokeMethod<void>('release', lateId);
                  }
                })
                .catchError((Object _) {}),
          );
          return null;
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    if (id == null || id == 0) return null;
    final original = <String, String>{};
    final target = NativeHdrOutput._(id, viewId, size, transfer, original);
    void set(String key, String value) {
      final previous = original[key] ?? player.getProperty(key);
      player.setProperty(key, value);
      original[key] = previous;
    }

    try {
      set('vo', 'null');
      if (dolby && player.getProperty('vf').contains('@bilisail_dovi:')) {
        // A legacy SDR render context may have installed our labeled filter.
        // Remove only that filter so the HDR renderer receives the original frames.
        original['vf'] = player.getProperty('vf');
        await player.native.command(['vf', 'remove', '@bilisail_dovi']);
      }
      if (Platform.isAndroid || usesAppleMetalOutput) {
        set('wid', id.toString());
        // Android opaque hardware frames can lose the Dolby RPU. Preserve it
        // for both Profile 5 reshaping and Profile 8 dynamic metadata.
        if (dolby) set('hwdec', 'no');
        if (Platform.isAndroid) {
          set('android-surface-size', '${size.width}x${size.height}');
        }
      } else {
        set('d3d11-output-mode', 'composition');
        set('d3d11-output-format', 'rgb10_a2');
        set('d3d11-composition-size', '${size.width}x${size.height}');
      }
      set('gpu-api', Platform.isWindows ? 'd3d11' : 'vulkan');
      set(
        'gpu-context',
        usesAppleMetalOutput
            ? 'moltenvk'
            : Platform.isAndroid
            ? 'androidvk'
            : 'd3d11',
      );
      set('target-prim', transfer == 'srgb' ? 'bt.709' : 'bt.2020');
      set('target-trc', transfer);
      set('target-colorspace-hint', 'yes');
      set('vo', 'gpu-next');
      // A requested PQ target alone does not prove that the presentation
      // surface negotiated PQ. Inspect the actual output before revealing it.
      for (var i = 0; i < 80; i++) {
        final matrix = player.getProperty('video-out-params/colormatrix');
        final inputTransfer = player.getProperty('video-out-params/gamma');
        // Prefer the full RPU even for Profile 8. After giving software decode
        // time to supply it, accept an explicitly signaled PQ or HLG base.
        final usableColor =
            (!dolby && (inputTransfer == 'pq' || inputTransfer == 'hlg')) ||
            matrix == 'dolbyvision' ||
            (i >= 60 &&
                hasCompatibleHdrBase(
                  profile: profile,
                  matrix: matrix,
                  primaries: player.getProperty('video-out-params/primaries'),
                  transfer: inputTransfer,
                ));
        if (player.getProperty('current-vo') == 'gpu-next' &&
            player.getProperty('video-target-params/gamma') == transfer &&
            usableColor) {
          if (Platform.isWindows) {
            if (await _channel.invokeMethod<bool>('bind', {
                  'id': id,
                  'player': player.nativeHandle,
                }) !=
                true) {
              break;
            }
          }
          if (usesAppleMetalOutput &&
              await _channel.invokeMethod<bool>('matches', {
                    'id': id,
                    'transfer': transfer,
                  }) !=
                  true) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            continue;
          }
          return target;
        }
        // Some Android MediaCodec/Vulkan combinations cannot import HDR frames.
        // Retain hardware decode whenever it supplies usable HDR color.
        if (i == 30 && !usableColor && player.getProperty('hwdec') != 'no') {
          set('hwdec', 'no');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      throw StateError('HDR swapchain unavailable');
    } on Object catch (error) {
      debugPrint('HDR output unavailable: $error');
      await target.restore(player);
      return null;
    }
  }

  Future<void> restore(mk.Player player) async {
    try {
      if (!_original.containsKey('vo')) return;
      player.setProperty('vo', 'null');
      try {
        for (final entry in _original.entries.toList().reversed) {
          if (entry.key == 'vo') continue;
          try {
            player.setProperty(entry.key, entry.value);
          } on StateError {
            // A removed device can invalidate one backend-specific option.
            // Restore the remaining settings and the original VO independently.
            debugPrint('Could not restore mpv option ${entry.key}');
          }
        }
      } finally {
        if (_original['vo'] case final vo?) player.setProperty('vo', vo);
      }
    } finally {
      await release();
    }
  }

  Future<void> release() => _channel.invokeMethod<void>('release', id);

  Widget build() => Center(
    child: AspectRatio(
      aspectRatio: dimensions.width / dimensions.height,
      child: switch (defaultTargetPlatform) {
        TargetPlatform.android => buildAndroidDecoderSurface(id),
        TargetPlatform.iOS => UiKitView(
          key: ValueKey(id),
          viewType: 'bilisail/hdr_video',
          creationParams: id,
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        TargetPlatform.macOS => AppKitView(
          key: ValueKey(id),
          viewType: 'bilisail/hdr_video',
          creationParams: id,
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        _ => _WindowsHdrSurface(key: ValueKey(id), target: id),
      },
    ),
  );
}

Widget buildAndroidDecoderSurface(int id) => PlatformViewLink(
  key: ValueKey(id),
  viewType: 'bilisail/hdr_video',
  surfaceFactory: (_, controller) => AndroidViewSurface(
    controller: controller as AndroidViewController,
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
  ),
  onCreatePlatformView: (params) {
    final controller = PlatformViewsService.initExpensiveAndroidView(
      id: params.id,
      viewType: 'bilisail/hdr_video',
      layoutDirection: TextDirection.ltr,
      creationParams: id,
      creationParamsCodec: const StandardMessageCodec(),
    )..addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
    unawaited(controller.create());
    return controller;
  },
);

final class _WindowsHdrSurface extends LeafRenderObjectWidget {
  const _WindowsHdrSurface({super.key, required this.target});
  final int target;
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _WindowsHdrBox(target, View.of(context).devicePixelRatio);
  @override
  void updateRenderObject(BuildContext context, _WindowsHdrBox renderObject) {
    renderObject.dpr = View.of(context).devicePixelRatio;
    renderObject.markNeedsPaint();
  }
}

final class _WindowsHdrBox extends RenderBox {
  _WindowsHdrBox(this.target, this.dpr);
  static int _nextOwner = 0;
  final int placementId = ++_nextOwner;
  final int target;
  double dpr;
  Rect? last;
  int revision = 0;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    final current = ++revision;
    void afterFrame(Duration _) {
      if (!attached || revision != current) return;
      if (hasSize) _place();
      // A retained layer can move during scroll or zoom without repainting
      // this box. Observe rendered frames without requesting additional ones.
      WidgetsBinding.instance.addPostFrameCallback(afterFrame);
    }

    WidgetsBinding.instance.addPostFrameCallback(afterFrame);
  }

  @override
  void performLayout() => size = constraints.biggest;
  @override
  void paint(PaintingContext context, Offset offset) {
    _place();
    context.canvas.drawRect(
      offset & size,
      Paint()..blendMode = BlendMode.clear,
    );
  }

  void _place() {
    final box = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    if (!box.isFinite || box.isEmpty) return;
    final rect = Rect.fromLTRB(
      (box.left * dpr).roundToDouble(),
      (box.top * dpr).roundToDouble(),
      (box.right * dpr).roundToDouble(),
      (box.bottom * dpr).roundToDouble(),
    );
    if (last != rect) {
      last = rect;
      unawaited(
        _channel.invokeMethod<void>('place', {
          'id': target,
          'owner': placementId,
          'x': rect.left.toInt(),
          'y': rect.top.toInt(),
          'width': rect.width.toInt(),
          'height': rect.height.toInt(),
        }),
      );
    }
  }

  @override
  void detach() {
    last = null;
    revision++;
    unawaited(
      _channel.invokeMethod<void>('hide', {'id': target, 'owner': placementId}),
    );
    super.detach();
  }
}
