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
