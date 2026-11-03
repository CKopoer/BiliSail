# 弹幕发送色板与样式面板

日期：2026-10-31。

## 范围与来源

只读参考相邻 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 [发送面板](../../../PiliPlus/lib/pages/video/send_danmaku/view.dart) 与 [RGB 选择器](../../../PiliPlus/lib/pages/setting/slide_color_picker.dart)。其应用为 GPLv3；本次参考普通 RGB 预设值、自定义色值及颜色预览的交互职责，独立实现 Flutter 组件，没有复制应用源码、资源或新增依赖。参考工程锁定 `bggRGjQaUbCoE/canvas_danmaku@275046d8647a6a26cba1d0dadb9e28688cb3dbf1`，与本应用的固定 Predidit 依赖分别处理，没有修改相邻仓库或锁文件。

补齐参考面板的 14 种普通颜色，保留原有粉色 `FF6699`、金色 `FFD700`、蓝色 `00A1D6`，共 17 色。自定义支持六位十六进制输入与 R／G／B 滑块，范围为 `000000`–`FFFFFF`，只在完整合法时应用。PiliPlus 的会员渐变需要额外的 `colorful` 协议、权限与绘制适配，本轮范围为普通 RGB 发送，没有加入会员渐变入口。

## 交互与适配

2026-11-03 已另行补齐会员渐变显示、发送入口、权限与成功回显；上文“本轮范围”为 10 月 31 日的历史范围，现行能力及验证边界见 [会员彩色弹幕](vip-danmaku-2026-11-03.md)。

- 视频与影视、普通与全屏继续共用 [样式按钮](../../lib/shared/ui/danmaku_send_style_button.dart) 和 [面板](../../lib/shared/ui/danmaku_send_style_panel.dart)。2026-11-01 按用户后续要求改为全局保存，`PlaybackSession` 同步当前偏好供发送使用，详见下文。
- 一次打开可同时调整滚动／顶部／底部和颜色，深浅两种背景预览当前颜色；点击“完成”一次性应用。关闭、取消、遮罩或 Escape 丢弃草稿，不改变已有设置，也不发送弹幕。打开／取消不清除发送栏文字。
- 面板按当前窗口可用空间适配：宽度小于 600 时靠底，其他情况居中，内容最大宽度 440。使用现有 `showAppDialog`，保持当前 View 的弹层归属、模态快捷键隔离和焦点循环，不创建额外原生窗口。
- 色块为 44×44，提供名称提示、选中边框／勾选与读屏颜色值。发送栏最小高度调整为 44，按钮同时显示颜色圆点，深色选项仍有可辨识的按钮图形。
- 模式与色块自动换行，全部内容可滚动，遵守 SafeArea 和键盘避让；短横屏、大字号和分屏可滚动到确认按钮。自定义输入未完成时禁止应用，收起自定义编辑时回到最近合法值；键盘 Enter 可确认合法色值。重复点击入口只打开一个面板。

发送 API、账号／源隔离、确认成功后回显和未知结果不重试规则沿用 [发送链路验证](danmaku-display-area.md#发送链路复查)，色值仍为无 alpha 的 24 位 RGB。

## 验证

- [组件回归](../../test/shared/ui/danmaku_send_style_button_test.dart) 覆盖预设和旧色、确认／取消／Escape／遮罩、重复打开、禁用、完整／不完整色值、带 `#` 粘贴、滑块与重新打开。
- Android／iOS／Windows／macOS／Linux 的平台配置均覆盖 320×640、640×280、1280×800 和 2 倍文字，加入键盘 inset 后检查可达的自定义输入、确认和无溢出。这些是 Widget 配置测试，不代表各平台设备验收。
- [发送回归](../../test/features/video/video_danmaku_send_test.dart) 覆盖旧色、新增红／绿／深灰与三种模式，自定义 `000001` 经过真实控制器／Repository／API 后仍为十进制 `1`；打开面板保留草稿，确认样式不触发网络写入。
- 新增 [Widget 预览入口](../../lib/shared/ui/previews/danmaku_send_style_preview.dart)，包含手机、桌面和大字号。当前 SDK 的 CLI previewer 将目录 `bili-lite` 生成为 `bili_lite` path 依赖，与实际包名 `bilisail` 不一致而启动失败，未修改工程名或 SDK 来绕过，改用 Windows 原生合成预览检查。
- 定向 62 项测试通过，日志为 `artifacts/danmaku-style-targeted.log`。全仓 `tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界及测试：根应用 3747、API 498、播放器 105、弹幕 145、mux 5；根应用 13 项和未配置 `BILI_MUX_LIBRARY` 的 10 项 mux 原生用例跳过。计数包含同期其他任务的工作区修改，日志为 `artifacts/danmaku-style-check.log`。
- Windows Debug 原生合成预览、热重载通过，工具报告无运行时错误，实际检查普通／自定义／大字号画面，截图为 `artifacts/danmaku-style-picker-windows.png`。预览结束后，普通入口 `lib/main.dart` 的 Windows Debug 构建通过，日志为 `artifacts/danmaku-style-normal-build.log`。

本轮没有发布真实测试弹幕。Android／Apple／Linux 原生输入法、触摸手感与读屏设备验收仍待执行。

## Windows 格式确认丢失修复（2026-11-01，#52）

[问题 #52](https://github.com/CKopoer/BiliSail/issues/52) 报告确认发送格式后再次打开恢复默认，发送仍使用默认值。根因是样式面板没有参与播放器现有的菜单显隐保护：面板打开后，点击模式等待 5 秒，或动态模式移出播放器／等待 2.5 秒，控件淡出并销毁发送栏。面板本身仍在 Navigator 上显示，但确认回调发现原样式按钮已经卸载，丢弃了选择。

共享控件新增 [PlayerControlsMenuScope](../../lib/shared/ui/player_controls_menu_scope.dart)，将发送栏内的样式面板接入播放器同一菜单计数。打开面板前暂停控件自动隐藏，确认、取消、关闭按钮、遮罩及 Escape 返回后释放保护，恢复原来的隐藏规则。视频与影视、普通与全屏沿用同一入口；发送样式仍由当前 `PlaybackSession` 持有，点击“完成”提交，其他关闭方式丢弃未确认编辑。

验证：

- [播放器组件回归](../../test/features/playback/playback_panel_test.dart) 新增点击／动态 × 普通／全屏四项测试，修复前四项均复现默认白色滚动样式未改变，修复后全部通过。测试包含面板打开后鼠标移出并等待 6 秒、确认顶部粉色、重新打开、取消新颜色、真实发送控制器参数，以及面板关闭后控件再次自动隐藏。
- [样式面板回归](../../test/shared/ui/danmaku_send_style_button_test.dart) 验证确认及四种取消方式的菜单计数配对；连同视频发送／输入框和影视发送回归，共 63 项通过。
- `tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界及 4810 项测试（根应用 3980、API 541、播放器 131、弹幕 153、mux 5）。根应用按既有条件跳过 13 项；未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过，不属于原生验证通过。日志：`artifacts/issue-52/check.log`。本文相对链接和 `git diff --check` 通过。
- 按用户要求未构建、未实机测试、未发送真实弹幕；没有活动调试应用可热重载。设备交互与真实账号发送效果由后续构建验收。

## 全局记忆（2026-11-01）

发送位置和颜色改为 `AppSettings.danmakuSendStyle` 全局偏好，不按账号或视频隔离。点击“完成”后通过 `SettingsController` 的串行写入队列保存；新视频、影视剧集、新播放标签与应用重启读取同一选择。取消、关闭、遮罩或 Escape 继续丢弃未确认编辑。恢复默认设置会恢复白色滚动弹幕。

`preferences.v1` 快照版本从 34 升至 35，新增整数 `danmakuSendMode`／`danmakuSendColor`，SQLite 表结构版本仍为 3。缺失／非法字段分别回退到滚动 `1`／白色 `0xFFFFFF`，保留其他有效偏好；颜色 `000000`、`000001` 等仍按完整 24 位 RGB 保存。

共享样式按钮等待保存结果，失败时提示“弹幕样式保存失败，请重试”，沿用设置控制器的已保存值回退。多个页面先后确认时，较早完成的回调读取最新全局选择，不用旧草稿覆盖新值。普通／全屏和菜单显隐保护沿用 #52 的修复。

回归覆盖设置默认值／非法字段／复制、旧快照兼容与数据库重载、并发偏好写入／保存失败／恢复默认、两个播放会话同步、切视频和重建设置容器后的恢复，以及视频与影视的保存／发送路径。按用户要求仍不构建、不实机测试、不发送真实弹幕。

为隔离同期搜索功能修改，使用提交 `25934d6` 加本次文件的临时工作区验证。`tool/check.ps1` 的格式、静态分析及打包边界检查通过；测试首次因 SQLite 下载 TLS 握手失败中断，复用与上游 SHA-256 一致的本地缓存后，分别重跑 `-SkipPub -Stage RootTests` 和 `-SkipPub -Stage PackageTests`，共 4816 项通过（根应用 3986、API 541、播放器 131、弹幕 153、mux 5）。根应用 13 项条件跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。未修改 Pub 缓存或绕过哈希校验。主工作区的四项播放器样式回归随后也通过。

日志保存到 `artifacts/issue-52-global-memory/` 下的 `lint.log`、`root-tests.log` 和 `package-tests.log`；首次下载失败记录保留在 `setup.log`。本文相对链接与 `git diff --check` 通过。
