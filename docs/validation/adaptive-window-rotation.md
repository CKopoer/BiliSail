# 主窗口、播放器旋转与折叠边界

日期：2026-10-28。本文按用户后续要求修订[手机旋转全屏](responsive-player.md#手机旋转全屏2026-10-28)中的尺寸与方向规则。

2026-10-31 修复缓存引擎首次启动缺失完整屏幕指标导致的平板导航误判，保留窄屏强制底栏；初始化、原始指标校验和本轮验收边界见 [Android 平板冷启动导航布局](android-tablet-navigation-cold-start.md)。

## 当前行为

2026-11-16 增加“设置 → 外观 → 应用方向”，Android／iOS 可选择“自动、竖屏、横屏”，保存后立即应用并跨启动保留。默认“自动”沿用下表规则；“竖屏”和“横屏”在普通页面及播放全屏时均优先采用固定方向，并停用旋转触发的进入／退出全屏，手动全屏与退出继续可用。桌面不显示此移动端选项，保留原生窗口行为。

固定方向通过系统方向接口请求，实际生效仍受系统限制：当前 Flutter `SystemChrome.setPreferredOrientations` 说明 Android 16／API 36 起，显示宽度至少 600 dp 的设备不能通过该接口固定方向；iPad 启用多任务时也可能忽略方向请求。本次不修改平台的多窗口／多任务能力或系统兼容策略，组件测试仅证明方向命令正确，不能证明系统接受了方向锁定。

主窗口与播放器共用 [WindowSizePolicy](../../lib/core/platform/window_size_policy.dart) 的 600 逻辑像素边界，同时分别检查完整显示屏和当前可用窗口宽度。可用宽度扣除横向系统安全区；不使用设备型号，也不把旋转后的长边当作大屏依据。

| 自动方向模式下的条件 | 普通页面 | 自动导航 | 播放器旋转 |
| --- | --- | --- | --- |
| 移动端完整显示屏最短边小于 600 | 竖屏 | 底栏，横放也不变成侧栏 | 窄屏横向视频有播放意图时，物理横拿进入全屏，回转竖拿退出 |
| 移动端完整显示屏最短边至少 600，可用窗口宽度小于 600 | 跟随系统方向，不安装方向限制 | 底栏 | 随显示屏实际旋转进入／退出全屏，保留窄窗约束，不强制大屏方向 |
| 移动端完整显示屏最短边至少 600，可用窗口宽度至少 600 | 跟随系统方向 | 侧栏 | 旋转只调整整体布局，保持当前全屏／非全屏选择 |
| 桌面 | 保留原生窗口行为 | 按实际窗口宽度及保存的偏好 | 不增加移动旋转行为 |

2026-10-31 修订：Android 手机仅在系统自动旋转开启时使用物理方向进出全屏；系统锁定方向时忽略物理旋转，手动全屏和退出仍可用。锁定状态变化取消待执行的旋转操作，解锁后的首个姿势仅建立基线。iOS 没有可用的公开系统旋转锁状态接口，手机暂停物理旋转触发的全屏切换，仍可手动切换；大屏窄分屏继续跟随系统实际显示方向。

此次播放面板／窗口服务专项测试及本次文件静态分析通过，覆盖锁定时取消排队的进入／退出、解锁后重建基线和手动全屏。四个包的测试通过，其中 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。根检查被并行任务新增的未格式化探针阻塞；独立根测试中音频测试因并行修改期间缺少 `BackgroundVideoControl` 而编译失败。Android 开发 Release 构建重试成功，使用当前工作区（含并行修改）及已有 mux 资产，未安装；没有连接 Android 设备或 DTD 调试进程，Android／iOS 实机旋转锁行为和热重载未验证。

导航栏偏好不迁移、不重写。移动端空间不足时，保存的“侧边栏”选择临时使用底栏，空间恢复后重新采用原选择；明确保存的“底栏”选择继续保留。自动模式在宽度足够时隐藏底栏、显示侧栏。页面身份、访问历史、PageStorage 和播放会话继续保留。

## 方向所有权

应用方向是纯 Dart [AppOrientationPreference](../../lib/domain/app_orientation.dart)，由 `AppSettings.orientation` 持有；[设置控制器](../../lib/features/settings/application/settings_controller.dart) 沿用串行写入、即时应用及保存失败回退。[SQLite 设置仓储](../../lib/features/settings/data/sqlite_settings_repository.dart) 将它保存在 `preferences.v1.orientation`，快照版本增至 53，数据库表和数据库版本 3 不变。旧快照缺失该字段或字段非法时回退“自动”，有效旧设置保留；全局恢复默认也回到“自动”。方向宿主接收组合根注入的当前设置，更新方向不替换页面或播放会话；所有系统方向请求继续经过同一串行队列，执行时读取最新选择。

[WindowOrientationHost](../../lib/core/presentation/window_orientation_host.dart) 位于主应用的 `MaterialApp.builder`，监听所属 Flutter view 的显示屏变化和应用恢复，将完整显示屏尺寸交给同一个 [WindowService](../../lib/core/platform/window_service.dart)。自动模式下，手机普通页面申请竖屏，进入播放器全屏时暂时由该 owner 的画面方向覆盖；退出恢复普通页面的竖屏策略。主窗口销毁后释放自己安装的限制。

自动模式下大屏不安装方向限制，避免 Android 的兼容居中窗口；即使分屏或过渡窗口还很窄，也以完整 display 判断是否释放旧手机限制。方向命令统一串行执行，并在执行时读取最新显示屏和全屏意图，设置 2 秒超时；迟到的手机命令不能在展开后的大屏重新加锁。大屏未加锁时不会无条件发送空方向列表覆盖其他系统策略。

普通手机页面已锁竖屏，因此 Android 上 [PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 在当前 owner 可见、前台且有横向视频播放意图时也订阅物理方向；全屏内继续共用该订阅。原生侧监听系统自动旋转设置并在关闭时停止传感器；设置变化时清除待执行操作。暂停普通播放、隐藏、后台及销毁取消订阅，旧回调以订阅 owner 隔离。手动退出时仍横拿不会立即再次进入，竖拿后下一次横拿才重新进入。竖屏点全屏按钮不会因最初的竖拿姿势立即退出，须先实际横拿后再回转。

宽屏播放页不订阅手机物理方向，也不因窗口横竖变化进出全屏。只有当前仍属于窄屏时，窗口旋转或手机物理方向才改变播放器呈现。全屏继续交接唯一 surface，不重新打开媒体源或 seek，保留进度、倍速、播放意图及信息区浏览状态。

大屏窄分屏使用完整显示屏的横竖变化作为旋转输入：设备横放后分屏窗口可能仍是竖长形，也应响应实际旋转；单纯调整分屏高度不视为转动设备。

## 折叠、展开与分屏

- 599／600 边界、折叠、展开、进入／离开窄分屏只更新布局和方向策略，不将尺寸类别变化视为进入／退出全屏的旋转手势。
- 当前全屏在展开为宽屏后仍保持全屏，并释放旧手机方向限制；随后宽屏旋转不取消全屏。收起时重新采用手机方向能力，保留原全屏选择，后续实际横拿／竖拿才恢复窄屏自动切换。
- 完整显示屏与窗口矩形可能分别送达；同一帧的过渡矩形作为新基线消费，物理方向订阅恢复时的首个姿势也只建立基线，避免从宽屏横向矩形到折叠竖向矩形误退出全屏。
- 真实 Android 厂商的折叠动画、多窗口／兼容模式和 iOS 方向行为仍需设备验收，组件测试不替代这些系统行为。

## 本轮验证

### 应用方向设置（2026-11-16）

- 方向宿主、应用方向设置、完整恢复默认、预测式返回、响应式布局设置和 SQLite 设置仓储共 93 项测试通过，日志：`build/app-orientation-targeted.log`。覆盖手机／平板固定方向优先于全屏、运行中切换及保留子树、回到自动、完整显示尺寸变化、迟到命令采用最新选择、销毁释放、Android／iOS 窄屏设置入口、保存失败回退、重载、恢复默认与旧／非法快照兼容。测试使用本机实际 Flutter 3.50.0／Dart 3.14.0，不代表固定 SDK 3.47.6 下已验证。
- 本次 16 个 Dart 文件定向分析无错误或警告，保留 8 项由新 SDK 引入的 Material 导入弃用提示，`--no-fatal-infos` 下通过；日志：`build/app-orientation-changed-analysis.log`。根应用 `lib/test/integration_test` 及现有平滑滚动源码共 974 个文件格式检查通过，`git diff --check` 通过。
- 已执行 `tool/check.ps1 -SkipPub`，打包边界检查完成后被 SDK 版本约束阻止：本机为 Flutter 3.50.0，仓库要求 3.47.6；日志：`build/app-orientation-check.log`。独立全量分析也未通过，已有独立窗口 `RegularWindowController`／`RegularWindow` 接口及包分析环境与新 SDK 不匹配，日志：`build/app-orientation-analysis.log`。未修改这些无关实现或升级仓库 SDK 约束。
- [独立播放方向测试](../../test/features/playback/app_orientation_playback_test.dart) 另外 4 项通过，覆盖手机／平板两种固定方向不触发自动全屏、手动全屏及返回遵循固定方向、播放源／进度和单一 surface 保留；日志：`build/app-orientation-player-policy.log`。与上述 93 项合计 97 项通过。既有完整 `playback_panel_test.dart` 仍因独立窗口接口编译错误未能运行，日志：`build/app-orientation-playback.log`，未将完整播放面板回归记为通过。
- 本轮未构建安装包、连接设备或测量性能；移动平台实际旋转、固定方向与系统限制仍待实机验收。当前工具集中没有可用的 Dart DTD／热重载工具，未执行热重载。根检查未进入包测试或 mux 原生测试，不计为原生验证通过。

### 原有自动方向规则（2026-10-28）

- 播放面板、窗口服务、方向宿主、导航布局／模式与 DPI 共 487 项专项通过，日志：[最终专项](../../build/validation/adaptive-window-final-targeted.log)。覆盖手机普通页面竖屏、物理旋转全屏与恢复、大屏宽屏旋转不改变全屏、窄分屏实际旋转、599／600 边界、折叠／展开、三倍密度及运行中密度变化、横向安全区，以及导航／页面／单一 surface 保留。已有 DPI 用例同步设置完整 display 与实际窗口，避免模拟屏幕小于测试窗口造成虚假布局变化；导航模式用例同时验证 Android/iOS 的窄屏回退与 Windows 的明确选择。
- `tool/check.ps1 -SkipPub` 最终完整通过：根应用 3343、`bili_api` 492、`bili_player` 96、`bili_danmaku` 116、`bili_mux` 5，共 4052 项；格式、静态分析、打包边界通过。13 项 Windows 符号链接用例因权限不足、10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，未计入通过数。日志：[最终根检查](../../build/validation/adaptive-window-final-check.log)。工作区包含并行播放恢复改动；本任务提交只包含窗口布局、方向策略、文档和对应回归。
- `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 成功，复用本轮先前准备的固定来源 arm64 mux，普通 `lib/main.dart` 入口生成 [Android 开发 Release APK](../../build/development/android-arm64/BiliSail-test-arm64-release.apk)。脚本确认 `dev.bilisail.bilisail.test`／「BiliSail 测试版」、`1.2.3+1`／12301、arm64 AOT、本机原有开发签名及不可调试标记，SHA-256 和元信息同目录保存；未安装到设备。日志：[Android Release](../../build/validation/adaptive-window-android-release.log)。
- 没有连接 Android 设备，也没有可连接的 DTD 调试进程，未执行热重载；Windows 主机未构建 iOS。真实手机／折叠屏旋转、系统动画、兼容窗口、分屏及 iOS 实机行为仍未验收，不从组件测试或 APK 构建推导实机通过；未测性能。
