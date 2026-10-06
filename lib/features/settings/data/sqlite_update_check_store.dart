import '../../../core/storage/app_database.dart';
import '../../../domain/app_failure.dart';
import '../domain/app_update.dart';

final class SqliteUpdateCheckStore implements UpdateCheckStore {
  const SqliteUpdateCheckStore(this.database);
  final AppDatabase database;
  static const lastStartupDayKey = 'app_update.last_startup_day.v1';

  @override
  Future<bool> claimStartupDay(String day) async {
    try {
      return await database.transaction(() async {
        if (await database.readSetting(lastStartupDayKey) == day) return false;
        await database.writeSetting(lastStartupDayKey, day);
        return true;
      });
    } catch (_) {
      throw const AppFailure(AppFailureKind.storage, '无法保存更新检查日期');
    }
  }
}
