import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/shared/ui/dynamic_post_card.dart';
import 'package:bilisail/shared/ui/dynamic_post_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    DynamicPost post, {
    double width = 375,
    double scale = 1,
    bool detail = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DynamicPostCard(post: post, inDetail: detail),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder body() => find
      .descendant(
        of: find.byType(DynamicPostText),
        matching: find.byType(RichText),
      )
      .first;

  testWidgets(
    'short multiline content and wide paragraphs do not show a false expand action',
    (tester) async {
      await show(tester, DynamicPost(id: '1', text: '第一行\n第二行'));
      expect(find.text('展开全文'), findsNothing);
      await show(tester, DynamicPost(id: '2', text: 'A' * 350), width: 1500);
      expect(find.text('展开全文'), findsNothing);
      expect(
        tester.renderObject<RenderParagraph>(body()).didExceedMaxLines,
        isFalse,
      );
    },
  );

  testWidgets('six lines fit and seven lines actually expand and collapse', (
    tester,
  ) async {
    await show(
      tester,
      DynamicPost(id: 'six', text: List.filled(6, '一行').join('\n')),
    );
    expect(find.text('展开全文'), findsNothing);
    await show(
      tester,
      DynamicPost(id: 'seven', text: List.filled(7, '一行').join('\n')),
    );
    expect(find.text('展开全文'), findsOneWidget);
    final before = tester.getSize(body()).height;
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(tester.getSize(body()).height, greaterThan(before));
    expect(
      tester.renderObject<RenderParagraph>(body()).didExceedMaxLines,
      isFalse,
    );
    await tester.tap(find.text('收起'));
    await tester.pump();
    expect(tester.getSize(body()).height, before);
  });

  testWidgets(
    'short dense text and enlarged fonts use actual width rather than a character threshold',
    (tester) async {
      await show(
        tester,
        DynamicPost(id: 'dense', text: '字' * 200),
        width: 280,
        scale: 2,
      );
      expect(find.text('展开全文'), findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(body()).didExceedMaxLines,
        isTrue,
      );
      final before = tester.getSize(body()).height;
      await tester.tap(find.text('展开全文'));
      await tester.pump();
      expect(tester.getSize(body()).height, greaterThan(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded text preserves content past the old 12000 character cut and detail has no collapse action',
    (tester) async {
      final post = DynamicPost(id: 'long', text: '${'字' * 15000}全文结尾');
      await show(tester, post);
      await tester.tap(find.text('展开全文'));
      await tester.pump();
      expect(
        tester.widget<RichText>(body()).text.toPlainText(),
        endsWith('全文结尾'),
      );
      expect(
        tester.renderObject<RenderParagraph>(body()).didExceedMaxLines,
        isFalse,
      );
      await show(tester, post, detail: true);
      expect(find.text('展开全文'), findsNothing);
      expect(find.text('收起'), findsNothing);
      expect(
        tester.widget<RichText>(body()).text.toPlainText(),
        endsWith('全文结尾'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rich text measures the visible spans and emoji dimensions', (
    tester,
  ) async {
    await show(
      tester,
      DynamicPost(
        id: 'spans',
        text: List.filled(20, '隐藏的回退正文').join('\n'),
        spans: const [DynamicTextSpan(text: '实际短正文')],
      ),
    );
    expect(find.text('展开全文'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: DynamicPostText(
              post: DynamicPost(
                id: 'emoji',
                spans: List.generate(
                  42,
                  (_) => DynamicTextSpan(
                    kind: DynamicTextKind.emoji,
                    text: '[表情]',
                    emojiSize: 2,
                    imageUrl: Uri.https('example.test', '/emoji'),
                  ),
                ),
              ),
              layoutOnly: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('展开全文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the sole detail action sits at the top right and browser buttons are absent',
    (tester) async {
      var details = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DynamicPostCard(
              post: DynamicPost(id: '1', authorName: '作者'),
              onOpenDetail: () => details++,
              onOpenLink: (_) {},
            ),
          ),
        ),
      );
      final button = find.byTooltip('查看动态详情');
      expect(
        tester.getRect(button).right,
        greaterThan(tester.getRect(find.text('作者')).right),
      );
      expect(tester.getRect(button).top, lessThan(30));
      expect(find.byTooltip('在浏览器打开动态'), findsNothing);
      await tester.tap(button);
      expect(details, 1);
    },
  );
}
