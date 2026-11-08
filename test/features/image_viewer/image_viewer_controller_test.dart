import 'dart:async';
import 'dart:typed_data';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/image_export_service.dart';
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
  late _ExportService exporter;
  setUp(() {
    repository = _Repository();
    exporter = _ExportService();
    request = ImageViewerRequest(sources, 0);
    container = ProviderContainer(
      overrides: [
        originalImageRepositoryProvider.overrideWithValue(repository),
        imageExportServiceProvider.overrideWithValue(exporter),
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

  Future<void> load() async {
    final pending = controller.load();
    repository.pending.last.complete(image);
    await pending;
  }

  test('preview loads first; original is explicit and single flight', () async {
    await load();
    expect(repository.sources, [request.previewSource(0)]);
    var state = container.read(imageViewerControllerProvider(request));
    expect(state.isOriginal, isFalse);
    final original = controller.loadOriginal();
    await controller.loadOriginal();
    expect(repository.sources, [request.previewSource(0), sources[0]]);
    state = container.read(imageViewerControllerProvider(request));
    expect(state.loading, isTrue);
    expect(state.image, image);
    repository.pending.last.complete(image);
    await original;
    state = container.read(imageViewerControllerProvider(request));
    expect(state.isOriginal, isTrue);
    await controller.loadOriginal();
    expect(repository.sources, hasLength(2));
    final next = controller.load(1);
    expect(repository.sources.last, request.previewSource(1));
    expect(
      container.read(imageViewerControllerProvider(request)).image,
      isNull,
    );
    repository.pending.last.complete(image);
    await next;
    expect(
      container.read(imageViewerControllerProvider(request)).isOriginal,
      isFalse,
    );
  });

  test(
    'failed original keeps preview and retry targets the original',
    () async {
      await load();
      final original = controller.loadOriginal();
      repository.pending.last.completeError(TimeoutException('test'));
      await original;
      var state = container.read(imageViewerControllerProvider(request));
      expect(state.image, image);
      expect(state.isOriginal, isFalse);
      expect(state.message, '原图加载超时，请重试');
      final retry = controller.retry();
      expect(repository.sources.last, sources[0]);
      repository.pending.last.complete(image);
      await retry;
      state = container.read(imageViewerControllerProvider(request));
      expect(state.isOriginal, isTrue);
      expect(state.message, isNull);
    },
  );

  test(
    'switch cancels original upgrade and ignores its late response',
    () async {
      await load();
      final original = controller.loadOriginal();
      final cancelled = repository.reads.last;
      final next = controller.load(1);
      expect(cancelled.isCancelled, isTrue);
      repository.pending[2].complete(image);
      await next;
      repository.pending[1].complete(image);
      await original;
      final state = container.read(imageViewerControllerProvider(request));
      expect(state.index, 1);
      expect(state.isOriginal, isFalse);
      expect(repository.sources, [
        request.previewSource(0),
        sources[0],
        request.previewSource(1),
      ]);
    },
  );

  test(
    'URLs without a safe CDN preview load directly without an upgrade',
    () async {
      final direct = ImageViewerRequest([
        Uri.parse('https://i0.hdslb.com/a.png?signature=example'),
      ], 0);
      final subscription = container.listen(
        imageViewerControllerProvider(direct),
        (_, _) {},
      );
      final directController = container.read(
        imageViewerControllerProvider(direct).notifier,
      );
      final pending = directController.load();
      repository.pending.last.complete(image);
      await pending;
      expect(repository.sources, direct.images);
      expect(
        container.read(imageViewerControllerProvider(direct)).isOriginal,
        isTrue,
      );
      await directController.loadOriginal();
      expect(repository.sources, hasLength(1));
      subscription.close();
    },
  );

  test('export ignores loading, uses the displayed image and prevents duplicate writes', () async {
    await controller.export(save: true);
    expect(exporter.bytes, isEmpty);
    await load();
    final saving = controller.export(save: true);
    await controller.export(save: false);
    expect(exporter.bytes, [image.bytes]);
    expect(
      container.read(imageViewerControllerProvider(request)).exporting,
      isTrue,
    );
    exporter.saved.complete('Pictures/BiliSail/current.png');
    await saving;
    expect(
      container.read(imageViewerControllerProvider(request)).exportMessage,
      contains('Pictures/BiliSail/current.png'),
    );
    await controller.export(save: false);
    expect(exporter.bytes, [image.bytes, image.bytes]);
    expect(
      container.read(imageViewerControllerProvider(request)).exportMessage,
      contains('已复制'),
    );
  });

  test('switching image suppresses stale export feedback without replacing the new image', () async {
    await load();
    final saving = controller.export(save: true);
    final next = controller.load(1);
    repository.pending.last.complete(image);
    await next;
    exporter.saved.complete('old.png');
    await saving;
    final state = container.read(imageViewerControllerProvider(request));
    expect(state.index, 1);
    expect(state.image, image);
    expect(state.exportMessage, isNull);
    expect(state.exporting, isFalse);
  });

  test('failed export permits retry and hides native error details', () async {
    await load();
    final saving = controller.export(save: true);
    exporter.saved.completeError(StateError('private local path'));
    await saving;
    final state = container.read(imageViewerControllerProvider(request));
    expect(state.exporting, isFalse);
    expect(state.exportMessage, contains('保存失败'));
    expect(state.exportMessage, isNot(contains('private')));
    await controller.export(save: false);
    expect(
      container.read(imageViewerControllerProvider(request)).exportMessage,
      contains('已复制'),
    );
  });

  test('session change and close safely ignore export completion', () async {
    await load();
    final saving = controller.export(save: true);
    container.read(sessionProvider.notifier).change();
    container.read(imageViewerSessionProvider);
    exporter.saved.complete('old.png');
    await saving;
    expect(
      container.read(imageViewerControllerProvider(request)).image,
      isNull,
    );
    expect(
      container.read(imageViewerControllerProvider(request)).exportMessage,
      isNull,
    );
    await load();
    exporter.saved = Completer<String>();
    final closing = controller.export(save: true);
    container.dispose();
    exporter.saved.complete('closed.png');
    await closing;
  });

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
      expect(repository.sources, [
        request.previewSource(0),
        request.previewSource(1),
      ]);
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

class _ExportService implements ImageExportService {
  final bytes = <Uint8List>[];
  var saved = Completer<String>();
  @override
  bool get supported => true;
  @override
  Future<String> save(Uint8List data) {
    bytes.add(data);
    return saved.future;
  }

  @override
  Future<void> copy(Uint8List data) async {
    bytes.add(data);
  }
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
