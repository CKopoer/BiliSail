# 动态页默认标签

日期：2026-11-05。需求：[Issue #66](https://github.com/CKopoer/BiliSail/issues/66)。

## 行为

- “设置 → 外观”新增“动态页默认标签”，可选“动态”或“视频动态”，默认仍为“动态”。选择跨启动保存，单／双／多标签、侧栏和底栏共用。
- 本次运行首次从一级导航进入动态页时使用偏好；手动切换后，离开并返回继续保留该会话的标签、内容和滚动状态。修改偏好后，下次从一级入口进入使用新值，不要求重启。
- 显式 `/?channel=dynamic`、`/?channel=videoDynamic` 链接继续按链接打开，并成为本次运行后续返回的选择，不被默认值覆盖。
- 复用设置控制器的串行保存和失败回退。恢复默认回到“动态”；缺失、未知或类型错误的字段回退“动态”，保留其他有效设置。

## 实现边界

偏好是 [AppSettings](../../lib/features/settings/domain/app_settings.dart) 的 `defaultDynamicTab`，通过 [SettingsController](../../lib/features/settings/application/settings_controller.dart) 更新，由 [SqliteSettingsRepository](../../lib/features/settings/data/sqlite_settings_repository.dart) 写入 `preferences.v1`，快照版本从 36 升至 37。SQLite 表结构不变，数据库 schema 仍为 3。

[路由组合根](../../lib/app/router.dart) 将偏好注入 [BiliAppShell](../../lib/app/shell.dart)。外壳保留现有会话内分类记录，偏好变化时只清除动态分类记录，使下次进入采用新默认值；不清除页面缓存或重建播放会话。配置仅选择现有频道，不改变请求协议或写入账号操作。

## 验证

自动回归覆盖默认值、复制和归一化、旧快照与非法字段、SQLite 保存重读、设置恢复默认、保存失败回退、显式频道链接、宽窄布局、三种导航模式和运行时修改。

- 设置、SQLite、工作区外壳及实际路由共 331 项定向测试通过，包含运行中修改设置后再次进入动态页的回归。日志：`build/validation/default-dynamic-tab/focused-tests.log`。
- 同期设置字段与测试更新后，复跑设置、SQLite 和工作区外壳测试，244 项通过；没有覆盖或回退同期改动。日志：`build/validation/default-dynamic-tab/settings-shell-tests.log`。
- 本任务相关源码与测试的 `dart analyze` 无问题，格式检查通过。四个包及 Linux Dart 适配器的格式检查通过；文档本地链接与 `git diff --check` 通过。
- `tool/check.ps1 -SkipPub -Stage PackageTests` 通过：bili_api 586、bili_player 148、bili_danmaku 161、bili_mux 5，共 900 项。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。日志：`build/validation/default-dynamic-tab/package-tests.log`。
- `tool/check.ps1 -SkipPub` 已执行，打包边界脚本通过，随后被同期修改的 `lib/features/video/domain/video_card_interactions.dart` 格式问题阻塞。另行执行根测试时，同期“稍后再看”代码的 `WatchLaterResult.removed` 分支、可空接口调用等编译错误反复出现，因此停止该次运行；未计为根应用全量通过。全局 `flutter analyze --no-pub` 同样报告同期 `video_card_controller.dart`、`video_card.dart` 和 `video_card_cover.dart` 的 8 项问题，本任务定向分析没有问题。原始日志分别为 `check.log`、`root-tests.log`、`analyze.log`，均位于 `build/validation/default-dynamic-tab/`。保留这些同期修改，未为消除检查失败改动其实现。

未构建安装包，未执行 Windows／Android／macOS 实机或性能验收。本机未发现可连接的 Flutter 调试进程，未执行热重载。
