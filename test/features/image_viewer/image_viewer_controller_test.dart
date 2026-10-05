import 'dart:async';
import 'dart:typed_data';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class StateProviderForTest extends Notifier<int> {
  @override
  int build() => 0;
  void change() => state++;
}

final sessionProvider = NotifierProvider<StateProviderForTest, int>(
  StateProviderForTest.new,
);

void main() {
  final sources = [
    Uri.parse('https://i0.hdslb.com/a.png'),
    Uri.parse('https://i0.hdslb.com/b.png'),
  ];
  final image = OriginalImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    width: 24,
    height: 16,
  );
  late _Repository repository;
  late ProviderContainer container;
  late ImageViewerRequest request;
  late ImageViewerController controller;
  setUp(() {
    repository = _Repository();
    request = ImageViewerRequest(sources, 0);
    container = ProviderContainer(
      overrides: [
        originalImageRepositoryProvider.overrideWithValue(repository),
        imageViewerSessionProvider.overrideWith(
          (ref) => ref.watch(sessionProvider),
        ),
      ],
    );
    container.listen(imageViewerControllerProvider(request), (_, _) {});
    controller = container.read(
      imageViewerControllerProvider(request).notifier,
    );
  });
  tearDown(() => container.dispose());

  test(
    'switch cancels original and late old response cannot replace next image',
    () async {
      final first = controller.load();
      final second = controller.load(1);
      expect(repository.reads.first.isCancelled, isTrue);
      repository.pending[1].complete(image);
      await second;
      repository.pending.first.complete(image);
      await first;
      final state = container.read(imageViewerControllerProvider(request));
      expect(state.index, 1);
      expect(state.image, image);
      expect(repository.sources, sources);
    },
  );

  test(
    'same pending image is single flight; error permits explicit retry',
    () async {
      final read = controller.load();
      await controller.load();
      expect(repository.pending, hasLength(1));
      repository.pending.first.completeError(TimeoutException('test'));
      await read;
      expect(
        container.read(imageViewerControllerProvider(request)).message,
        contains('超时'),
      );
      final retry = controller.load();
      repository.pending.last.complete(image);
      await retry;
      expect(
        container.read(imageViewerControllerProvider(request)).image,
        image,
      );
    },
  );

  test(
    'closing and account scope changes cancel downloads and release image',
    () async {
      final read = controller.load();
      container.read(sessionProvider.notifier).change();
      container.read(imageViewerSessionProvider);
      expect(repository.reads.first.isCancelled, isTrue);
      repository.pending.first.complete(image);
      await read;
      expect(
        container.read(imageViewerControllerProvider(request)).image,
        isNull,
      );
      final next = controller.load();
      container.dispose();
      expect(repository.reads.last.isCancelled, isTrue);
      repository.pending.last.complete(image);
      await next;
    },
  );
}

class _Repository implements OriginalImageRepository {
  final reads = <RequestCancellation>[];
  final pending = <Completer<OriginalImage>>[];
  final sources = <Uri>[];
  @override
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation) {
    sources.add(source);
    reads.add(cancellation);
    final result = Completer<OriginalImage>();
    pending.add(result);
    return result.future;
  }
}
