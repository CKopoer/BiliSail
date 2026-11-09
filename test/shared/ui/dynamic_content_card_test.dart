import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/shared/ui/dynamic_content_card.dart';
import 'package:bilisail/shared/ui/dynamic_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [280.0, 375.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('topic, goods and all card types fit $width at $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final opened = <Uri>[];
        final destination = Uri.parse('https://mall.bilibili.com/item/1');
        final post = DynamicPost(
          id: '1',
          authorName: '作者',
          text: '动态正文',
          topic: DynamicTopic(
            name: '一个很长的话题名称也可以自动换行显示',
            url: Uri.https('www.bilibili.com', '/v/topic/detail', {
              'topic_id': '12',
            }),
          ),
          contentCards: [
            for (final kind in DynamicCardKind.values)
              DynamicContentCard(
                kind: kind,
                title: '卡片名称 $kind',
                description: '¥19.90 或其他附加描述',
                detail: '附加信息',
                url: destination,
                actionLabel: '去看看',
                actionUrl: destination,
              ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DynamicPostCard(post: post, onOpenLink: opened.add),
              ),
            ),
          ),
        );
        expect(
          find.byType(DynamicContentCardView),
          findsNWidgets(DynamicCardKind.values.length),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('一个很长的话题名称也可以自动换行显示'));
        expect(opened.single.queryParameters['topic_id'], '12');
        final goods = find.byWidgetPredicate(
          (widget) =>
              widget is DynamicContentCardView &&
              widget.card.kind == DynamicCardKind.goods,
        );
        final button = find.descendant(
          of: goods,
          matching: find.byType(OutlinedButton),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        expect(opened.last, destination);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'measurement keeps exact geometry for topics, covers and attached cards',
    (tester) async {
      final post = DynamicPost(
        id: 'measured',
        text: '动态正文',
        topic: const DynamicTopic(name: '话题'),
        contentCards: [
          DynamicContentCard(
            kind: DynamicCardKind.pgc,
            title: '影视',
            coverUrl: Uri.https('example.test', '/cover'),
          ),
          const DynamicContentCard(
            kind: DynamicCardKind.goods,
            title: '商品',
            actionLabel: '查看商品',
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(900, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DynamicPostCard(post: post, onOpenLink: (_) {}),
                ),
                Expanded(
                  child: DynamicPostCard.forLayout(
                    post: post,
                    onOpenLink: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(DynamicPostCard).first),
        tester.getSize(find.byType(DynamicPostCard).last),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forwarded goods have independent targets and malformed links stay disabled',
    (tester) async {
      final opened = <Uri>[];
      final destination = Uri.https('mall.bilibili.com', '/item/1');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DynamicPostCard(
                post: DynamicPost(
                  id: '1',
                  original: DynamicPost(
                    id: '2',
                    contentCards: [
                      DynamicContentCard(
                        kind: DynamicCardKind.goods,
                        title: '原动态商品',
                        url: destination,
                        actionLabel: '去购买',
                        actionUrl: destination,
                      ),
                      const DynamicContentCard(
                        kind: DynamicCardKind.goods,
                        title: '没有跳转地址',
                        actionLabel: '不可点击',
                      ),
                    ],
                  ),
                ),
                onOpenLink: opened.add,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('原动态商品'));
      expect(opened, [destination]);
      final disabled = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '不可点击'),
      );
      expect(disabled.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
