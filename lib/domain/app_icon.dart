enum AppIconPreference {
  bilisail('哔帆', 'assets/branding/app_icon.png'),
  bilibili('粉红小电视', 'assets/branding/bilibili_pink.png');

  const AppIconPreference(this.label, this.asset);
  final String label;
  final String asset;
}

enum AppIconSurface { unsupported, launcher, window, dock }

abstract interface class AppIconService {
  AppIconSurface get surface;
  Future<AppIconPreference> restore(AppIconPreference saved);
  Future<void> apply(AppIconPreference icon);
}

final class UnsupportedAppIconService implements AppIconService {
  const UnsupportedAppIconService();
  @override
  AppIconSurface get surface => AppIconSurface.unsupported;
  @override
  Future<AppIconPreference> restore(AppIconPreference saved) async => saved;
  @override
  Future<void> apply(AppIconPreference icon) async =>
      throw UnsupportedError('Application icons are unavailable');
}
