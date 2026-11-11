import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/local_image.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/dynamic_composer_repository.dart';
import '../domain/dynamic_repository.dart';
import '../domain/dynamic_draft.dart';
import '../domain/dynamic_management_repository.dart';

final class ApiDynamicComposerRepository
    implements DynamicComposerRepository, DynamicEditRepository {
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
  Future<void> edit({
    required String mid,
    required String id,
    required String title,
    required String text,
    required List<DynamicTextSpan> spans,
    required List<DynamicPicture> pictures,
    DynamicComposeTopic? topic,
    required DynamicPublishOptions options,
    String? repostId,
    String? reserveId,
    required RequestCancellation cancellation,
  }) => _write((context) async {
    await client.create(
      mid: mid,
      text: text,
      title: title,
      contents: _contents(text, spans, null, null),
      pictures: [
        for (final p in pictures)
          ApiDynamicPicture(p.url, p.width, p.height, p.sizeKiB),
      ],
      topic: topic == null
          ? null
          : ApiDynamicComposeTopic(topic.id, topic.name),
      onlySelf: options.onlySelf,
      replyPolicy: options.replyPolicy.index,
      editId: id,
      repostId: repostId,
      reserveId: reserveId,
      context: context,
    );
  }, cancellation);

  @override
  Future<List<DynamicEmotePackage>> emotes(RequestCancellation cancellation) =>
      requests.run(
        (context) async => [
          for (final p in await client.api.getCommentEmotes(context: context))
            DynamicEmotePackage(
              p.name,
              List.unmodifiable([
                for (final e in p.items) DynamicEmote(e.text, e.imageUrl),
              ]),
            ),
        ],
        cancellation: cancellation,
      );

  @override
  Future<List<DynamicMention>> mentions(
    String keyword,
    RequestCancellation cancellation,
  ) => requests.run(
    (context) async => [
      for (final u in await client.mentions(keyword, context: context))
        DynamicMention(u.id, u.name, avatar: u.avatar),
    ],
    cancellation: cancellation,
  );

  Future<T> _write<T>(
    Future<T> Function(ApiRequestContext) operation,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    try {
      return await operation(context);
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

  @override
  Future<String> createPoll(
    DynamicPollDraft poll,
    List<DynamicPicture> pictures,
    String mid,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.createPoll(
      mid: mid,
      title: poll.title,
      description: poll.description,
      maxChoices: poll.maxChoices,
      endsAt: poll.endsAt,
      options: [
        for (final (i, o) in poll.options.indexed)
          ApiDynamicPollOption(
            o.text,
            imageUrl: poll.withImages ? pictures[i].url : null,
          ),
      ],
      context: context,
    ),
    cancellation,
  );

  @override
  Future<String> createReserve(
    DynamicReserveDraft reserve,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.createReserve(
      title: reserve.title,
      startsAt: reserve.startsAt,
      onlyMembers: reserve.onlyMembers,
      context: context,
    ),
    cancellation,
  );

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
    RequestCancellation cancellation, {
    bool forPoll = false,
  }) => requests.run((context) async {
    final p = await client.upload(
      image.bytes,
      image.mimeType,
      forPoll: forPoll,
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
    String title = '',
    List<DynamicTextSpan> spans = const [],
    DynamicPublishOptions options = const DynamicPublishOptions(),
    String? pollId,
    String? pollTitle,
    String? reserveId,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    try {
      return await client.create(
        mid: mid,
        text: text + (pollId == null ? '' : pollTitle ?? ''),
        title: title,
        contents: _contents(text, spans, pollId, pollTitle),
        onlySelf: options.onlySelf,
        replyPolicy: options.replyPolicy.index,
        publishAt: options.publishAt,
        reserveId: reserveId,
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

List<ApiDynamicContent> _contents(
  String text,
  List<DynamicTextSpan> spans,
  String? pollId,
  String? pollTitle,
) {
  final result = <ApiDynamicContent>[];
  var offset = 0;
  for (final span in spans) {
    if (span.start < offset ||
        span.end > text.length ||
        span.end <= span.start) {
      throw ArgumentError('Invalid rich text range');
    }
    if (span.start > offset) {
      result.add(ApiDynamicContent(text.substring(offset, span.start), 1));
    }
    result.add(
      ApiDynamicContent(
        text.substring(span.start, span.end),
        switch (span.kind) {
          DynamicTextKind.mention => 2,
          DynamicTextKind.vote => 4,
          DynamicTextKind.emote => 9,
        },
        id: span.id,
      ),
    );
    offset = span.end;
  }
  if (offset < text.length) {
    result.add(ApiDynamicContent(text.substring(offset), 1));
  }
  if (pollId != null) {
    result.add(ApiDynamicContent(pollTitle ?? '', 4, id: pollId));
  }
  return result;
}
