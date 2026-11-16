import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/shared/ui/dynamic_post_card.dart';
import 'package:bilisail/shared/ui/sliver_dynamic_post_list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('viewport insets preserve measured post heights', (tester) async {
    final metrics = ValueNotifier(const MediaQueryData(size: Size(800, 600)));
    final controller = ScrollController();
    addTearDown(metrics.dispose);
    addTearDown(controller.dispose);
    final posts = List.generate(
      300,
      (i) => DynamicPost(
        id: '$i',
        authorName: 'Author',
        text: 'Card $i\nMultiple lines of content',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: metrics,
            builder: (_, value, child) =>
                MediaQuery(data: value, child: child!),
            child: CustomScrollView(
              controller: controller,
              slivers: [SliverDynamicPostList(posts: posts)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(12000);
    await tester.pumpAndSettle();
    final extent = controller.position.maxScrollExtent;
    var builds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is DynamicPostCard) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    metrics.value = metrics.value.copyWith(
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    await tester.pumpAndSettle();
    expect(
      builds,
      lessThan(20),
      reason: 'Do not remeasure all 300 loaded posts',
    );
    expect(controller.position.maxScrollExtent, extent);
    expect(controller.offset, 12000);
    builds = 0;
    metrics.value = metrics.value.copyWith(
      textScaler: const TextScaler.linear(1.5),
    );
    await tester.pumpAndSettle();
    expect(builds, greaterThanOrEqualTo(300));
    expect(controller.position.maxScrollExtent, greaterThan(extent));
    builds = 0;
    metrics.value = metrics.value.copyWith(boldText: true);
    await tester.pumpAndSettle();
    expect(builds, greaterThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });
}
