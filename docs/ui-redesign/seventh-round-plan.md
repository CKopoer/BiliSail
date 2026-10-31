# 晴湾第七轮调整

2026-10-31 后续按用户要求增加主窗口／播放窗口的跨启动持久化，本文的首显最大化修复继续沿用；当前存储与验证边界见[桌面窗口状态持久化](../validation/window-geometry-persistence.md)。

日期：2026-10-25。依据用户本轮三项反馈，在现有未提交的晴湾界面与双标签实现上增量修改。

## 改动方案

- 设置页参照消息页，将“设置”标题放在顶部，分类标签放在下一行并左对齐，再显示当前分类内容。分类栏由设置页持有，避免外层工作区先显示分类、内容区再重复显示标题。保留分类路由、跟手分页、横向滚轮和各分类独立滚动状态。
- 消息分类标签将“回复我的”简化为“回复”，将带 `@` 图标的“@我的”简化为“我的”；分类身份、图标、未读计数和交互维持既有行为。
- 双标签独立播放窗口恢复时，记忆的最大化状态优先于普通窗口矩形。普通矩形继续保存，供用户主动还原；最大化后关闭、重开或再次激活均保持最大化，主动还原后再记忆普通状态。沿用应用会话内记忆，不新增持久化配置。

## 分工与验收

按用户指定，三个 GPT-6.1 Sol / xhigh 子代理分别负责设置布局、消息标签和窗口恢复。主代理审查集成并统一运行检查、更新验证记录及构建 Windows Release。

自动验证包括设置分类与路由/滚动回归、消息标签回归、窗口 owner/生命周期及最大化恢复回归、`tool/check.ps1 -SkipPub` 和 Windows 构建。Windows 原生几何回归与 Flutter fake 测试分别报告；实机交互、跨显示器、全屏及实际观看由用户在交付产物上验收。不以自动测试或构建成功代替实机验证，Android/macOS 不在本轮构建范围内。

## 窗口问题定位

固定 Flutter 3.47.6 SDK 的 `engine/src/flutter/shell/platform/windows/host_window.cc` 在首帧回调中执行创建时捕获的 `ShowWindow(nCmdShow)`，普通窗口的默认值由同目录 `host_window.h` 定义为 `SW_SHOWNORMAL`。此前应用在 `restoreGeometry` 阶段先恢复普通矩形并调用 `SW_MAXIMIZE`，将窗口提前显示；随后 SDK 首帧再次普通显示，将最大化还原为已保存的矩形。因此单纯调整普通矩形和最大化两次调用的相对顺序不足以解决问题。

本轮 Windows 修复以第一次原生显示消息为边界，在 SDK 应用普通矩形之后完成记忆的最大化，随后解除这次恢复处理；用户主动还原继续有效。准备期窗口保持隐藏，取消、关闭与新 owner 接管不能把尚未展示的默认状态写回记忆。不修改 Flutter SDK 或 Pub 缓存。

## 验证结果

- `tool/check.ps1 -SkipPub` 通过：根应用 2190 项、bili_api 446 项、bili_player 81 项、bili_danmaku 93 项、bili_mux 2 项，共 2812 项通过。五处格式与静态分析、打包边界检查均通过；另有 10 项 mux 原生测试因未设置 `BILI_MUX_LIBRARY` 跳过。日志：`build/seventh-round-check.log`。
- 设置、消息及工作区首轮定向检查 291 项通过，2 项测试断言需随固定标题布局调整；修正为验证内容区滚动条，以及滚动布局稳定后点击大字体控件。设置专项 33 项复测通过，并包含在上述最终全量通过结果中。日志：`build/seventh-round-ui-tests.log`、`build/seventh-round-settings-retest.log`。
- `tool/test-window-geometry.ps1` 通过：纯几何状态测试及真实 Win32 首次显示回归均以 MSVC `/W4 /WX` 编译。后者在隔离桌面创建合成 HWND，直接使用生产适配代码，验证旧时序可复现，以及修复后的最大化重开、正常矩形恢复、主动还原、最小化、准备期关闭、旧 owner 隔离和全屏采样保护。日志：`build/seventh-round-window-geometry.log`。这不是实际 Flutter 窗口和视频播放的实机验收。
- `tool/build-download-mux.ps1 -Target windows-x64` 成功，已准备 Windows 分发所需封装组件；这项资产构建不替代上文跳过的 mux 原生测试。日志：`build/seventh-round-mux-build.log`。

默认 `flutter build windows --release --no-pub` 已编译到链接阶段，但默认 Release 中的 `bilisail.exe` 正被用户运行，导致 LNK1104。保留该进程，改用现有 Flutter 生成配置与同一 CMake `Release / INSTALL` 流程，成功输出到 `build/windows-seventh-round/x64/runner/Release`。独立构建使用本地依赖归档缓存并继续执行原有哈希校验，复用现有 NuGet 工具及固定版本包；不修改 SDK、依赖版本或全局 Flutter 配置。

最终产物为 `build/windows-seventh-round/x64/runner/Release/bilisail.exe`（源码版本 `1.1.1+7`），需保留整个 Release 目录。已核验安装清单的 62 个文件、关键 DLL 和资源非空、libmpv 固定 SHA-256、mux 与本轮预构建资产一致、Dart AOT 与本轮输出一致。构建日志：`build/seventh-round-windows-isolated.log`；产物哈希与清单核验：`build/seventh-round-artifact-verification.json`。第三方 WebView 的 CMake/编译警告未阻断构建。

另已通过 149 个本地文档链接检查、PowerShell 语法检查及 `git diff --check`；保留原有未提交修改，本轮未创建提交。

当前没有运行中的 Dart 调试进程，无法执行热重载；本轮通过完整 Release 重建应用改动。未启动生产客户端，未执行 Android/macOS 构建、跨显示器或性能测量。

建议实机按顺序验证：调整播放窗大小和位置 → 最大化 → 关闭并重新打开媒体，应保持最大化；主动还原应回到之前的普通矩形；还原后再次关闭重开应保持普通窗口。设置页同时检查分类切换、滚动与窄窗口下的标题和分类栏位置。

## 追加：搜索页工具精简

同日按用户追加反馈，搜索结果页也移除“观看历史、下载、设置”三个快捷按钮，保留账号头像、关键词输入、搜索分类及既有返回入口。相应功能继续通过工作区一级导航和“我的”页面访问。更新现有宽窄布局断言与从搜索返回设置的导航测试。

追加修改后的 `tool/check.ps1 -SkipPub` 再次通过：2812 项通过，10 项 mux 原生测试仍按未配置测试库跳过；格式、分析和打包边界检查通过。日志：`build/seventh-round-search-check.log`。同一独立目录的 Windows Release 增量构建完成，安装清单文件齐全，已确认 AOT 更新且与当前构建一致；日志及产物核验分别为 `build/seventh-round-search-windows.log`、`build/seventh-round-search-artifact-verification.json`。实机视觉仍待用户确认。
