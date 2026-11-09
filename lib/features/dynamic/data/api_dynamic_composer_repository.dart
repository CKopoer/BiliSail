import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/local_image.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/dynamic_composer_repository.dart';
import '../domain/dynamic_repository.dart';

final class ApiDynamicComposerRepository implements DynamicComposerRepository {
  ApiDynamicComposerRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final DynamicPublishClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<List<DynamicComposeTopic>> topics(
    String keyword,
    RequestCancellation cancellation,
  ) => requests.run(
    (context) async => [
      for (final topic in await client.topics(keyword, context: context))
        DynamicComposeTopic(topic.id, topic.name),
    ],
    cancellation: cancellation,
  );

  @override
  Future<DynamicPicture> upload(
    LocalImage image,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final p = await client.upload(
      image.bytes,
      image.mimeType,
      context: context,
    );
    return DynamicPicture(p.url, p.width, p.height, p.sizeKiB);
  }, cancellation: cancellation);

  @override
  Future<String> create({
    required String mid,
    required String text,
    required List<DynamicPicture> pictures,
    DynamicComposeTopic? topic,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    try {
      return await client.create(
        mid: mid,
        text: text,
        pictures: [
          for (final p in pictures)
            ApiDynamicPicture(p.url, p.width, p.height, p.sizeKiB),
        ],
        topic: topic == null
            ? null
            : ApiDynamicComposeTopic(topic.id, topic.name),
        context: context,
      );
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.http,
        ApiFailureCategory.protocol,
      }.contains(error.category)) {
        throw const DynamicWriteUncertain();
      }
      rethrow;
    }
  }, cancellation: cancellation);
}
