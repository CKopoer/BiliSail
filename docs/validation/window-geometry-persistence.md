# 桌面窗口状态持久化

日期：2026-10-31。按用户要求，主浏览窗口与独立播放窗口分别记住普通窗口大小、屏幕位置和最大化状态，下次启动或重开对应窗口时恢复。取代第六／七轮界面调整中的“仅应用会话内记忆”限制。

## 行为与存储边界

- 窗口状态属于本机呈现状态，跨账号共用；主窗口与播放窗口使用不同记录。账号切换、恢复产品设置不清除此记录，不改变导航和播放会话所有权。
- 保存最大化前的普通矩形和独立最大化标记。最小化不会成为下一次启动状态，全屏不会覆盖普通矩形，也不会在下次启动时自动全屏。
- 缺失、损坏或未知版本的记录回退到原有默认尺寸。显示器被移除、工作区改变后，将保存的矩形限制在最近显示器的可见工作区内。
- Windows 在首次 Flutter surface 创建前恢复主窗口矩形，沿用播放窗既有首显最大化处理。原生监听移动／缩放／最大化，拖动中用 250 ms 防抖保存，关闭、释放和退出时补存；旧播放 view/owner 不能覆盖当前记录，首帧前取消不落盘。
- macOS 沿用 Cocoa 的普通 frame／zoom 语义与全屏过渡保护，主窗口和播放窗口共用原生跟踪器；打包 smoke 不读取或写入用户窗口状态。
- Linux 当前只有主窗口；GTK 保存尺寸和最大化，X11 可请求恢复位置。Wayland 的绝对位置由合成器决定，不能保证接受应用的位置请求。Android／iOS 沿用系统窗口与旋转策略，不引入桌面窗口记录。

采用原生存储是为了在 Flutter 首帧和业务数据库打开前应用几何状态，并在引擎销毁时同步保存。这不是新增产品设置，不改 `AppSettings`、SQLite schema 或凭据存储。

| 平台 | 本机存储 | 格式 |
| --- | --- | --- |
| Windows | `HKCU\Software\BiliSail\WindowGeometry`，`main`／`playback` | 每个角色一个版本 1 的二进制记录，普通屏幕矩形（物理像素）与最大化标记一起写入 |
| macOS | 当前应用的 `UserDefaults`，`bilisail.windowGeometry.v1.main`／`playback` | 版本 1 字典，普通 Cocoa frame（桌面点）与 zoom 标记 |
| Linux | 用户配置目录下 `dev.bilisail.bilisail/window-geometry.ini` | 版本 1 的 `main` 记录，GTK 位置／尺寸与最大化标记 |

## 验证

- `tool/test-window-geometry.ps1` 通过：MSVC `/W4 /WX` 编译纯状态测试和真实 Win32 隔离桌面测试。除原有首显／最大化／主动还原／工作区／全屏／owner 回归，增加自动缩放防抖保存、销毁前补存、两个角色隔离、最大化后立即最小化保存、新实例恢复最大化及普通矩形、首帧前取消、损坏记录回退，以及另起进程读取两个角色记录。测试只写临时注册表子键并清理，不修改用户窗口状态。日志：`build/validation/window-geometry-2026-10-31/native-geometry.log`。
- Windows Release 构建通过，入口为 `build/windows/x64/runner/Release/bilisail.exe`；分发仍须保留整个 Release 目录。日志：`build/validation/window-geometry-2026-10-31/windows-build.log`。
- `tool/check.ps1 -SkipPub` 通过：根应用 3774、bili_api 499、bili_player 105、bili_danmaku 145、bili_mux 5 项，共 4528 项测试通过；格式、静态分析与打包边界检查通过。根测试按配置跳过 13 项，另有 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。日志：`build/validation/window-geometry-2026-10-31/check.log`。
- 6 份改动文档的 273 个本地链接及 `git diff --check` 通过。

本轮未操作用户运行中的正式客户端；隔离 HWND 回归不是完整 Flutter 客户端的拖动、跨屏 DPI 与播放验收。macOS／Linux 尚未构建或实机验收；当前 Windows 主机没有 Apple 工具链，WSL 未配置 GTK 开发环境。未进行性能测量。本次应用逻辑未改 Dart，不需要热重载；原生窗口改动由完整 Windows Release 重建验证。

## 窄屏播放窗重开首帧尺寸（2026-11-01）

用户反馈双标签播放窗保存为窄屏后，关闭并打开另一个视频时页面显示异常。Windows 的普通窗口恢复原生矩形后，Flutter view 的尺寸通知可能尚未更新；此前 `restoreGeometry` 只为首次最大化返回目标客户区尺寸，普通窗口首帧仍可能使用创建时的默认宽度。首帧内容定尺寸与保护保存外框的原生钩子因此可能使用不同尺寸。

原生恢复现在也为普通窗口返回实际客户区的物理尺寸，由现有 Dart 适配器换算成逻辑尺寸布局首帧。首次最大化仍返回显示器工作区尺寸；首显或取消后不再提供初始尺寸覆盖，后续用户缩放继续使用实际 view 约束。Dart 只同步接口注释，没有修改可执行逻辑。

- 新增隔离 Win32 回归，分别保存 460／1100 物理像素宽的普通窗口，各连续重开两次，检查恢复后仍隐藏、首帧尺寸等于客户区而非默认宽度或外框、SDK 初始内容定尺寸不改变保存外框，以及首显／释放后清除初始覆盖。旧实现在“普通窗口未返回初始客户区尺寸”断言失败，日志为 `build/narrow-window-before.log`。
- `tool/test-window-geometry.ps1` 通过，包含新增窄／宽屏重开及既有最大化、还原、全屏、取消、旧 owner 隔离和持久化回归；日志为 `build/narrow-window-after.log`。
- 窗口服务、独立窗口生命周期、顶部栏、播放窗口与双 view 工作区的 64 项定向 Flutter 测试通过；日志为 `build/narrow-window-targeted-tests.log`。
- `tool/check.ps1 -SkipPub -Stage Lint` 的格式、静态分析和打包边界检查通过，`git diff --check` 通过；日志为 `build/narrow-window-lint.log`。未运行全量根应用／子包测试。

本次按用户要求完成相关单元／组件测试，不构建客户端、不进行设备操作或性能测量；完整 Flutter 窄屏重开后的实际画面及跨屏 DPI 留待用户构建验收。原生回归运行于隔离桌面，不读写用户的窗口状态记录。
