import 'dart:typed_data';

import 'package:bilisail/domain/local_image.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_composer_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_draft.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_management_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_management_fakes.dart';

void main() {
  late DynamicEditComposerFake repo;
  late DynamicAuthFake auth;
  late ProviderContainer container;
  late DynamicPicture picture;
  DynamicComposerController controller() =>
      container.read(dynamicComposerProvider.notifier);
  DynamicComposerState state() => container.read(dynamicComposerProvider);
  setUp(() {
    repo = DynamicEditComposerFake();
    auth = DynamicAuthFake();
    picture = DynamicPicture(Uri.https('i0.hdslb.com', '/old.png'), 20, 30, 0);
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicComposerRepositoryProvider.overrideWithValue(repo),
        dynamicComposerProvider.overrideWith(
          () => DynamicComposerController(
            editDraft: DynamicEditDraft(
              id: '100',
              authorId: '7',
              title: '标题',
              text: '@名字[doge]投票',
              spans: const [
                DynamicTextSpan(0, 3, DynamicTextKind.mention, id: '8'),
                DynamicTextSpan(3, 9, DynamicTextKind.emote),
                DynamicTextSpan(9, 11, DynamicTextKind.vote, id: '123'),
              ],
              pictures: [picture],
              repostId: '200',
              reserveId: '300',
            ),
          ),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });
  test('editing retains existing pictures, mentions, emotes, vote and repost identity', () async {
    expect(state().canPublish, true);
    controller().addImages([
      LocalImage(Uint8List.fromList([1]), 'image/png'),
    ]);
    expect(await controller().publish(), true);
    expect(repo.drafts, isEmpty);
    expect(repo.uploads, hasLength(1));
    final edit = repo.edits.single;
    expect(edit.id, '100');
    expect(edit.pictures, hasLength(2));
    expect(edit.pictures.first, same(picture));
    expect((edit.repostId, edit.reserveId), ('200', '300'));
    expect(edit.spans.last.kind, DynamicTextKind.vote);
  });
  test('existing pictures can be removed and new attachments cannot silently replace a retained vote', () async {
    controller().removeExistingPicture(picture);
    expect(state().existingPictures, isEmpty);
    controller().setPoll(
      DynamicPollDraft(
        title: '新投票',
        options: const [DynamicPollOption('一'), DynamicPollOption('二')],
        endsAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    expect(state().poll, isNull);
    expect(await controller().publish(), true);
    expect(repo.edits.single.pictures, isEmpty);
    expect(repo.polls, isEmpty);
  });
  test('uncertain edit keeps the original edit identity and prevents duplicate mutation', () async {
    repo.createError = const DynamicWriteUncertain();
    expect(await controller().publish(), false);
    controller().setText('修改也不能重放');
    expect(await controller().publish(), false);
    expect(repo.edits, hasLength(1));
    expect(state().editId, '100');
    expect(state().uncertain, true);
  });
  for (final mid in ['7', '8']) {
    test(
      'an account epoch transition invalidates the editing seed mid=$mid',
      () async {
        expect(state().text, isNotEmpty);
        repo.sessionEpoch++;
        repo.accountScope = 'user:$mid';
        auth.change(AuthState(status: AuthStatus.signedIn, mid: mid));
        await container.pump();
        expect(state().text, isEmpty);
        expect(state().existingPictures, isEmpty);
        expect(state().mid, isNull);
        expect(await controller().publish(), false);
      },
    );
  }
}
