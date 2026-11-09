import 'dart:async';

import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_composer_repository.dart';

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
        })
      >[];
  RequestCancellation? lastRequest;
  Completer<DynamicPicture>? pendingUpload;
  Completer<String>? pendingCreate;
  Object? uploadError, createError;
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
    RequestCancellation cancellation,
  ) async {
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
    required RequestCancellation cancellation,
  }) async {
    lastRequest = cancellation;
    drafts.add((mid: mid, text: text, pictures: pictures, topic: topic));
    if (createError case final error?) throw error;
    return pendingCreate?.future ?? '9007199254740993123';
  }
}
