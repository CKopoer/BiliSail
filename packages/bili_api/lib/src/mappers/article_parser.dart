import 'dart:convert';

import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as parser;

import '../models.dart';
import '../models/article_models.dart';
import 'web_comment_target.dart';
import 'web_count.dart';

Map<String, Object?> articleMap(Object? value) =>
    value is Map<String, Object?> ? value : const {};
List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];
String _text(Object? value) => value is String ? value : '';
bool isArticleId(String value) =>
    RegExp(r'^[1-9][0-9]{0,127}$').hasMatch(value);
String? articleId(Object? value) {
  final raw = value is int || value is String ? '$value' : '';
  return isArticleId(raw) ? raw : null;
}

final class ArticleParser {
  const ArticleParser(this.url, this.endpoint);

  final Uri url;
  final String endpoint;

  ApiArticle opus(Map<String, Object?> data, String id) {
    final item = articleMap(data['item']);
    if (item.isEmpty ||
        (item['id_str'] != null && articleId(item['id_str']) != id)) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final modules = <String, Map<String, Object?>>{};
    for (final value in _list(item['modules'])) {
      final module = articleMap(value);
      for (final key in const [
        'module_title',
        'module_author',
        'module_content',
        'module_blocked',
        'module_stat',
      ]) {
        if (module[key] case final Map<String, Object?> value) {
          modules[key] = value;
        }
      }
    }
    final blocked = modules['module_blocked'];
    final comments = articleMap(modules['module_stat']?['comment']);
    return _document(
      title: _text(modules['module_title']?['text']),
      author: modules['module_author'] ?? const {},
      published: modules['module_author']?['pub_ts'],
      blocks: blocked == null
          ? _paragraphs(modules['module_content']?['paragraphs']).toList()
          : const [],
      accessMessage: blocked == null
          ? null
          : [
              _text(blocked['title']),
              _text(blocked['hint_message']),
            ].where((value) => value.trim().isNotEmpty).join('\n'),
      commentTarget: blocked == null
          ? parseWebCommentTarget(articleMap(item['basic']))
          : null,
      commentCount: blocked == null ? parseWebCount(comments['count']) : null,
      commentForbidden: comments['forbidden'] == true,
    );
  }

  ApiArticle legacy(Map<String, Object?> data, String id) {
    if (data['id'] != null && articleId(data['id']) != id) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final content = _text(data['content']);
    final blocks = _paragraphs(
      articleMap(articleMap(data['opus'])['content'])['paragraphs'],
    ).toList();
    if (blocks.isEmpty) {
      if (data['type'] == 3 || data['type'] == '3') {
        blocks.addAll(_quill(data['ops'], content));
      } else if (content.isNotEmpty) {
        blocks.addAll(_html(content));
      }
    }
    return _document(
      title: _text(data['title']),
      author: articleMap(data['author']),
      published: data['publish_time'],
      blocks: blocks,
      commentTarget: (oid: id, type: 12),
    );
  }

  ApiArticle _document({
    required String title,
    required Map<String, Object?> author,
    required Object? published,
    required List<ApiArticleBlock> blocks,
    String? accessMessage,
    ({String oid, int type})? commentTarget,
    int? commentCount,
    bool commentForbidden = false,
  }) {
    if (blocks.isEmpty && accessMessage == null) {
      throw ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final timestamp = int.tryParse('$published');
    return ApiArticle(
      url: url,
      title: title.trim(),
      author: _text(author['name']),
      authorMid: articleId(author['mid']),
      authorAvatar: _imageUri(author['face']),
      publishedAt:
          timestamp != null && timestamp > 0 && timestamp < 253402300800
          ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true)
          : null,
      accessMessage: accessMessage == '' ? '当前账号暂时无法阅读这篇内容' : accessMessage,
      blocks: List.unmodifiable(blocks),
      commentOid: commentTarget?.oid,
      commentType: commentTarget?.type,
      commentCount: commentCount,
      commentForbidden: commentForbidden,
    );
  }

  Iterable<ApiArticleBlock> _paragraphs(
    Object? value, {
    int depth = 0,
    bool quoted = false,
  }) sync* {
    if (depth > 16) return;
    for (final row in _list(value)) {
      final paragraph = articleMap(row);
      final kind = int.tryParse('${paragraph['para_type']}');
      switch (kind) {
        case 1 || 4 || 8:
          final text = _nodes(
            articleMap(paragraph[kind == 8 ? 'heading' : 'text'])['nodes'],
          );
          if (text.isNotEmpty) {
            yield _block(
              kind == 4 || quoted
                  ? ApiArticleBlockKind.quote
                  : kind == 8
                  ? ApiArticleBlockKind.heading
                  : ApiArticleBlockKind.paragraph,
              text,
            );
          }
          if (kind == 4) {
            yield* _paragraphs(
              articleMap(paragraph['blockquote'])['children'],
              depth: depth + 1,
              quoted: true,
            );
          }
        case 2:
          for (final row in _list(articleMap(paragraph['pic'])['pics'])) {
            final photo = articleMap(row);
            final image = _image(photo['url'], photo['width'], photo['height']);
            if (image != null) yield image;
          }
        case 3:
          yield const ApiArticleBlock(ApiArticleBlockKind.divider);
        case 5:
          final list = articleMap(paragraph['list']);
          for (final row in _list(list['items'])) {
            final item = articleMap(row);
            final order = int.tryParse('${item['order']}');
            final text = _nodes(item['nodes']);
            if (text.isNotEmpty) {
              yield _block(ApiArticleBlockKind.paragraph, [
                ApiArticleText(order != null && order > 0 ? '$order. ' : '• '),
                ...text,
              ]);
            }
          }
          for (final row in _list(list['children'])) {
            yield* _paragraphs(
              articleMap(row)['children'],
              depth: depth + 1,
              quoted: quoted,
            );
          }
        case 6:
          final card = articleMap(articleMap(paragraph['link_card'])['card']);
          for (final key in const [
            'ugc',
            'live',
            'opus',
            'common',
            'music',
            'item_null',
            'eva3_video',
            'eva3_opus',
            'eva3_user',
            'eva3_comment',
            'eva3_vote',
          ]) {
            final raw = articleMap(card[key]);
            final info = raw.containsKey('info')
                ? articleMap(raw['info'])
                : raw;
            final title = _text(info['title'] ?? info['text'] ?? info['name']);
            if (title.isEmpty) continue;
            yield _block(ApiArticleBlockKind.paragraph, [
              ApiArticleText(
                title,
                link: _link(info['jump_url'] ?? info['uri']),
              ),
            ]);
            break;
          }
        case 7:
          final value = _text(articleMap(paragraph['code'])['content']);
          if (value.isNotEmpty) {
            yield _block(ApiArticleBlockKind.code, [ApiArticleText(value)]);
          }
      }
    }
  }

  List<ApiArticleText> _nodes(Object? value) => [
    for (final row in _list(value)) ?_node(articleMap(row)),
  ];

  ApiArticleText? _node(Map<String, Object?> node) {
    final rich = articleMap(node['rich']);
    final word = articleMap(node['word']);
    final raw = rich.isNotEmpty ? rich : word;
    final content = _text(
      raw['text'] ??
          raw['orig_text'] ??
          raw['words'] ??
          articleMap(node['formula'])['latex_content'],
    );
    if (content.isEmpty) return null;
    final style = articleMap(raw['style']);
    final mention = rich['type'] == 'RICH_TEXT_NODE_TYPE_AT'
        ? articleId(rich['rid'])
        : null;
    return ApiArticleText(
      content,
      link: mention != null
          ? Uri.https('space.bilibili.com', '/$mention')
          : _link(rich['jump_url']),
      bold: style['bold'] == true,
      italic: style['italic'] == true,
      strike: style['strikethrough'] == true,
    );
  }

  List<ApiArticleBlock> _html(String content) {
    final blocks = <ApiArticleBlock>[];
    final pending = <ApiArticleText>[];
    void flush(ApiArticleBlockKind kind) {
      if (pending.any((run) => run.text.trim().isNotEmpty)) {
        blocks.add(_block(kind, pending));
      }
      pending.clear();
    }

    void walk(
      List<html.Node> nodes,
      ApiArticleBlockKind kind, {
      Uri? link,
      bool bold = false,
      bool italic = false,
      bool strike = false,
      int depth = 0,
    }) {
      if (depth > 32) return;
      for (final node in nodes) {
        if (node is html.Text) {
          pending.add(
            ApiArticleText(
              node.data.replaceAll(RegExp(r'[ \t\r\n]+'), ' '),
              link: link,
              bold: bold,
              italic: italic,
              strike: strike,
            ),
          );
        } else if (node is html.Element) {
          final tag = node.localName;
          if (const {
            'script',
            'style',
            'iframe',
            'object',
            'embed',
            'audio',
            'video',
            'svg',
            'template',
            'noscript',
          }.contains(tag)) {
            continue;
          }
          if (tag == 'br') {
            pending.add(const ApiArticleText('\n'));
            continue;
          }
          if (tag == 'hr' || tag == 'pre' || tag == 'img') {
            flush(kind);
            if (tag == 'hr') {
              blocks.add(const ApiArticleBlock(ApiArticleBlockKind.divider));
            } else if (tag == 'pre') {
              blocks.add(
                _block(ApiArticleBlockKind.code, [ApiArticleText(node.text)]),
              );
            } else {
              final attr = node.attributes;
              final image = _image(
                attr['data-src'] ?? attr['src'],
                attr['width'],
                attr['height'],
              );
              if (image != null) blocks.add(image);
            }
            continue;
          }
          final block = switch (tag) {
            'p' ||
            'div' ||
            'section' ||
            'figure' ||
            'figcaption' ||
            'ul' ||
            'ol' ||
            'li' ||
            'tr' => kind,
            'blockquote' => ApiArticleBlockKind.quote,
            'h1' ||
            'h2' ||
            'h3' ||
            'h4' ||
            'h5' ||
            'h6' => ApiArticleBlockKind.heading,
            _ => null,
          };
          if (block != null) flush(kind);
          if (tag == 'li') pending.add(const ApiArticleText('• '));
          final style = node.attributes['style'] ?? '';
          walk(
            node.nodes,
            block ?? kind,
            link: tag == 'a' ? _link(node.attributes['href']) : link,
            bold:
                bold ||
                tag == 'b' ||
                tag == 'strong' ||
                style.contains('font-weight: bold'),
            italic: italic || tag == 'i' || tag == 'em',
            strike: strike || tag == 's' || tag == 'del' || tag == 'strike',
            depth: depth + 1,
          );
          if (block != null) flush(block);
        }
      }
    }

    const kind = ApiArticleBlockKind.paragraph;
    walk(parser.parseFragment(content).nodes, kind);
    flush(kind);
    return blocks;
  }

  List<ApiArticleBlock> _quill(Object? raw, String content) {
    var operations = _list(raw);
    if (operations.isEmpty && content.isNotEmpty) {
      try {
        final decoded = jsonDecode(content) as Object?;
        operations = _list(
          decoded is List<Object?> ? decoded : articleMap(decoded)['ops'],
        );
      } on FormatException {
        return const [];
      }
    }
    final blocks = <ApiArticleBlock>[];
    final pending = <ApiArticleText>[];
    void flush(ApiArticleBlockKind kind) {
      if (pending.isNotEmpty) blocks.add(_block(kind, pending));
      pending.clear();
    }

    for (final operation in operations) {
      final row = articleMap(operation);
      final insert = row['insert'];
      final attrs = articleMap(row['attributes']);
      if (insert is String) {
        final lines = insert.split('\n');
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (line.isNotEmpty) {
            pending.add(
              ApiArticleText(
                line,
                link: _link(attrs['link']),
                bold: attrs['bold'] == true,
                italic: attrs['italic'] == true,
                strike: attrs['strike'] == true,
              ),
            );
          }
          if (index < lines.length - 1) {
            flush(switch (attrs) {
              {'header': final int level} when level > 0 =>
                ApiArticleBlockKind.heading,
              {'blockquote': true} => ApiArticleBlockKind.quote,
              {'code-block': true} => ApiArticleBlockKind.code,
              _ => ApiArticleBlockKind.paragraph,
            });
          }
        }
      } else if (insert is Map<String, Object?>) {
        flush(ApiArticleBlockKind.paragraph);
        final photo = articleMap(insert['image']);
        final image = _image(
          photo['url'] ?? insert['image'],
          photo['width'],
          photo['height'],
        );
        if (image != null) blocks.add(image);
        for (final kind in const ['article-card', 'live-card', 'video-card']) {
          final card = articleMap(insert[kind]);
          if (card.isEmpty) continue;
          final id = articleId(card['id']);
          final path = id == null
              ? null
              : switch (kind) {
                  'article-card' => '/read/cv$id',
                  'video-card' => '/video/av$id',
                  _ => null,
                };
          final link =
              _link(card['url']) ??
              (kind == 'live-card' && id != null
                  ? Uri.https('live.bilibili.com', '/$id')
                  : path == null
                  ? null
                  : url.resolve(path));
          final label = _text(card['alt'] ?? card['title']);
          if (label.isNotEmpty || link != null) {
            blocks.add(
              _block(ApiArticleBlockKind.paragraph, [
                ApiArticleText(
                  label.isEmpty ? link?.path ?? '' : label,
                  link: link,
                ),
              ]),
            );
          }
        }
      }
    }
    flush(ApiArticleBlockKind.paragraph);
    return blocks;
  }

  static ApiArticleBlock _block(
    ApiArticleBlockKind kind,
    List<ApiArticleText> text,
  ) => ApiArticleBlock(kind, text: List.unmodifiable(text));

  ApiArticleBlock? _image(Object? value, Object? width, Object? height) {
    final image = _imageUri(value);
    if (image == null) return null;
    final w = double.tryParse('$width') ?? 0;
    final h = double.tryParse('$height') ?? 0;
    final ratio = w / h;
    return ApiArticleBlock(
      ApiArticleBlockKind.image,
      image: image,
      aspectRatio: ratio.isFinite && ratio > 0 ? ratio : null,
    );
  }

  Uri? _imageUri(Object? value) {
    final uri = _link(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        !(uri.host.endsWith('.hdslb.com') ||
            uri.host.endsWith('.biliimg.com'))) {
      return null;
    }
    return uri;
  }

  Uri? _link(Object? value) {
    final text = _text(value).trim();
    if (text.isEmpty) return null;
    final parsed = Uri.tryParse(text);
    if (parsed == null) return null;
    final uri = url.resolveUri(parsed);
    return const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }
}
