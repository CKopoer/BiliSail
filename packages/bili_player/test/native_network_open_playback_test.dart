import 'dart:io';

import 'package:bili_player/src/media_kit_backend.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:bili_player/src/shared_player_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['BILI_TEST_NATIVE_MPV'];
  for (final live in [false, true]) {
    test(
      'native HTTP open errors reach network retry classification (live=$live)',
      () async {
        mk.MediaKit.ensureInitialized(libmpv: library);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final serving = server.listen((request) async {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        late final SharedPlayerEngine engine;
        engine = SharedPlayerEngine(
          createBackend: () => MediaKitBackend(
            snapshot: () => engine.currentSnapshot,
            createPlayer: () async {
              final player = await createNativePlayer();
              await player.setPropertyAsync('ao', 'null');
              return player;
            },
          ),
        );
        try {
          await expectLater(
            engine.open(
              ProgressiveSource(
                MediaTrack(
                  uri: Uri.parse('http://127.0.0.1:${server.port}/unavailable'),
                  requestPolicy: MediaRequestPolicy(),
                ),
                isAudioOnly: true,
                isLive: live,
              ),
              const OpenOptions(play: true),
            ),
            throwsA(
              isA<PlayerFailure>().having(
                (failure) => failure.kind,
                'network failure kind',
                PlayerFailureKind.networkOpen,
              ),
            ),
          );
        } finally {
          await engine.dispose();
          await serving.cancel();
          await server.close(force: true);
        }
      },
      skip: library == null ? 'Set BILI_TEST_NATIVE_MPV' : false,
    );
  }
}
