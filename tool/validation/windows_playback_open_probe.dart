import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_caption.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/shared/ui/state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Profile/AOT window latency probe; no account, API or media is needed to show
/// the same loading state as a video detail request that has not completed yet.
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  runApp(const _Probe());
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _clock = Stopwatch();
  final _controller = DesktopPlaybackWindowController();
  final _samples = <Map<String, Object>>[];
  final _frames = <Map<String, int>>[];
  final _presentations = <Map<String, Object>>[];
  final _playbackKey = GlobalKey();
  Map<String, Object> _stages = {};
  _MeasuredWindow? _window;
  bool _open = false;
  final _maximized =
      Platform.environment['BILI_WINDOW_OPEN_MAXIMIZED'] == 'true';

  void _mark(String stage) {
    _stages.putIfAbsent(stage, () => _clock.elapsedMicroseconds);
    if (stage == 'prepareEnd') _stages['preparedSize'] = _window!.viewSize;
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentation());
    });
    unawaited(_run());
  }

  void _presentation() {
    final window = _window;
    final context = _playbackKey.currentContext;
    if (!mounted || !_open || window == null || context == null) return;
    void visit(Element element) {
      if (element.widget.key == const ValueKey('playback-window-caption')) {
        final box = element.findRenderObject()! as RenderBox;
        final scene = context.findRenderObject()! as RenderBox;
        final view = View.of(element);
        _presentations.add({
          'us': _clock.elapsedMicroseconds,
          'visible': window.visible,
          'viewSize': window.viewSize,
          'dpr': view.devicePixelRatio,
          'captionSize': [box.size.width, box.size.height],
          'sceneSize': [
            scene.size.width * view.devicePixelRatio,
            scene.size.height * view.devicePixelRatio,
          ],
        });
        return;
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
  }

  void _timings(List<FrameTiming> timings) {
    if (!_open) return;
    for (final timing in timings) {
      _frames.add({
        'buildUs': timing.buildDuration.inMicroseconds,
        'rasterUs': timing.rasterDuration.inMicroseconds,
      });
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  Future<void> _until(bool Function() ready) async {
    final timeout = Stopwatch()..start();
    while (!ready()) {
      if (timeout.elapsed > const Duration(seconds: 10)) {
        throw TimeoutException('Window probe: $_stages');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      for (var sample = _maximized ? -1 : 0; sample < 8; sample++) {
        _stages = {'sample': sample};
        _frames.clear();
        _presentations.clear();
        _clock
          ..reset()
          ..start();
        _mark('request');
        setState(() => _open = true);
        await _until(() => _window?.visible == true);
        _mark('visible');
        _stages['visibleSize'] = _window!.viewSize;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        _stages['settledSize'] = _window!.viewSize;
        if (sample < 0) {
          await _window!.windowService.togglePlaybackWindowMaximized();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        } else {
          final first = _presentations.first;
          final scene = first['sceneSize']! as List<double>;
          final caption = first['captionSize']! as List<double>;
          final settled = _window!.viewSize;
          if ((scene[0] - settled[0]).abs() > 1 ||
              (scene[1] - settled[1]).abs() > 1 ||
              caption[1] != desktopCaptionHeight) {
            throw StateError(
              'First scene $scene, caption $caption differs from $settled.',
            );
          }
          _samples.add({
            ..._stages,
            'frames': _frames.toList(),
            'presentations': _presentations.toList(),
          });
        }
        setState(() => _open = false);
        await _until(() => _window?.disposed == true);
        _window = null;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await _controller.close();
      await File(
        Platform.environment['BILI_WINDOW_OPEN_OUTPUT'] ??
            'build/validation/window-open.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(_samples));
      exit(0);
    } catch (error, stack) {
      stderr.writeln('$error\n$stack');
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_open) _mark('hostBuild');
    return DesktopPlaybackWindow(
      controller: _controller,
      windowFactory: ({required title, required onCloseRequested}) {
        _mark('createStart');
        final window = DetachedPlaybackWindow.create(
          title: title,
          onCloseRequested: onCloseRequested,
        );
        _mark('createEnd');
        return _window = _MeasuredWindow(window, _mark);
      },
      onCloseRequested: () => setState(() => _open = false),
      onError: (error) => throw StateError('Window failed: $error'),
      playback: !_open
          ? null
          : WorkspacePlaybackWindow(
              key: _playbackKey,
              theme: ThemeData.dark(),
              shortcuts: ShortcutSettings.defaults(),
              onBack: () {},
              onClose: () {},
              onActivateBrowser: () {},
              child: const StateView.loading(message: '正在加载视频详情…'),
            ),
      child: const MaterialApp(
        home: Scaffold(body: Center(child: Text('Playback window probe'))),
      ),
    );
  }
}

class _MeasuredWindow extends DetachedPlaybackWindow {
  _MeasuredWindow(this.inner, this.mark) {
    inner.addListener(notifyListeners);
  }

  final DetachedPlaybackWindow inner;
  final void Function(String) mark;
  bool disposed = false;

  List<double> get viewSize {
    final view = PlatformDispatcher.instance.views.singleWhere(
      (view) => view.viewId == viewId,
    );
    return [view.physicalSize.width, view.physicalSize.height];
  }

  bool get visible =>
      _isWindowVisible(
        _windowHandle(PlatformDispatcher.instance.engineId!, viewId),
      ) !=
      0;

  @override
  int get viewId => inner.viewId;
  @override
  bool get isOpen => inner.isOpen;
  @override
  WindowService get windowService => inner.windowService;
  @override
  Future<void> prepare() async {
    mark('prepareStart');
    await inner.prepare();
    mark('prepareEnd');
  }

  @override
  Widget buildView(Widget child) {
    mark('viewBuild');
    WidgetsBinding.instance.addPostFrameCallback((_) => mark('viewFrame'));
    return inner.buildView(child);
  }

  @override
  void activate() => inner.activate();
  @override
  void setTitle(String title) => inner.setTitle(title);
  @override
  Future<void> saveGeometry() => inner.saveGeometry();
  @override
  void dispose() {
    inner.removeListener(notifyListeners);
    inner.dispose();
    disposed = true;
    super.dispose();
  }
}

@Native<Pointer<Void> Function(Int64, Int64)>(
  symbol: 'InternalFlutterWindows_WindowManager_GetTopLevelWindowHandle',
)
external Pointer<Void> _windowHandle(int engineId, int viewId);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'IsWindowVisible')
external int _isWindowVisible(Pointer<Void> window);
