import '../../../domain/local_image.dart';
import '../../../domain/request_cancellation.dart';
import 'dynamic_draft.dart';

final class DynamicComposeTopic {
  const DynamicComposeTopic(this.id, this.name);
  final String id, name;
}

final class DynamicPicture {
  const DynamicPicture(this.url, this.width, this.height, this.sizeKiB);
  final Uri url;
  final int width, height;
  final double sizeKiB;
}

abstract interface class DynamicComposerRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<List<DynamicComposeTopic>> topics(
    String keyword,
    RequestCancellation cancellation,
  );
  Future<DynamicPicture> upload(
    LocalImage image,
    RequestCancellation cancellation, {
    bool forPoll = false,
  });
  Future<List<DynamicEmotePackage>> emotes(RequestCancellation cancellation);
  Future<List<DynamicMention>> mentions(
    String keyword,
    RequestCancellation cancellation,
  );
  Future<String> createPoll(
    DynamicPollDraft poll,
    List<DynamicPicture> pictures,
    String mid,
    RequestCancellation cancellation,
  );
  Future<String> createReserve(
    DynamicReserveDraft reserve,
    RequestCancellation cancellation,
  );
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
  });
}
