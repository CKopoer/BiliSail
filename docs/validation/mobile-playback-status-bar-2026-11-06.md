# 移动端播放页黑色状态栏

日期：2026-11-06。

## 修改

- Android／iOS 的视频、影视、直播和离线播放页共用工作区的[状态栏适配](../../lib/core/presentation/mobile_playback_status_bar.dart)。在既有顶部安全区绘制纯黑背景，并提供白色状态栏图标；Android edge-to-edge 下由 Flutter 实际绘制底色。
- [工作区外壳](../../lib/app/shell.dart)按当前页面身份启用；进入 UP 空间或返回浏览页时恢复原页面背景和图标策略。保留既有 SafeArea、底部导航栏策略和播放会话所有权，桌面平台保持原行为。
- 全屏显隐与方向仍由既有窗口服务管理，本次没有修改原生工程或播放器。

## 验证

- `flutter test --no-pub test/core/presentation/mobile_playback_status_bar_test.dart test/core/presentation/android_system_ui_test.dart`：11 项通过。
- 新增[组件回归](../../test/core/presentation/mobile_playback_status_bar_test.dart)覆盖 Android／iOS、浅／深主题、四类播放路由、390×844 与 900×600 布局，读取实际顶部绘制像素与平台通道图标参数，并验证保留的播放页不影响 UP 空间和首页。既有 Android 系统栏测试同时通过。
- 三个改动 Dart 文件定向 `flutter analyze --no-pub` 通过。
- 按用户要求不构建、不安装、不进行实机或性能测试；Android／iOS 系统实际合成、刘海／挖孔屏和全屏往返由用户后续验收。未发现运行中的 DTD／调试应用，无法热重载。

## 2026-11-07：窄屏全屏旋转闪白修复

- 原先先请求系统横屏和隐藏系统栏，再显示全屏路由；原生过渡期间仍可能露出浅色工作区。移动端现在先完成黑色全屏路由的一帧绘制，再请求方向和系统栏变化；保留原先普通画面先卸载、共享唯一会话以及按 owner 串行取消／退出的规则。桌面窗口沿用原来的全屏调用顺序。
- 普通／全屏共用状态栏适配；隐藏系统栏导致顶部 padding 为零时，保留顶部 1 个逻辑像素的黑色样式区域，避免旋转或临时显示系统栏时回落到浅色样式。此区域不消费安全区，不改变底部系统栏。
- 黑色状态区仅适用于 Android／iOS 且显示屏逻辑短边小于 600 的设备，复用 `WindowSizePolicy`；手机横屏继续启用，平板及其窄分屏窗口恢复主题背景。宽屏全屏播放器沿用既有黑色画面。
- 监听只改变显示屏、未改变窗口尺寸的 metrics 更新；宽窄切换仅增删顶部覆盖层，保留播放器子树。状态栏只订阅 padding，键盘动画不会额外重建弹幕输入组件；既有折叠屏单 surface、输入焦点和草稿回归通过。
- [播放面板回归](../../test/features/playback/playback_panel_test.dart)通过延迟原生全屏请求复现过渡，验证请求完成前黑色全屏路由已经绘制、Android／iOS 浅深主题的顶部实际像素、零 padding 时的状态栏样式、临时系统栏重新显示以及单一 surface／源与暂停意图保留：新增 4 项通过。[状态栏回归](../../test/core/presentation/mobile_playback_status_bar_test.dart)补充手机横屏、600 短边宽屏、平板窄分屏和展开后恢复浏览页的检查。
- 根检查按阶段验证：构建边界检查、格式检查和全仓静态分析通过；`tool/check.ps1 -SkipPub -Stage RootTests`：4,572 项通过，13 项 Windows 符号链接条件用例跳过；`tool/check.ps1 -SkipPub -Stage PackageTests`：1,056 项通过。未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过，不计为原生通过。文档相对链接和 `git diff --check` 通过。
- Android 设备 `950c21ca`（2211133C）：普通入口 arm64 Release 与 Profile fixture 构建成功，既有[全屏／手势真机回归](../../integration_test/android_fullscreen_orientation_test.dart)通过，覆盖原生画面变换、同一源、视频／直播横竖屏全屏往返及亮度／音量恢复。流程沿用 `tool/test-android-player-gestures.ps1` 的临时副本，fixture 额外传入 `--dart-define=BILISAIL_RELEASE_VERSION=1.2.7+0`，使其与恢复包的 versionCode 同为 12700；原脚本未修改。结果保存在 `build/validation/android-status-bar-final/results.json`。测试统一使用 `dev.bilisail.bilisail.test`，结束后覆盖恢复普通入口 Release，未卸载／清数据，临时常亮和 adb reverse 已恢复。
- 本机为 Windows，iOS 构建／实机、宽屏 Android／iOS 实机及原生转场逐帧合成仍未验收；自动像素回归不代替这些验收。本轮 Profile 仅做功能验证，未测性能。未发现可连接的 DTD 调试应用，无法热重载。

## 2026-11-07：退出全屏恢复竖屏时顶部闪白

- 用户反馈前一轮修复后，退出全屏仍在竖屏顶部闪白。原退出流程先 pop 全屏路由，再在 `finally` 中恢复方向与系统栏；底层浅色工作区会在此期间露出。方向／系统栏的平台方法完成，也不代表竖屏尺寸、状态栏 inset 与对应 Flutter 帧已经到达。
- [共享播放面板](../../lib/features/playback/presentation/playback_panel.dart)统一处理按钮、中心下滑、Esc、物理旋转与系统返回：退出期间保留黑色全屏路由，先恢复系统呈现；窄屏锁定竖屏浏览时，等待实际竖屏和顶部 inset，再等待对应一帧绘制，之后才移除全屏路由。路由拦截同样涵盖直接 pop，并保留页内 local history 优先返回。
- 窄屏退出准备阶段先绘制黑色覆盖层，保留其后的原视频 surface；即便视频本身是全白画面，系统提前显示状态栏、Flutter 还没收到 inset 时也不会露出亮色帧。覆盖层只用于窄屏全屏退出，不改变宽屏状态栏。
- 退出请求单飞，准备期间停止自动方向更新，避免晚到的视频尺寸重新进入横屏。沿用播放 owner 的串行命令与唯一 surface，普通／全屏不重新打开媒体，不改变播放／暂停意图；页面关闭或隐藏仍直接清理自己的呈现，不覆盖接下来的浏览页。
- 系统拒绝方向／inset 更新时最多等待 2 秒再退出；隐藏／销毁提前取消等待并释放 Timer。宽屏普通播放页的主题背景和不强制旋转策略保留。
- [组件回归](../../test/features/playback/playback_panel_test.dart)新增 19 项：Android／iOS、浅／深主题、按钮／系统返回／Esc／中心下滑共 16 项，分别延迟原生回复、竖屏尺寸和顶部 inset，验证中间帧及最终竖屏帧的黑色像素、重复返回、单源和单 surface；另 3 项验证超时、页面隐藏和销毁。定向回归与既有键盘输入、折叠屏、焦点释放用例通过。
- [Android 真机回归](../../integration_test/android_fullscreen_orientation_test.dart)增加真实原生方向与系统栏恢复的覆盖检查，分别走按钮和系统返回，验证 native restore 开始时全屏页面仍在，并读取竖屏状态区实际 Flutter 绘制像素。该断言区别于前一轮仅检查最终方向的烟测。
- 验证使用 `build/statusbar-exit-worktree/` 隔离检出，避免与主工作区并发测试争用原生 DLL；三个改动代码文件与主工作区逐文件 SHA-256 一致。根检查的构建边界／格式及五份锁文件的 `--enforce-lockfile` 解析通过；最终全仓静态分析无问题，根应用 4,591 项、四个子包 1,056 项离线测试通过。13 项 Windows 符号链接条件用例、10 项未配置 `BILI_MUX_LIBRARY` 的 mux 原生用例跳过，不计为原生通过。
- Android `950c21ca`（2211133C）最终 Profile 真机回归全部通过，结果见 `build/statusbar-exit-worktree/build/validation/android-statusbar-exit/results.json`：`fullscreenExit` 中的退出前覆盖、竖屏黑色状态区和普通页黑色状态区断言均通过。普通 Release／fixture 均为开发包 `dev.bilisail.bilisail.test`、版本 `1.2.8+0`，fixture 补传同版本的 `BILISAIL_RELEASE_VERSION`；结束后覆盖恢复普通入口 Release，常亮与 adb reverse 已恢复，未卸载或清数据。最终普通 APK、SHA-256 和元信息同步到根工作区 `build/development/android-arm64/`。
- iOS 和宽屏设备保留组件回归覆盖，未进行本轮实机验证；没有测量性能，也未采集原生合成转场的逐帧视频。真机像素断言读取 Flutter 绘制结果。未发现可连接的 DTD 调试应用，无法热重载。
