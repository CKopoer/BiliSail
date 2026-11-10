import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_draft.dart';
import 'dynamic_composer_controller.dart';

final dynamicComposeEmotesProvider =
    FutureProvider.autoDispose<List<DynamicEmotePackage>>((ref) {
      final repository = ref.watch(dynamicComposerRepositoryProvider);
      ref.watch(
        authControllerProvider.select(
          (s) => (s.status, s.mid, repository?.sessionEpoch),
        ),
      );
      final request = RequestCancellation();
      ref.onDispose(request.cancel);
      return repository?.emotes(request) ?? Future.value(const []);
    }, retry: (_, _) => null);

final dynamicComposeMentionsProvider = FutureProvider.autoDispose
    .family<List<DynamicMention>, String>((ref, keyword) {
      final repository = ref.watch(dynamicComposerRepositoryProvider);
      ref.watch(
        authControllerProvider.select(
          (s) => (s.status, s.mid, repository?.sessionEpoch),
        ),
      );
      final request = RequestCancellation();
      ref.onDispose(request.cancel);
      return repository?.mentions(keyword, request) ?? Future.value(const []);
    }, retry: (_, _) => null);
