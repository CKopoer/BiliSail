import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/application/favorite_folder_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/favorite_folder_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 1735.0]) {
    testWidgets('created folder metadata and menu fit $width at double text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opens = 0;
      var edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width == 360 ? 320 : 400,
                child: FavoriteFolderCard(
                  entry: HomeEntry(
                    id: '42',
                    title: '音乐与其他收藏内容',
                    kind: HomeEntryKind.folder,
                    isPrivate: true,
                    createdAt: DateTime(2021, 4, 7),
                    contentCount: 11,
                    viewCount: 25000,
                  ),
                  showCreatedMetadata: true,
                  onTap: () => opens++,
                  onEdit: () => edits++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('11个内容 私密'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('11个内容 私密'))
            .didExceedMaxLines,
        false,
      );
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('创建于2021-04-07'), findsOneWidget);
      expect(find.textContaining('播放'), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑信息'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(opens, 0);
      await tester.tap(find.text('音乐与其他收藏内容'));
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('menu loads complete details, saves form and refreshes cards', (
    tester,
  ) async {
    final repository = _EditorRepository();
    final home = _HomeRepository(repository);
    await _pump(tester, home, repository);
    expect(home.loads, 1);
    await _open(tester);
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields[0].controller?.text, '音乐');
    expect(fields[1].controller?.text, '保留完整简介');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      true,
    );
    await tester.enterText(find.byType(TextFormField).first, '新收藏夹');
    await tester.enterText(find.byType(TextFormField).last, '新简介 & + %');
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.writes, 1);
    expect(repository.info.title, '新收藏夹');
    expect(repository.info.intro, '新简介 & + %');
    expect(repository.info.isPrivate, false);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('新收藏夹'), findsOneWidget);
    expect(find.text('11个内容 公开'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(home.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty title and cancellation never write', (tester) async {
    final repository = _EditorRepository();
    await _pump(tester, _HomeRepository(repository), repository);
    await _open(tester);
    await tester.enterText(find.byType(TextFormField).first, '  ');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入收藏夹名称'), findsOneWidget);
    expect(repository.writes, 0);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(repository.writes, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('read failure cannot overwrite missing folder info', (
    tester,
  ) async {
    final repository = _EditorRepository()
      ..readFailure = const AppFailure(AppFailureKind.network, '无法连接');
    await _pump(tester, _HomeRepository(repository), repository);
    await _open(tester);
    expect(find.text('无法连接'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );
    expect(repository.writes, 0);
  });

  testWidgets(
    'uncertain save retains draft until explicit server reconciliation',
    (tester) async {
      final repository = _EditorRepository()
        ..writeFailure = const FavoriteFolderWriteUncertain();
      await _pump(tester, _HomeRepository(repository), repository);
      await _open(tester);
      await tester.enterText(find.byType(TextFormField).first, '待核对的名称');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(repository.writes, 1);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller
            ?.text,
        '待核对的名称',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(TextButton, '重新读取'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller
            ?.text,
        '音乐',
      );
      expect(repository.writes, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('editing fits a narrow dialog with large text and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _EditorRepository();
    await _pump(tester, _HomeRepository(repository), repository, scale: 2);
    await _open(tester);
    await tester.tap(find.byType(TextFormField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('编辑信息'));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _HomeRepository home,
  _EditorRepository repository, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeRepositoryProvider.overrideWithValue(home),
        favoriteFolderRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(_Auth()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: AppNoticeHost(child: child!),
        ),
        home: const Scaffold(
          body: HomeContent(
            channel: HomeChannel.favorites,
            section: '我创建的收藏夹',
            isSignedIn: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _HomeRepository implements HomeRepository {
  _HomeRepository(this.editor);
  final _EditorRepository editor;
  int loads = 0;
  @override
  String get accountScope => 'user:1';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    loads++;
    return HomePage([
      HomeEntry(
        id: '42',
        title: editor.info.title,
        kind: HomeEntryKind.folder,
        contentCount: 11,
        viewCount: 20000,
        isPrivate: editor.info.isPrivate,
        createdAt: DateTime(2021, 4, 7),
      ),
    ], hasMore: false);
  }
}

final class _EditorRepository implements FavoriteFolderRepository {
  FavoriteFolderInfo info = const FavoriteFolderInfo(
    id: '42',
    title: '音乐',
    intro: '保留完整简介',
    isPrivate: true,
  );
  int writes = 0;
  Object? readFailure;
  Object? writeFailure;
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 1;
  @override
  Future<FavoriteFolderInfo> load(
    FavoriteFolderTarget target,
    RequestCancellation c,
  ) async {
    if (readFailure case final failure?) throw failure;
    return info;
  }

  @override
  Future<void> update(
    FavoriteFolderTarget target,
    FavoriteFolderEdit edit,
    RequestCancellation c,
  ) async {
    writes++;
    if (writeFailure case final failure?) throw failure;
    info = FavoriteFolderInfo(
      id: target.id,
      title: edit.title,
      intro: edit.intro,
      isPrivate: edit.isPrivate,
    );
  }
}

final class _Auth implements AuthRepository {
  @override
  AuthState get current =>
      const AuthState(status: AuthStatus.signedIn, mid: '1');
  @override
  Stream<AuthState> get changes => const Stream.empty();
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  void cancelSignIn() {}
  @override
  Future<void> signOut() async {}
}
