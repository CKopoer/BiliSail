import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_settings.dart';
import '../domain/shortcut_settings.dart';
import '../domain/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) =>
      throw UnimplementedError('SettingsRepository must be provided by app'),
);

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

final class SettingsController extends AsyncNotifier<AppSettings> {
  Future<void> _writeQueue = Future<void>.value();
  AppSettings? _persisted;
  int _revision = 0;

  @override
  Future<AppSettings> build() async {
    ++_revision;
    await _writeQueue;
    final loaded = await ref.read(settingsRepositoryProvider).load();
    _persisted = loaded;
    return loaded;
  }

  Future<void> setShortcuts(ShortcutSettings value) {
    if (value.conflict case final String conflict) {
      throw ArgumentError(conflict);
    }
    return update((current) => current.copyWith(shortcuts: value));
  }

  Future<void> setTheme(AppThemePreference value) =>
      update((current) => current.copyWith(theme: value));
  Future<void> setFont(AppFontPreference value) =>
      update((current) => current.copyWith(font: value));
  Future<void> setSystemFont(String family) => update(
    (current) => current.copyWith(
      font: AppFontPreference.installed,
      systemFontFamily: family,
    ),
  );
  Future<void> setCacheImages(bool value) =>
      update((current) => current.copyWith(cacheImages: value));
  Future<void> setDanmakuEnabled(bool value) =>
      update((current) => current.copyWith(danmakuEnabled: value));
  Future<void> setShowCollapsedProgress(bool value) =>
      update((current) => current.copyWith(showCollapsedProgress: value));
  Future<void> setDanmakuOpacity(double value) =>
      update((current) => current.copyWith(danmakuOpacity: value));
  Future<void> setDanmakuFontScale(double value) =>
      update((current) => current.copyWith(danmakuFontScale: value));
  Future<void> setAutoPlay(bool value) =>
      update((current) => current.copyWith(autoPlay: value));
  Future<void> setResumePlayback(bool value) =>
      update((current) => current.copyWith(resumePlayback: value));
  Future<void> setPreferredQuality(int value) =>
      update((current) => current.copyWith(preferredQuality: value));
  Future<void> setPreferredVideoCodec(VideoCodecPreference value) =>
      update((current) => current.copyWith(preferredVideoCodec: value));
  Future<void> setVideoDecoding(VideoDecodingPreference value) =>
      update((current) => current.copyWith(videoDecoding: value));
  Future<void> setDefaultPlaybackRate(double value) =>
      update((current) => current.copyWith(defaultPlaybackRate: value));
  Future<void> setDefaultVolume(double value) =>
      update((current) => current.copyWith(defaultVolume: value));
  Future<void> setDanmakuArea(double value) =>
      update((current) => current.copyWith(danmakuArea: value));
  Future<void> setDanmakuTopMargin(double value) =>
      update((current) => current.copyWith(danmakuTopMargin: value));
  Future<void> setDanmakuSpeed(double value) =>
      update((current) => current.copyWith(danmakuSpeed: value));
  Future<void> setDanmakuMaxPerSecond(int value) =>
      update((current) => current.copyWith(danmakuMaxPerSecond: value));
  Future<void> setDanmakuMaxOnScreen(int value) =>
      update((c) => c.copyWith(danmakuMaxOnScreen: value));
  Future<void> setDanmakuScrollEnabled(bool value) =>
      update((current) => current.copyWith(danmakuScrollEnabled: value));
  Future<void> setDanmakuTopEnabled(bool value) =>
      update((current) => current.copyWith(danmakuTopEnabled: value));
  Future<void> setDanmakuBottomEnabled(bool value) =>
      update((current) => current.copyWith(danmakuBottomEnabled: value));
  Future<void> setDanmakuFont(DanmakuFontPreference value) =>
      update((c) => c.copyWith(danmakuFont: value));
  Future<void> setDanmakuBold(bool value) =>
      update((c) => c.copyWith(danmakuBold: value));
  Future<void> setDanmakuStyle(DanmakuStylePreference value) =>
      update((c) => c.copyWith(danmakuStyle: value));
  Future<void> setDanmakuMergeDuplicates(bool value) =>
      update((c) => c.copyWith(danmakuMergeDuplicates: value));
  Future<void> setDanmakuBlockColored(bool value) =>
      update((c) => c.copyWith(danmakuBlockColored: value));
  Future<void> setDanmakuMinimumWeight(int value) =>
      update((c) => c.copyWith(danmakuMinimumWeight: value));
  Future<void> setDanmakuOffset(Duration value) =>
      update((c) => c.copyWith(danmakuOffset: value));
  Future<void> setDanmakuBlockedWords(List<String> value) =>
      update((current) => current.copyWith(danmakuBlockedWords: value));
  Future<void> setSubtitlesEnabled(bool value) =>
      update((current) => current.copyWith(subtitlesEnabled: value));
  Future<void> setSubtitleFontScale(double value) =>
      update((current) => current.copyWith(subtitleFontScale: value));
  Future<void> setSubtitleBackgroundOpacity(double value) =>
      update((current) => current.copyWith(subtitleBackgroundOpacity: value));
  Future<void> setSubtitleBottomPadding(double value) =>
      update((current) => current.copyWith(subtitleBottomPadding: value));
  Future<void> setSponsorBlockMode(SponsorBlockMode value) =>
      update((current) => current.copyWith(sponsorBlockMode: value));
  Future<void> setSponsorBlockCategories(List<String> value) =>
      update((current) => current.copyWith(sponsorBlockCategories: value));

  @override
  Future<AppSettings> update(
    FutureOr<AppSettings> Function(AppSettings) cb, {
    FutureOr<AppSettings> Function(Object, StackTrace)? onError,
  }) async {
    final previous = state.asData?.value ?? await future;
    final candidate = cb(previous);
    final next =
        (candidate is Future<AppSettings> ? await candidate : candidate)
            .normalized();
    final revision = ++_revision;
    state = AsyncData(next);
    final repository = ref.read(settingsRepositoryProvider);
    final write = _writeQueue.then((_) async {
      await repository.save(next);
      _persisted = next;
    });
    // A failed write must not prevent a newer setting from reaching storage.
    _writeQueue = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await write;
      return next;
    } catch (_) {
      if (ref.mounted && revision == _revision) {
        state = AsyncData(_persisted ?? previous);
      }
      rethrow;
    }
  }
}
