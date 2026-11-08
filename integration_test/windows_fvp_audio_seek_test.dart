import 'dart:io';

import 'windows_fvp_seek_synchronization_test.dart';

void main() => registerFvpSeekSynchronizationTests(
  mediaDirectory: Platform.environment['BILI_TEST_BUFFER_DIR']!,
  delayedTrack: 'audio',
  targetMilliseconds: 400375,
  scenarios: const ['playing', 'paused'],
);
