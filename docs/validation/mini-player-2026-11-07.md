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
