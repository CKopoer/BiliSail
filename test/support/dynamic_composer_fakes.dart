import 'dart:async';

import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_composer_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart';

class DynamicComposerFake implements DynamicComposerRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  final uploads = <LocalImage>[];
  final drafts =
      <
        ({
          String mid,
          String text,
          List<DynamicPicture> pictures,
          DynamicComposeTopic? topic,
          String title,
          List<DynamicTextSpan> spans,
          DynamicPublishOptions options,
          String? pollId,
          String? reserveId,
        })
      >[];
  RequestCancellation? lastRequest;
  Completer<DynamicPicture>? pendingUpload;
  Completer<String>? pendingCreate;
  Completer<String>? pendingPoll;
  Object? uploadError, createError;
  final polls = <DynamicPollDraft>[];
  final reserves = <DynamicReserveDraft>[];
  Object? attachmentError;
  Future<List<DynamicMention>> Function(String, RequestCancellation)?
  onMentions;
  Future<List<DynamicEmotePackage>> Function(RequestCancellation)? onEmotes;
  @override
  Future<List<DynamicEmotePackage>> emotes(
    RequestCancellation cancellation,
  ) async =>
      onEmotes?.call(cancellation) ??
      [
        const DynamicEmotePackage('小黄脸', [
          DynamicEmote('[微笑]', null),
          DynamicEmote('[doge]', null),
        ]),
      ];
  @override
  Future<List<DynamicMention>> mentions(
    String keyword,
    RequestCancellation cancellation,
  ) async =>
      onMentions?.call(keyword, cancellation) ??
      [const DynamicMention('9007199254740993123', '测试用户')];
  @override
  Future<String> createPoll(
    DynamicPollDraft poll,
    List<DynamicPicture> pictures,
    String mid,
    RequestCancellation cancellation,
  ) async {
    lastRequest = cancellation;
    polls.add(poll);
    if (attachmentError case final error?) throw error;
    return pendingPoll?.future ?? '123';
  }

  @override
  Future<String> createReserve(
    DynamicReserveDraft reserve,
    RequestCancellation cancellation,
  ) async {
    lastRequest = cancellation;
    reserves.add(reserve);
    if (attachmentError case final error?) throw error;
    return '456';
  }

  Future<List<DynamicComposeTopic>> Function(String, RequestCancellation)?
  onTopics;
  @override
  Future<List<DynamicComposeTopic>> topics(
    String keyword,
    RequestCancellation cancellation,
  ) async =>
      onTopics?.call(keyword, cancellation) ??
      [const DynamicComposeTopic('12', '测试话题')];
  @override
  Future<DynamicPicture> upload(
    LocalImage image,
    RequestCancellation cancellation, {
    bool forPoll = false,
  }) async {
    lastRequest = cancellation;
    uploads.add(image);
    if (uploadError case final error?) throw error;
    return pendingUpload?.future ??
        DynamicPicture(Uri.https('i0.hdslb.com', '/image.png'), 1, 1, 1);
  }

  @override
  Future<String> create({
    required String mid,
    required String text,
    required List<DynamicPicture> pictures,
    DynamicComposeTopic? topic,
    String title = '',
    List<DynamicTextSpan> spans = const [],
    DynamicPublishOptions options = const DynamicPublishOptions(),
    String? pollId,
    String? pollTitle,
    String? reserveId,
    required RequestCancellation cancellation,
  }) async {
    lastRequest = cancellation;
    drafts.add((
      mid: mid,
      text: text,
      pictures: pictures,
      topic: topic,
      title: title,
      spans: spans,
      options: options,
      pollId: pollId,
      reserveId: reserveId,
    ));
    if (createError case final error?) throw error;
    return pendingCreate?.future ?? '9007199254740993123';
  }
}
