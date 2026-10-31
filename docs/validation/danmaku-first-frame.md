# 视频首帧与弹幕同步

日期：2026-10-31。

## 原因与实现

原共享播放面板仅按页面活动和弹幕设置挂载弹幕层。点播弹幕虽在媒体打开后加载，但固定 media-kit 的原生首帧等待与 Flutter 视频控件显示还有时间差：原生输出初始化可报告 1×1 纹理，`Video` 还要等待播放器的 width／height 通知并重建。因此加载中的黑底可能先出现弹幕；直播消息也能早于视频加载完成到达。

- [视频输出](../../packages/bili_player/lib/src/media_kit_video_output.dart) 实现可选的 [VideoFrameReadiness](../../packages/bili_player/lib/src/video_composition.dart)，同时检查当前控制器的首帧信号、纹理 ID、非初始化占位纹理和正的视频显示尺寸。条件满足后等待当前 Flutter 帧结束，再发布局部就绪通知。
- 清除／重绑输出时同步复位，取消旧尺寸和纹理订阅；revision 隔离迟到首帧 Future 与已排队的帧后回调，释放时清理通知对象。不轮询、不新增固定延迟、不更改原生打开预算。
- [共享播放面板](../../lib/features/playback/presentation/playback_panel.dart) 先等待当前媒体准备完成，再按输出就绪信号挂载点播或自定义直播弹幕层。普通／全屏、视频／影视／直播／离线播放使用同一路径；暂停和已有画面的正常缓冲不隐藏弹幕。听视频沿用音频界面。
- 保留唯一 engine／surface、确认媒体位置和直播到达时钟、原弹幕 Ticker 与设置。不修改依赖、Pub 缓存、native 补丁、账号或数据结构。

该信号表达当前 Flutter 视频控件已具备显示条件并完成一次帧绘制，不是屏幕像素回读或三端人工观感验收。

## 回归

- [播放器输出测试](../../packages/bili_player/test/media_kit_video_output_test.dart) 新增 4 项，覆盖尺寸／纹理／首帧分别迟到、1×1 初始化纹理、纹理失效恢复、换源后的旧通知与帧后回调。
- [播放面板测试](../../test/features/playback/playback_panel_test.dart) 新增 7 项，覆盖视频／影视／直播／离线、默认／自定义弹幕层、加载期间的旧就绪信号、画面就绪后显示、暂停／缓冲、普通转全屏及全屏重载；检查不新增播放器或 surface。
- [原生首帧集成测试](../../integration_test/native_video_readiness_test.dart) 增加真实本地分轨／progressive 暂停打开、Texture 挂载先于前景就绪、停止后复位与再次打开的验证。按 Flutter 集成测试技能沿用现有 binding 和 fixture，不连接真实账号。

## 本轮验证

- 根检查脚本的格式、静态分析与打包边界通过。全仓测试启动曾遇到同期根测试占用 `build/native_assets/windows/sqlite3.dll`，保留该进程并等待结束后，分别运行同一脚本的 RootTests／PackageTests 阶段完成检查。
- 根应用 3,702 项、API 498 项、播放器 105 项、弹幕 145 项、mux 5 项，共 **4,455 项通过**。根应用另有 13 项按原条件跳过；mux 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。日志：`build/danmaku-first-frame-check.log`（格式／分析／边界）、`build/danmaku-first-frame-root-check.log`、`build/danmaku-first-frame-package-check.log`。
- Windows mux 组件按 `tool/build-download-mux.ps1 -Target windows-x64` 重新构建成功；日志 `build/danmaku-first-frame-mux-build.log`。
- Windows Debug 测试入口构建成功，`flutter test --no-pub integration_test/native_video_readiness_test.dart -d windows` 的 6 项原生用例全部通过，包括新增首帧前景顺序，以及既有坏视频拒绝、分轨恢复、暂停续播、seek 和纯音频回归。日志 `build/danmaku-first-frame-native.log`。集成测试首轮在通知回调直接调用 `expect` 触发测试框架异步保护，已调整为回调采样、等待后断言，并重新完整通过；最终测试文件格式与定向分析也通过。
- 通过 DTD 连接本次 Windows 调试实例，最终代码热重载成功，随后退出本次测试实例。普通入口 Release 未重建。
- 三份修改文档的相对链接与本任务 `git diff --check` 通过；提交仅包含本任务文件，保留同期修改。

Android／macOS 本轮未构建、未实机验收；未进行性能测量或线上 CDN 长时间播放验收。
