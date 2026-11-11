import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comment_rich_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('HarmonyOS Sans')..addFont(
          rootBundle.load(
            'assets/fonts/harmonyos_sans/HarmonyOS_Sans_SC_Regular.ttf',
          ),
        ))
        .load();
  });

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${compact ? 'preview' : 'root'} body matches CSS line boxes '
          'in ${dark ? 'dark' : 'light'} theme at $scale',
          (tester) async {
            final opened = <Uri>[];
            final users = <UserId>[];
            final sought = <Duration>[];
            const message = '中文评论 Abc 123\n@用户 00:09\nhttps://example.com';
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? BiliTheme.dark() : BiliTheme.light(),
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SizedBox(
                      width: 320,
                      child: CommentRichContent(
                        compact: compact,
                        comment: const CommentEntry(
                          id: '1',
                          author: '作者',
                          message: message,
                          mentionedUsers: {'用户': UserId('2')},
                        ),
                        onOpenLink: opened.add,
                        onOpenUser: users.add,
                        onSeek: sought.add,
                      ),
                    ),
                  ),
                ),
              ),
            );

            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(CommentRichContent),
                matching: find.byType(RichText),
              ),
            );
            final style = paragraph.text.style!;
            final fontSize = compact ? 14.0 : 15.0;
            final lineHeight = compact ? 20.0 : 25.0;
            expect(style.fontFamily, 'HarmonyOS Sans');
            expect(style.fontSize, fontSize);
            expect(style.fontWeight, FontWeight.w400);
            expect(style.color, Color(dark ? 0xFFE7E9EB : 0xFF18191C));
            expect(style.letterSpacing, 0);
            expect(style.height, lineHeight / fontSize);
            expect(paragraph.text.toPlainText(), message);
            expect(find.byType(SelectionArea), findsOneWidget);

            // CSS splits the space left over from the natural font metrics
            // equally above and below the glyphs, including the outer lines.
            final natural = TextPainter(
              text: TextSpan(
                text: '中文评论 Abc 123',
                style: TextStyle(
                  fontFamily: 'HarmonyOS Sans',
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                ),
              ),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            final metrics = natural.computeLineMetrics().single;
            final expectedAscent =
                (lineHeight * scale + metrics.ascent - metrics.descent) / 2;
            natural.dispose();
            expect(
              paragraph.getDryBaseline(
                paragraph.constraints,
                TextBaseline.alphabetic,
              ),
              closeTo(expectedAscent, .01),
            );
            expect(paragraph.size.height, lineHeight * scale * 3);

            final spans = (paragraph.text as TextSpan).children!
                .cast<TextSpan>();
            for (final span in spans.where((span) => span.recognizer != null)) {
              expect(span.style?.color, Color(dark ? 0xFF2C9CC8 : 0xFF008AC5));
              expect(span.style?.fontWeight, isNull);
              expect(span.style?.fontSize, isNull);
            }
            await tester.tapOnText(find.textRange.ofSubstring('@用户'));
            await tester.tapOnText(find.textRange.ofSubstring('00:09'));
            await tester.tapOnText(
              find.textRange.ofSubstring('https://example.com'),
            );
            expect(users, [const UserId('2')]);
            expect(sought, [const Duration(seconds: 9)]);
            expect(opened, [Uri.parse('https://example.com')]);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
