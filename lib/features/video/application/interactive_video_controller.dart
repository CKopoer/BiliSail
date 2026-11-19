import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/interactive_video_repository.dart';

final interactiveVideoRepositoryProvider = Provider<InteractiveVideoRepository>(
  (ref) => throw UnimplementedError(
    'InteractiveVideoRepository must be provided by app',
  ),
);

typedef InteractiveVideoGraph = ({VideoId id, String cid, int epoch});
typedef InteractiveVideoNode = ({InteractiveVideoGraph graph, String? edgeId});

final interactiveVideoGraphProvider = FutureProvider.autoDispose
    .family<String, InteractiveVideoGraph>((ref, graph) {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .read(interactiveVideoRepositoryProvider)
          .loadGraphVersion(graph.id, graph.cid, cancellation: cancellation);
    }, retry: (_, _) => null);

final interactiveVideoChoicesProvider = FutureProvider.autoDispose
    .family<List<InteractiveVideoChoice>, InteractiveVideoNode>((
      ref,
      node,
    ) async {
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      final epoch = ref.read(sessionEpochProvider);
      final repository = ref.read(interactiveVideoRepositoryProvider);
      final version = await ref.watch(
        interactiveVideoGraphProvider(node.graph).future,
      );
      if (cancellation.isCancelled || epoch() != node.graph.epoch) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      return repository.loadChoices(
        node.graph.id,
        version,
        edgeId: node.edgeId,
        cancellation: cancellation,
      );
    }, retry: (_, _) => null);
