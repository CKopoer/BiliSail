# 近期三项界面修复与发布验收

日期：2026-10-09。验收源码为 `ac00f87`，包含以下三个连续提交；本轮不修改修复实现。版本构建号由 `0.5.1+4` 递增为 `0.5.1+5`。

| 提交 | 对话要求 | 验收结果 |
| --- | --- | --- |
| `87a3f39` | 顶部子标签跟随双向分页居中；全部标签可见时保持原位 | 共享标签栏在 Windows Flutter 引擎中通过双向逐帧、首尾、回弹、取消、RTL、宽屏及缩放回归 |
| `19e71ac` | 点击模式悬停控件不隐藏；播放器内持续移动也不隐藏 | 原生 MediaKit 播放器在 320／1200 逻辑像素布局通过持续移动、底栏／标题／小窗按钮悬停、移开后隐藏、隐藏后不因移动显示及播放意图／源代次保留检查 |
| `ac00f87` | 首页滑动时封面不闪空；检查其他支持滑动的子标签 | 首页八个频道和用户主页投稿／动态／收藏的往返、取消及缓存开关回归通过；设置分页由全量 widget 回归覆盖 |

相关行为与实现说明见 [顶部标签](single-page-navigation.md)、[播放控件](responsive-player.md) 和 [图片缓存](feed-scroll-image-cache.md)。

## 自动检查与原生运行

- `tool/check.ps1 -EnforceLockfile` 通过格式、静态分析及 1939 项离线测试：根应用 1504、API 336、播放器 32、弹幕 65、封装包 2。封装包另有 7 项需要 `BILI_MUX_LIBRARY` 的原生合并测试按配置跳过。日志：`build/recent-three-check.log`。
- 临时 integration_test 入口复用首页封面、用户主页分页和共享标签栏的 57 项现有测试，在 Windows 实际 Flutter 引擎中执行；仓储与图片使用 fake 和生成 PNG，不依赖真实账号或在线图片。首次 56 项通过，一项在截图观察触发语义句柄变化后收尾报错；停止窗口观察后该项独立复跑通过。日志：`build/recent-three-native-swipes.log`、`build/recent-three-native-swipes-retry.log`。
- 两项原生控件回归使用本地分轨素材并确认两轨解码，采用与现有 Windows 原生播放测试一致的 `fullyLive` 绘帧配置，均通过。首次临时脚手架采用默认绘帧策略时进程退出；调整后未再复现，但未据此声称定位或修复了该退出的根因。日志：`build/recent-three-native-controls.log`、`build/recent-three-native-controls-live.log`。
- 现有 `windows_playback_test.dart` 的 `Windows native DASH pair: headers, redirects, ranges, seek and lifecycle` 单独通过，确认音视频解码、两轨 Range、本机 HTTP 重定向和播放生命周期。日志：`build/recent-three-native-dash.log`。
- 临时入口已从应用源码移除，保留于本地忽略目录 `build/recent-three-probes/`；重跑时复制回 `integration_test/` 对应文件名，使用 `flutter test <入口> -d windows`。控件入口需将 `BILI_TEST_MEDIA_DIR` 指向 `test/fixtures/media` 的绝对路径。

## 构建与验证边界

`flutter build windows --release -t lib/main.dart` 成功，构建版本为 `0.5.1+5`，耗时 46.7 秒。完整产物位于 `build/windows/x64/runner/Release/`，已按完整进程路径启动本次 `bilisail.exe`，确认首页和封面正常显示；没有用已安装的旧版本代替验收。锁文件哈希在检查与构建后保持不变。

| 文件 | SHA-256 |
| --- | --- |
| `pubspec.lock` | `6660075CF5A6AB0ADAE187CD103D289659D879F99F3B793C3CD19B93CCA02549` |
| `Release/bilisail.exe` | `4C781CCED5ACF545083F43CD9FFB09103D668B5C6047BBFE8ABE03B604797421` |
| `Release/data/app.so` | `DC024798AF0FC82A11B18CC97947DA567EB1F0AB960E313E90F723C940792E48` |

构建仍输出既有的第三方 WebView 插件 CMake CMP0175 开发警告，未影响结果。日志：`build/recent-three-release-build.log`。

本轮在 Windows 主机验证共享界面与本地原生媒体。触摸滑动由 Flutter 测试指针驱动；未进行 Android／macOS 本机构建或移动端实机手势验收，未执行真实账号发送、投币、点赞等操作，未测量性能或长期播放稳定性。

Release 工作流沿用仓库现有三端构建与预览草稿策略；触发工作流不代表远端构建或公开发布已完成。
