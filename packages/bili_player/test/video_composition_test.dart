import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Output implements FlutterVideoOutput {
  Object? owner;
  int attaches = 0;
  int detaches = 0;
  final updates = <({double width, double height, double dpr})>[];

  @override
  void attach(Object owner) {
    this.owner = owner;
    attaches++;
  }

  @override
  void detach(Object owner) {
    if (!identical(this.owner, owner)) return;
    this.owner = null;
    detaches++;
  }

  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    if (!identical(this.owner, owner)) return;
    updates.add((
      width: logicalWidth,
      height: logicalHeight,
      dpr: devicePixelRatio,
    ));
  }

  @override
  Widget buildVideoSurface() => const ColoredBox(color: Colors.blue);
}

final class _NativeOutput implements VideoOutput {
  @override
  void attach(Object owner) {}

  @override
  void detach(Object owner) {}

  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {}
}

final class _Composition implements VideoCompositionAdapter {
  final surfaces = <VideoOutput>[];
  final compositions = <List<Widget>>[];

  @override
  Widget buildVideoSurface(BuildContext context, VideoOutput output) {
    surfaces.add(output);
    return const ColoredBox(
      key: ValueKey('custom-video-output'),
      color: Colors.green,
    );
  }

  @override
  Widget compose(BuildContext context, {required List<Widget> layers}) {
    compositions.add(layers);
    return const FlutterVideoCompositionAdapter().compose(
      context,
      layers: layers,
    );
  }
}

void main() {
  testWidgets('explicit output swaps owners without a playback engine', (
    tester,
  ) async {
    final first = _Output();
    final second = _Output();
    Widget surface(VideoOutput output) => Center(
      child: SizedBox(
        width: 320,
        height: 180,
        child: VideoSurface.output(output: output),
      ),
    );

    await tester.pumpWidget(surface(first));
    final owner = first.owner;
    expect(first.attaches, 1);
    expect(first.updates.single.width, 320);
    await tester.pumpWidget(surface(second));
    expect(first.detaches, 1);
    expect(first.owner, isNull);
    expect(second.attaches, 1);
    expect(second.owner, same(owner));
    expect(second.updates.single.height, 180);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.detaches, 1);
  });

  testWidgets('default composition preserves overlay layout and hit testing', (
    tester,
  ) async {
    final output = _Output();
    var backgroundTaps = 0;
    var foregroundTaps = 0;
    Widget scene({required bool foreground}) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: Builder(
            builder: (context) => VideoCompositionScope.of(context).compose(
              context,
              layers: [
                VideoSurface.output(output: output),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => backgroundTaps++,
                  ),
                ),
                if (foreground)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    width: 70,
                    height: 30,
                    child: Opacity(
                      opacity: 0.8,
                      child: GestureDetector(
                        key: const ValueKey('foreground-control'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => foregroundTaps++,
                        child: const ColoredBox(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(scene(foreground: true));
    expect(tester.getSize(find.byType(VideoSurface)), const Size(320, 180));
    await tester.tap(find.byKey(const ValueKey('foreground-control')));
    expect(foregroundTaps, 1);
    expect(backgroundTaps, 0);
    await tester.pumpWidget(scene(foreground: false));
    await tester.tapAt(tester.getCenter(find.byType(VideoSurface)));
    expect(backgroundTaps, 1);
    expect(output.attaches, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(output.detaches, 1);
  });

  testWidgets('scope delegates native output and survives Navigator routes', (
    tester,
  ) async {
    final adapter = _Composition();
    final output = _NativeOutput();
    Widget scene(BuildContext context) =>
        VideoCompositionScope.of(context)
            .compose(context, layers: [VideoSurface.output(output: output)]);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => VideoCompositionScope(
          adapter: adapter,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context)
                        .push<void>(MaterialPageRoute(builder: scene)),
                child: const Text('fullscreen'),
              ),
              Expanded(child: scene(context)),
            ],
          ),
        ),
      ),
    );
    expect(adapter.surfaces, contains(same(output)));
    expect(adapter.compositions, isNotEmpty);
    await tester.tap(find.text('fullscreen'));
    await tester.pumpAndSettle();
    expect(adapter.compositions.length, greaterThanOrEqualTo(2));
    expect(find.byKey(const ValueKey('custom-video-output')), findsOneWidget);
    expect(adapter.surfaces.every((value) => identical(value, output)), isTrue);
  });

  testWidgets('unsupported output is an explicit composition error', (
    tester,
  ) async {
    await tester.pumpWidget(VideoSurface.output(output: _NativeOutput()));
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changing composition does not replace the output owner', (
    tester,
  ) async {
    final output = _Output();
    Widget surface(VideoCompositionAdapter adapter) => VideoCompositionScope(
      adapter: adapter,
      child: VideoSurface.output(output: output),
    );
    await tester.pumpWidget(surface(const FlutterVideoCompositionAdapter()));
    final owner = output.owner;
    final adapter = _Composition();
    await tester.pumpWidget(surface(adapter));
    expect(output.owner, same(owner));
    expect(output.attaches, 1);
    expect(output.detaches, 0);
    expect(adapter.surfaces, [same(output)]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(output.detaches, 1);
  });
}
