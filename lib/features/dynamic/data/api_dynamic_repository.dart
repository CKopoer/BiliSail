import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../shared/data/dynamic_post_mapper.dart';
import '../domain/dynamic_repository.dart';
import '../domain/dynamic_reservation_repository.dart';
import '../domain/dynamic_poll.dart';
import '../domain/dynamic_poll_repository.dart';
import '../domain/dynamic_management_repository.dart';
import '../domain/dynamic_composer_repository.dart';
import '../domain/dynamic_draft.dart' as draft;
import '../../../domain/comment_target.dart';
import '../../../domain/user.dart';
import '../../../domain/app_failure.dart';

final class ApiDynamicRepository
    implements
        DynamicRepository,
        DynamicReservationRepository,
        DynamicManagementRepository,
        DynamicPollRepository,
        DynamicPollSocialRepository {
  ApiDynamicRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final DynamicClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<void> remove(String id, RequestCancellation cancellation) =>
      _write((context) => client.remove(id, context: context), cancellation);
  @override
  Future<void> pin(String id, bool pinned, RequestCancellation cancellation) =>
      _write(
        (context) => client.pin(id, pinned, context: context),
        cancellation,
      );
  @override
  Future<void> visibility(
    String id,
    bool onlySelf,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.visibility(id, onlySelf, context: context),
    cancellation,
  );
  @override
  Future<void> report(
    String id,
    UserId author,
    int reason,
    String description,
    RequestCancellation cancellation,
  ) => _write(
    (context) =>
        client.report(id, author.value, reason, description, context: context),
    cancellation,
  );
  @override
  Future<bool> publicVisible(String id, RequestCancellation cancellation) =>
      requests.run(
        (context) => client.publicVisible(id, context: context),
        cancellation: cancellation,
      );
  @override
  Future<DynamicInteractionSettings> interaction(
    CommentTarget target,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final s = await client.interaction(
      target.oid,
      target.type.value,
      context: context,
    );
    return DynamicInteractionSettings(
      canSelect: s.canSelect,
      selected: s.selected,
      canComment: s.canComment,
      comments: s.comments,
    );
  }, cancellation: cancellation);
  @override
  Future<void> setInteraction(
    CommentTarget target,
    int action,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.setInteraction(
      target.oid,
      target.type.value,
      action,
      context: context,
    ),
    cancellation,
  );
  @override
  Future<DynamicEditDraft> editDraft(
    String id,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final d = await client.editDraft(id, context: context);
    if (d == null) {
      throw const AppFailure(
        AppFailureKind.permission,
        '该动态包含尚不支持编辑的内容，请用官方客户端编辑',
      );
    }
    var offset = 0;
    final spans = <draft.DynamicTextSpan>[];
    final text = StringBuffer();
    for (final c in d.contents) {
      text.write(c.text);
      if (c.type != 1) {
        spans.add(
          draft.DynamicTextSpan(
            offset,
            offset + c.text.length,
            switch (c.type) {
              2 => draft.DynamicTextKind.mention,
              4 => draft.DynamicTextKind.vote,
              _ => draft.DynamicTextKind.emote,
            },
            id: c.id,
          ),
        );
      }
      offset += c.text.length;
    }
    return DynamicEditDraft(
      id: d.id,
      authorId: d.authorId,
      text: text.toString(),
      title: d.title,
      spans: List.unmodifiable(spans),
      pictures: List.unmodifiable([
        for (final p in d.pictures)
          DynamicPicture(p.url, p.width, p.height, p.sizeKiB),
      ]),
      topic: d.topic == null
          ? null
          : DynamicComposeTopic(d.topic!.id, d.topic!.name),
      options: draft.DynamicPublishOptions(
        onlySelf: d.onlySelf,
        replyPolicy: draft.DynamicReplyPolicy.values[d.replyPolicy],
      ),
      repostId: d.repostId,
      reserveId: d.reserveId,
    );
  }, cancellation: cancellation);
  @override
  Future<void> shareMessage(
    DynamicPost post,
    UserId receiver,
    RequestCancellation cancellation,
  ) => _write(
    (context) => MessageClient(client.api).shareDynamic(
      accountScope.substring('user:'.length),
      receiver.value,
      id: post.commentTarget?.type.value == 17
          ? post.id
          : post.commentTarget?.oid ?? post.id,
      title: post.text.isNotEmpty ? post.text : post.title,
      author: post.authorName,
      authorId: post.authorId?.value ?? '',
      source: switch (post.commentTarget?.type.value) {
        11 => 2,
        12 => 6,
        _ => 11,
      },
      thumbnail: post.commentTarget?.type.value == 17
          ? post.authorAvatarUrl
          : post.imageUrls.firstOrNull,
      context: context,
    ),
    cancellation,
  );

  @override
  Future<DynamicPost> detail(String id, RequestCancellation cancellation) =>
      requests.run(
        (context) async =>
            mapDynamicPost(await client.detail(id, context: context)),
        cancellation: cancellation,
      );

  @override
  Future<DynamicPoll> poll(String id, RequestCancellation cancellation) =>
      requests.run(
        (context) async => _poll(
          await DynamicPollClient(client.api).detail(id, context: context),
        ),
        cancellation: cancellation,
      );

  @override
  Future<List<DynamicPollFollowee>> followees(
    String id,
    RequestCancellation c,
  ) => requests.run(
    (context) async => List.unmodifiable([
      for (final f in await DynamicPollClient(
        client.api,
      ).followees(id, context: context))
        DynamicPollFollowee(UserId(f.id), f.name, f.votes, f.avatar),
    ]),
    cancellation: c,
  );

  @override
  Future<DynamicPoll> vote(
    String id,
    String voterId,
    List<int> choices,
    bool anonymous,
    RequestCancellation cancellation, {
    String? dynamicId,
  }) => _write(
    (context) async => _poll(
      await DynamicPollClient(client.api).vote(
        id: id,
        voterId: voterId,
        choices: choices,
        anonymous: anonymous,
        dynamicId: dynamicId,
        context: context,
      ),
    ),
    cancellation,
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
        ApiFailureCategory.protocol,
        ApiFailureCategory.http,
      }.contains(error.category)) {
        throw const DynamicWriteUncertain();
      }
      rethrow;
    }
  }, cancellation: cancellation);

  @override
  Future<void> like(String id, bool liked, RequestCancellation cancellation) =>
      _write(
        (context) => client.like(id, liked, context: context),
        cancellation,
      );
  @override
  Future<DynamicReservation> reserve(
    String dynamicId,
    DynamicReservation reservation,
    RequestCancellation cancellation,
  ) => _write((context) async {
    final result = await client.reserve(
      dynamicId,
      reservation.id,
      reservation.status,
      reservation.total,
      context: context,
    );
    return reservation.updated(result.status, result.total, result.description);
  }, cancellation);
  @override
  Future<String> repost(
    String id,
    String text,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.repost(id, text, context: context),
    cancellation,
  );
}

DynamicPoll _poll(ApiDynamicPoll poll) => DynamicPoll(
  id: poll.id,
  title: poll.title,
  description: poll.description,
  maxChoices: poll.maxChoices,
  endsAt: poll.endsAt,
  joinCount: poll.joinCount,
  options: [
    for (final option in poll.options)
      DynamicPollOption(
        index: option.index,
        text: option.text,
        count: option.count,
        imageUrl: option.imageUrl,
      ),
  ],
  myVotes: poll.myVotes,
);
