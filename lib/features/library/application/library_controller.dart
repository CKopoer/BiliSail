import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../domain/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) =>
      throw UnimplementedError('LibraryRepository must be provided by app'),
);

final historyProvider = FutureProvider<List<WatchHistoryEntry>>((ref) {
  final cancellation = RequestCancellation();
  ref.onDispose(cancellation.cancel);
  return ref
      .read(libraryRepositoryProvider)
      .loadHistory(cancellation: cancellation);
});
