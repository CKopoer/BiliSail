import 'dart:async';

import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';

class MemorySettingsRepository implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  bool failWrites = false;
  Completer<void>? pendingWrite;

  @override
  Future<AppSettings> load() async => value;

  @override
  Future<void> save(AppSettings settings) async {
    if (failWrites) throw StateError('settings write failed');
    await pendingWrite?.future;
    value = settings;
  }
}
