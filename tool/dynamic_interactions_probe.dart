import 'dart:convert';
import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/app/dependencies.dart';
import 'package:flutter/widgets.dart';

/// Explicit authenticated read probe. No IDs, content, URLs or credentials are
/// emitted, and no comment, like or repost mutation is reachable here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  try {
    await dependencies.session.restore();
    final page = await dependencies.requests.run(
      (context) => HomeClient(dependencies.api)
          .load(channel: 'dynamic', section: '全部', page: 1, context: context),
    );
    final posts = page.items.map((item) => item.dynamicPost).nonNulls.toList();
    stdout.writeln(
      jsonEncode({
        'stage': 'feed',
        'posts': posts.length,
        'withCommentTarget': posts
            .where((p) => p.commentOid != null && p.commentType != null)
            .length,
      }),
    );
    final seenTypes = <int>{};
    for (final post in posts.take(12)) {
      final oid = post.commentOid, type = post.commentType;
      if (oid == null ||
          type == null ||
          post.commentForbidden ||
          !seenTypes.add(type)) {
        continue;
      }
      try {
        final comments = await dependencies.requests.run(
          (context) => dependencies.api.getVideoComments(
            oid,
            commentType: type,
            context: context,
          ),
        );
        stdout.writeln(
          jsonEncode({
            'stage': 'comments',
            'type': type,
            'items': comments.items.length,
            'hasMore': comments.hasMore,
          }),
        );
        final root = comments.items.where((c) => c.replyCount > 0).firstOrNull;
        if (root != null) {
          final replies = await dependencies.requests.run(
            (context) => dependencies.api.getVideoReplies(
              oid,
              root.id,
              commentType: type,
              context: context,
            ),
          );
          stdout.writeln(
            jsonEncode({
              'stage': 'replies',
              'type': type,
              'items': replies.items.length,
              'hasMore': replies.hasMore,
            }),
          );
        }
      } on ApiFailure catch (error) {
        stdout.writeln(
          jsonEncode({
            'stage': 'comments',
            'type': type,
            'category': error.category.name,
            'code': error.businessCode,
          }),
        );
      }
      if (seenTypes.length >= 3) break;
    }
    if (posts.isNotEmpty) {
      final post = await dependencies.requests.run(
        (context) =>
            DynamicClient(dependencies.api)
                .detail(posts.first.id, context: context),
      );
      stdout.writeln(
        jsonEncode({
          'stage': 'detail',
          'commentType': post.commentType,
          'liked': post.liked,
          'unavailable': post.unavailable,
        }),
      );
    }
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'stage': 'failed',
        'errorType': error.runtimeType.toString(),
      }),
    );
    exitCode = 1;
  } finally {
    await dependencies.close();
  }
  exit(exitCode);
}
