import 'package:bili_player/bili_player.dart';

import 'windows_fvp_seek_synchronization_test.dart' as fvp;
import 'windows_seek_synchronization_test.dart' as media_kit;

// Copy the public fixture files to the test package's external files directory
// and pass that directory via --dart-define=BILI_TEST_MEDIA_DIR=... .
void main() {
  const directory = String.fromEnvironment('BILI_TEST_MEDIA_DIR');
  const backend = String.fromEnvironment(
    'BILI_TEST_BACKEND',
    defaultValue: 'all',
  );
  const selectedOutput = String.fromEnvironment(
    'BILI_TEST_OUTPUT',
    defaultValue: 'all',
  );
  if (directory.isEmpty) throw StateError('BILI_TEST_MEDIA_DIR is required');
  for (final output in AndroidVideoOutputMode.values) {
    if (selectedOutput != 'all' && selectedOutput != output.name) continue;
    if (backend == 'all' || backend == 'media_kit') {
      media_kit.registerMediaKitSeekSynchronizationTests(
        mediaDirectory: directory,
        androidVideoOutput: output,
      );
    }
    if (backend == 'all' || backend == 'fvp') {
      fvp.registerFvpSeekSynchronizationTests(
        mediaDirectory: directory,
        androidVideoOutput: output,
      );
    }
  }
}
