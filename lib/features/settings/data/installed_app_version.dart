import 'package:package_info_plus/package_info_plus.dart';

import '../../../domain/app_failure.dart';
import '../domain/app_update.dart';

Future<AppVersion> loadInstalledAppVersion() async {
  // Release scripts supply the source revision: split Android APK versionCode
  // includes an ABI offset and is not the Flutter +N used in Release tags.
  const releaseVersion = String.fromEnvironment('BILISAIL_RELEASE_VERSION');
  if (releaseVersion.isNotEmpty) {
    final parsed = AppVersion.tryParse(releaseVersion);
    if (parsed != null) return parsed;
    throw const AppFailure(AppFailureKind.protocol, '构建版本格式无效');
  }
  final info = await PackageInfo.fromPlatform().timeout(
    const Duration(seconds: 5),
  );
  final parsed = AppVersion.tryParse(
    '${info.version}${info.buildNumber.isEmpty ? '' : '+${info.buildNumber}'}',
  );
  if (parsed == null) {
    throw const AppFailure(AppFailureKind.protocol, '无法读取当前应用版本');
  }
  return parsed;
}
