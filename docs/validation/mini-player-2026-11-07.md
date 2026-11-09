# 迷你小窗与窗口置顶

日期：2026-11-07。对应 [issue #80](https://github.com/CKopoer/BiliSail/issues/80)。

## 样式与入口

- 桌面普通播放页提供「置顶／取消置顶」和「迷你小窗」。Windows 独立播放窗在现有 44 像素标题栏中也提供入口，沿用应用窗口的图标、悬停和关闭样式；其他桌面平台使用共享播放器工具栏。
- 桌面迷你窗移除页面信息和普通标题栏，以黑色画布和画面上下渐变承载少量白色圆角按钮。顶部为置顶、可拖动标题、还原和关闭；底部为播放／暂停和进度条。直播改为「直播中」，不提供 seek。置顶激活色沿用播放器粉色。
- 默认约 400×225，最小 240×135 逻辑像素；边缘自由缩放，不强制修改已保存的宽高比。Linux 另提供右下角缩放手柄，调用 GTK 窗口缩放入口。画面或标题可拖动，双击标题还原；移动鼠标／点击显示控件，静止 3 秒渐隐，Esc 通过原播放快捷键 owner 还原。
- Android 同一入口使用系统画中画，应用只绘制视频和缓冲提示。拖动、缩放、还原、关闭以及媒体会话播放控制由系统提供；不申请悬浮层权限，不自动在 Home 时进入。Android 8.0 以下或设备不提供 PiP 时回退应用内浮窗，系统拒绝进入时提示并还原。
- iOS 使用应用内圆角浮窗，可拖动、通过右下角调整尺寸，保留播放、进度、还原和关闭。浮窗限制在当前窗口安全区内，外部区域可继续浏览播放页内容。本次不声明 iOS 跨应用系统 PiP；切离或关闭拥有它的播放页结束浮窗。
- 听视频模式先退出听视频再进入小窗；全屏先返回普通播放器，再进入迷你窗。

## 所有权与窗口记录

共享 `PlaybackPanel` 保留页面的 `PlaybackSession`、engine 和播放意图。进入前卸载普通 surface，等待一帧后插入小窗 surface；退出先移除小窗并等待一帧，再恢复普通 surface。小窗不重新解析 URL、不创建播放器、不新增播放会话。

进入桌面小窗自动置顶，返回时恢复之前的大小、位置、最大化及置顶状态。原生呈现请求串行执行；退出先保存小窗并还原原生窗口，再恢复普通最小尺寸，避免约束扩大窗口后覆盖小窗记录。隐藏／关闭页面与延迟进入请求相交时仍排队还原。

| 平台 | 独立小窗记录 | 普通窗口保护 |
| --- | --- | --- |
| Windows | `HKCU\Software\BiliSail\WindowGeometry` 的 `miniPlayer`，版本 1 | 保留 HWND／Flutter view，普通几何跟踪跳过小窗，恢复原样式、矩形、最大化和层级 |
| macOS | `UserDefaults` 的 `bilisail.windowGeometry.v1.miniPlayer` | 原 NSWindow，使用浮动层级；几何跟踪排除小窗，恢复标题栏、尺寸及 zoom |
| Linux | 现有 `window-geometry.ini` 的 `miniPlayer` 组 | GTK 保留普通记录，恢复装饰、尺寸和 keep-above；Wayland 位置与置顶请求由合成器裁定 |
| Android／iOS | 系统 PiP／当前浮窗会话 | 不写桌面记录，不改 SQLite 或产品设置 |

桌面位置和尺寸跨重开、换视频和重启复用；移除显示器后限制在现有工作区内。关闭独立桌面小窗走工作区原关闭入口并释放会话；主窗口内的小窗和移动浮窗关闭时暂停并返回播放页。Android PiP 关闭进入后台时暂停，展开回应用保留播放意图。

## 参考与许可

行为参考相邻 PiliPlus `265f879fa85973b4bf885bde2562f1007f1013b8`：`lib/plugin/pl_player/controller.dart` 的桌面模式与位置记忆、`lib/plugin/pl_player/view/view.dart` 的精简控件、`android/app/src/main/java/com/example/piliplus/AndroidHelper.java` 的系统 PiP。

已核对实际 overrides／锁文件：核心来自 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`；视频来自 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`，均不是本项目依赖。本次只参考产品行为，独立实现适配器和 UI，未复制其 GPLv3 应用源码、资源或引入其依赖；继续使用本项目固定媒体 fork。Android API 依据 [官方 PiP 文档](https://developer.android.com/develop/ui/views/picture-in-picture)。

## 验证

```powershell
.\tool\check.ps1
.\tool\test-window-geometry.ps1
.\tool\test-mini-player.ps1
.\tool\test-mini-player.ps1 -DeviceId <adb-device-id>
```

Android 脚本先保留普通入口开发 Release APK，再以同一测试包身份和签名覆盖 Profile fixture；`flutter drive --keep-app-running`，在 `finally` 中恢复普通 Release 及屏幕常亮设置，不卸载、不清数据。

- 为避开共享工作区同期的原生构建和播放器修改，使用基于 `346c5d9` 的独立检出加本任务文件验证；没有把其他任务的构建产物视为本次结果。
- 根应用静态分析通过。播放器／窗口／取消竞态／浮窗布局及日志、下载相关定向复测 **571 项通过，1 项因 Windows 符号链接权限跳过**；Linux 缩放适配另跑 4 项通过。四包测试分别通过 678／212／161／5 项；mux 的 10 项原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不能算原生通过。
- 已执行根检查脚本。共享工作区曾被正在修改的 fvp 接口和无关文件格式阻塞；独立检出的全量根测试在并行构建负载下出现 4 个日志／下载用例超时，该轮终止，随后上述 571 项复测覆盖这些文件并通过。本轮不宣称全量根测试通过。
- Win32 `/W4 /WX` 几何测试通过，含小窗自动置顶、边框尺寸、独立持久化、普通矩形和最大化恢复。实际宿主回归定位并修正了直接写回 `WS_MAXIMIZE` 导致保留迷你矩形的问题。
- Windows x64 Debug 构建、主窗口与独立播放窗的原生 DASH 回归通过：320×180 缩放、置顶切换、暂停意图、播放位置前进和原窗口还原；源代次不变。实际窗口样式／鼠标还原和热重载通过，预览在 `build/validation/mini-player-windows.png`。
- Android 设备 `2211133C`／Android 16 的 Profile 分轨播放、进入系统 PiP、位置前进及展开还原通过；源代次不变。脚本二次完整回归通过并成功覆盖恢复普通 Release 测试版，未卸载或清数据，屏幕常亮恢复原值 `2`。
- 首轮 fixture 漏传原始版本 define，Flutter 将 `+0` 变成 `+1`，导致低版本普通 APK 的恢复被 Android 拒绝。脚本已统一传入 `BILISAIL_RELEASE_VERSION`；为遵守禁止降级／卸载边界，本机通过验证目录的本地 `1.2.8+1` 元信息构建同签名普通 Release，保留安装版本码 `12801` 后恢复成功，未修改仓库版本。后续该设备覆盖测试须使用版本码至少 `12801`。
- 本轮原生播放使用 media_kit；fvp 原生小窗、macOS／Linux／iOS 的构建和设备验收仍未完成。Windows UI Automation 读取期间观察到 Flutter `accessibility_bridge` 的 AXTree pending 节点日志，鼠标操作正常，读屏尚未验收。

## 关闭迷你窗的黑屏与 macOS 释放竞态（2026-11-09）

[issue #102](https://github.com/CKopoer/BiliSail/issues/102) 报告 Windows 1.2.8+5 中，关闭迷你窗时会短暂出现接近全屏的黑色窗口；用户另报告 macOS 关闭小窗闪退。

- Windows 原生 `saveGeometry` 原先先删除 `MiniPlayerWindow`，其析构执行 `Restore()`，恢复普通大小、标题栏及最大化，然后才保存并隐藏。Flutter 播放子树此时正在卸载，因此会暴露放大后的黑色窗口。现在先在小窗标记仍生效时保存普通窗口记录并隐藏，再以 `Retire()` 保存小窗记录、移除 subclass 和 store 指针，关闭时不恢复大小或样式。
- macOS 原先在 `retireGeometry` 以及 `MiniPlaybackPresentation.deinit` 中调用 `restore()`；Flutter 页面的 `_dismissMiniPlayer()` 又独立发出异步还原，没有被纳入窗口退休等待。这使标题栏重建、resize／zoom 与 Flutter view／媒体释放存在交叉。现在关闭只停止跟踪，不修改样式、尺寸和层级；`willClose` 和析构也执行相同的幂等清理。新的 `saveGeometry` 在保留小窗排除标记时采样普通记录，并隐藏小窗、保存小窗记录、撤销监听。当前没有 Mac 崩溃栈，不能把这处已确认的源码竞态等同于设备崩溃模块已确诊。
- 共享窗口服务在播放子树卸载前同步标记关闭，拒绝新进入、还原及置顶请求；已发送的小窗命令排空后才保存几何并继续媒体／原生全屏退出屏障。Cmd+W 的导航清理早于下一帧的关闭判定，所以页面清理中的还原还需等该帧结束，再由服务判断窗口是否仍需保留。浏览历史、切页和明确点击“还原播放页”仍恢复原窗口；独立小窗关闭释放自己的会话。
- Dart 回归新增延迟进入、排队还原、关闭前约束等待、卸载／保存／销毁顺序，以及实际 PlaybackPanel 的小窗关闭按钮、Cmd+W、重复原生关闭、延迟 engine 释放、保留其他会话和再次打开。Win32 测试覆盖普通／最大化窗口关闭后保持隐藏、紧凑尺寸、无标题栏、无悬空 store 指针，以及两个窗口记录分别保存。新增 3 项 Swift XCTest，覆盖显式退休、关闭通知／析构和正常还原；全部使用独立 UserDefaults suite。

验证与边界：

- 基于 `292befa8` 的独立检出只加入本任务文件，`tool/check.ps1` 完整通过：格式、静态分析、脚本／打包边界，以及 **6026** 项 Dart／Flutter 测试（根应用 4767、API 733、播放器 360、弹幕 161、封装 5）。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过；均不计为原生通过。日志：`build/issue-102-isolated-check.log`。源工作区同期的番剧续播修改未纳入该检出，也不属于本次提交。
- `tool/test-window-geometry.ps1` 通过，包括 `/W4 /WX` 编译及上述普通／最大化小窗退休回归；`tool/test-windows-video-dispose.ps1` 的 9 项原生生命周期／渲染队列检查通过。日志分别为 `build/issue-102-native-geometry.log`、`build/issue-102-video-dispose.log`。
- `tool/test-mini-player.ps1` 完成 Windows x64 Debug 构建及 2 项实际 media_kit 分轨播放回归：主窗口和独立播放窗的进入、320×180 缩放、置顶、播放意图／源代次保留和还原，以及独立小窗关闭按钮、surface 卸载和原生窗口销毁。日志：`build/issue-102-native-mini.log`。不据 Debug 结果作性能结论，也未据此声明 fvp 实机回归。
- 两份文档的 241 条本地链接及 `git diff --check` 通过。DTD 未发现可连接的调试应用，热重载请求未成功；Windows 原生结果来自重新构建的 fixture。
- 当前 Windows 主机没有 Swift／Xcode，新增 3 项 XCTest、macOS arm64／x64 构建和实际关闭／重开未执行。系统全屏窗口不在保存阶段主动隐藏，继续交由原有全屏／标签组关闭屏障；Mac 仍需复测普通／最大化／系统全屏、原生合并标签、关闭按钮／Cmd+W、切页、进入小窗中关闭和连续重开，并确认浏览窗继续响应、无遗留音频及崩溃。
