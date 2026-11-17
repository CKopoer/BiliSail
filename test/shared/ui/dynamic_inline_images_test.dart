import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/shared/data/dynamic_post_mapper.dart';
import 'package:bilisail/shared/ui/dynamic_post_card.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/material_tooltip_finder.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    for (final forwarded in [false, true]) {
      testWidgets(
        'inline pictures open shared viewer at $width, forwarded=$forwarded',
        (tester) async {
          final api = BiliApiClient(transport: _Transport(forwarded));
          final post = mapDynamicPost(
            await DynamicClient(api).detail('1271520214728572935'),
          );
          final links = <Uri>[];
          var details = 0;
          final originals = _Originals();
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                originalImageRepositoryProvider.overrideWithValue(originals),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: DynamicPostCard(
                      post: post,
                      inDetail: !forwarded,
                      onOpenLink: links.add,
                      onOpenDetail: () => details++,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(originals.sources, isEmpty);
          for (final index in [0, 1]) {
            final label = index == 0 ? '查看图片' : '另一组图片';
            await _tapLink(tester, label);
            await tester.pumpAndSettle();
            expect(links, isEmpty);
            expect(details, 0);
            final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
            expect(viewer.request.images, [
              Uri.parse('https://i0.hdslb.com/bfs/new_dyn/$index.jpg'),
              Uri.parse('https://i0.hdslb.com/bfs/new_dyn/$index-b.jpg'),
            ]);
            expect(viewer.request.initialIndex, 0);
            expect(originals.sources.last.path, contains('/$index.jpg'));
            await tester.tap(findMaterialTooltip('关闭图片'));
            await tester.pumpAndSettle();
            expect(find.byType(ImageViewer), findsNothing);
          }
          // Ordinary links still use the owning page's navigation callback.
          await _tapLink(tester, '普通链接');
          expect(links, [Uri.parse('https://www.bilibili.com/read/cv123')]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _tapLink(WidgetTester tester, String label) async {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(label),
    ),
  );
  final offset = paragraph.text.toPlainText().indexOf(label);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + label.length),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
}

class _Transport implements ApiTransport {
  _Transport(this.forwarded);
  final bool forwarded;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final item = <String, Object?>{
      'id_str': '1271520214728572935',
      'type': 'DYNAMIC_TYPE_FORWARD',
      'modules': {
        'module_dynamic': {
          'desc': {
            'rich_text_nodes': [
              for (final index in [0, 1])
                {
                  'type': 'RICH_TEXT_NODE_TYPE_VIEW_PICTURE',
                  'text': index == 0 ? '查看图片' : '另一组图片',
                  'jump_url': '//www.bilibili.com/read/cv/',
                  'rid': '1271520214728572935',
                  'pics': [
                    {'src': 'http://i0.hdslb.com/bfs/new_dyn/$index.jpg'},
                    {'src': '//i0.hdslb.com/bfs/new_dyn/$index-b.jpg'},
                  ],
                },
              {
                'type': 'RICH_TEXT_NODE_TYPE_WEB',
                'text': '普通链接',
                'jump_url': 'https://www.bilibili.com/read/cv123',
              },
            ],
          },
        },
      },
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': {
              'item': forwarded
                  ? {
                      'id_str': '1271520214728572935',
                      'modules': <String, Object?>{},
                      'orig': {...item, 'id_str': '2'},
                    }
                  : item,
            },
          }),
        ),
      ),
      const {},
    );
  }
}

class _Originals implements OriginalImageRepository {
  final sources = <Uri>[];
  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    sources.add(source);
    throw const FormatException('offline image fixture');
  }
}
