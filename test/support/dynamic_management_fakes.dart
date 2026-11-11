import 'dart:async';

import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_composer_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart' as draft;
import 'package:bilisail/features/dynamic/domain/dynamic_management_repository.dart';

import 'dynamic_fakes.dart';
import 'dynamic_composer_fakes.dart';

class DynamicManagementFake extends DynamicRepositoryFake
    implements DynamicManagementRepository {
  final writes = <String>[];
  Completer<void>? pendingWrite;
  Completer<DynamicPost>? pendingDetail;
  Object? writeError;
  bool publicVisibility = true;
  DynamicInteractionSettings settings = const DynamicInteractionSettings(
    canSelect: true,
    selected: false,
    canComment: true,
    comments: true,
  );
  DynamicEditDraft draftValue = const DynamicEditDraft(
    id: '100',
    authorId: '7',
    text: '旧正文[doge]',
    title: '旧标题',
    spans: [draft.DynamicTextSpan(3, 9, draft.DynamicTextKind.emote)],
    pictures: [],
  );
  Future<void> _write(String action, RequestCancellation c) async {
    lastCancellation = c;
    writes.add(action);
    if (writeError case final e?) throw e;
    await pendingWrite?.future;
  }

  @override
  Future<DynamicPost> detail(String id, RequestCancellation c) {
    lastCancellation = c;
    return pendingDetail?.future ?? super.detail(id, c);
  }

  @override
  Future<void> remove(String id, RequestCancellation c) =>
      _write('remove:$id', c);
  @override
  Future<void> pin(String id, bool pinned, RequestCancellation c) =>
      _write('pin:$id:$pinned', c);
  @override
  Future<void> visibility(String id, bool onlySelf, RequestCancellation c) =>
      _write('visibility:$id:$onlySelf', c);
  @override
  Future<void> report(
    String id,
    UserId author,
    int reason,
    String description,
    RequestCancellation c,
  ) => _write('report:$id:$reason:$description', c);
  @override
  Future<void> shareMessage(
    DynamicPost post,
    UserId receiver,
    RequestCancellation c,
  ) => _write('share:${post.id}:${receiver.value}', c);
  @override
  Future<bool> publicVisible(String id, RequestCancellation c) async {
    lastCancellation = c;
    return publicVisibility;
  }

  @override
  Future<DynamicEditDraft> editDraft(String id, RequestCancellation c) async {
    lastCancellation = c;
    return draftValue;
  }

  @override
  Future<DynamicInteractionSettings> interaction(
    CommentTarget t,
    RequestCancellation c,
  ) async {
    lastCancellation = c;
    return settings;
  }

  @override
  Future<void> setInteraction(
    CommentTarget t,
    int action,
    RequestCancellation c,
  ) async {
    await _write('interaction:${t.oid}:${t.type.value}:$action', c);
    settings = DynamicInteractionSettings(
      canSelect: settings.canSelect,
      canComment: settings.canComment,
      selected: action == 1
          ? true
          : action == 2
          ? false
          : settings.selected,
      comments: action == 3
          ? false
          : action == 4
          ? true
          : settings.comments,
    );
  }
}

class DynamicEditComposerFake extends DynamicComposerFake
    implements DynamicEditRepository {
  final edits =
      <
        ({
          String id,
          String text,
          List<DynamicPicture> pictures,
          List<draft.DynamicTextSpan> spans,
          String? repostId,
          String? reserveId,
        })
      >[];
  @override
  Future<void> edit({
    required String mid,
    required String id,
    required String title,
    required String text,
    required List<draft.DynamicTextSpan> spans,
    required List<DynamicPicture> pictures,
    DynamicComposeTopic? topic,
    required draft.DynamicPublishOptions options,
    String? repostId,
    String? reserveId,
    required RequestCancellation cancellation,
  }) async {
    lastRequest = cancellation;
    edits.add((
      id: id,
      text: text,
      pictures: pictures,
      spans: spans,
      repostId: repostId,
      reserveId: reserveId,
    ));
    if (createError case final e?) throw e;
  }
}
