import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  int checks = 0;
  @override
  void addPostFrameCallback(
    FrameCallback callback, {
    String debugLabel = 'callback',
  }) {
    if (debugLabel == 'PagedScrollViewport.pagination') checks++;
    super.addPostFrameCallback(callback, debugLabel: debugLabel);
  }
}

void main() {
  final binding = _Binding();
  testWidgets('pagination schedules only eligible scrolls near the end', (
    tester,
  ) async {
    late ScrollController controller;
    var requests = 0;
    Future<void> mount({bool active = true, bool canLoadMore = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedScrollViewport(
              active: active,
              canLoadMore: canLoadMore,
              contentVersion: 1,
              onLoadMore: () async => requests++,
              builder: (value) {
                controller = value;
                return ListView.builder(
                  controller: value,
                  itemExtent: 100,
                  itemCount: 100,
                  itemBuilder: (_, index) => Text('Card $index'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      binding.checks = 0;
    }

    Future<void> scroll(double offset) async {
      controller.jumpTo(offset);
      await tester.pumpAndSettle();
    }

    await mount();
    for (var i = 1; i <= 20; i++) {
      await scroll(i * 10);
    }
    expect(binding.checks, 0);
    expect(requests, 0);
    await scroll(controller.position.maxScrollExtent - 500);
    expect(binding.checks, 1);
    expect(requests, 1);
    await mount(canLoadMore: false);
    await scroll(controller.offset + 10);
    expect(binding.checks, 0);
    expect(requests, 1);
    await mount(active: false);
    await scroll(controller.offset + 10);
    expect(binding.checks, 0);
    expect(requests, 1);
    await mount();
    expect(requests, 2, reason: 'activation still checks a short remainder');
    expect(tester.takeException(), isNull);
  });
}
