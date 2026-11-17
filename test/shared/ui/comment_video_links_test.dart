import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const bv = 'BV117BkBsEWw';
  testWidgets('video icons and titles open the original target on real taps', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentRichContent(
            comment: const CommentEntry(
              id: '1',
              author: 'reader',
              message: '$bv https://example.com/x',
              linkTitles: {bv: '视频标题'},
            ),
            onOpenLink: opened.add,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    final text = tester.widget<Text>(find.byType(Text));
    final spans = (text.textSpan! as TextSpan).children!.whereType<TextSpan>();
    final video = spans.firstWhere((span) => span.text == '视频标题');
    final external = spans.firstWhere(
      (span) => span.text == 'https://example.com/x',
    );
    expect(video.style?.fontWeight, FontWeight.w600);
    expect(video.style?.color, external.style?.color);
    expect(external.style?.fontWeight, isNull);
    expect(video.semanticsLabel, '视频：视频标题');
    expect(opened, isEmpty);
    await tester.tapOnText(find.textRange.ofSubstring('视频标题'));
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    expect(opened, [
      Uri.https('www.bilibili.com', '/video/$bv'),
      Uri.https('www.bilibili.com', '/video/$bv'),
    ]);
  });

  testWidgets(
    'compact, scaled and detached measurement use identical video layout',
    (tester) async {
      Future<void> show(bool layoutOnly) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 180,
                child: CommentRichContent(
                  layoutOnly: layoutOnly,
                  compact: true,
                  comment: const CommentEntry(
                    id: '1',
                    author: 'reader',
                    message: '$bv 和 av170001',
                    linkTitles: {bv: '一段较长的视频标题用于换行'},
                  ),
                  onOpenLink: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await show(false);
      final size = tester.getSize(find.byType(CommentRichContent));
      expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));
      expect(
        tester.getRect(find.byIcon(Icons.play_circle_outline).first).height,
        32,
      );
      expect(tester.takeException(), isNull);
      await show(true);
      expect(tester.getSize(find.byType(CommentRichContent)), size);
      final text = tester.widget<Text>(find.byType(Text));
      expect(
        (text.textSpan! as TextSpan).children!.whereType<TextSpan>().where(
          (span) => span.recognizer != null,
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'updates server titles, callbacks and releases video recognizers',
    (tester) async {
      final first = <Uri>[], second = <Uri>[];
      Future<void> show(String title, ValueChanged<Uri>? open) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CommentRichContent(
                  comment: CommentEntry(
                    id: '1',
                    author: 'reader',
                    message: bv,
                    linkTitles: {bv: title},
                  ),
                  onOpenLink: open,
                ),
              ),
            ),
          );
      await show('旧标题', first.add);
      await tester.tapOnText(find.textRange.ofSubstring('旧标题'));
      await show('新标题', second.add);
      await tester.tapOnText(find.textRange.ofSubstring('新标题'));
      await show('新标题', null);
      final text = tester.widget<Text>(find.byType(Text));
      final span = (text.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .single;
      expect(span.recognizer, isNull);
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
