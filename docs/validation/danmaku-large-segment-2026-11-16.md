# 密集视频弹幕分段被误判为不可用

日期：2026-11-16。用户要求修复后通过单元测试并提交，不构建；播放界面与实机验收由用户后续完成。

## 原因与在线证据

用户报告 [BV1DRHU6LELy](https://www.bilibili.com/video/BV1DRHU6LELy) 显示“弹幕暂时不可用，视频播放不受影响”。公开详情接口确认该视频只有一个分 P，`cid=42560392051`，时长 257 秒。

只读请求 `GET https://api.bilibili.com/x/v2/dm/web/seg.so`，参数为 `type=1`、`oid=42560392051`、`segment_index=1`：

| 上下文 | HTTP | 响应大小 | 元素数 | 修复前结果 |
| --- | --- | --- | --- | --- |
| 游客抽样 | 200 | 138916 字节 | 402 | 成功解码 402 条 |
| 本机已有 Web 登录会话 | 200 | 3291060 字节 | 9669 | `danmaku_segment / protocol` |

登录响应的最大单项为 545 字节，最大字符串字段为 224 字节，全部为普通滚动／顶部／底部弹幕。它未超过每项 4096 字节、字符串 1024 字节的预算；条数超过 6000 时已有均匀抽样处理。实际失败点是 `getDanmakuSegment` 和 `decodeDanmakuSegment` 仍将超过 **2 MiB** 的合法响应整体拒绝，播放会话因此显示通用弹幕错误。

诊断仅读取该应用系统安全存储内的现有会话，并在内存中按 Cookie 作用域与有效期请求；不写账号状态，不输出或持久化凭据、原始响应或弹幕正文。数量和大小是本轮在线快照，会随弹幕池变化。

## 修改

- 按用户要求，接收后的检查和解码器共用 **8 MiB** 单段预算。
- 为弹幕请求传递显式字节上限；支持 `ApiBoundedTransport` 时使用流式接收，在解压后超过预算立即取消。自定义普通 transport 仍在解码前检查大小。
- 保留最多 6000 条均匀抽样、每项／字符串限制、完整验证未保留元素、大响应 isolate、并发与排队上限，以及取消、deadline 和 session epoch 隔离。
- 视频与 PGC 复用同一 API 入口；不修改播放、弹幕时钟或绘制逻辑。

## 验证

- 新增合成的 9669 项、超过 2 MiB，以及 16001 项、超过 4 MiB 的回归数据，均低于 8 MiB，无真实账号或弹幕正文。修复前直接解码和 API 读取均复现失败，修复后保留 6000 条并覆盖首尾与各分钟。
- 覆盖普通／流式 transport、默认异步解码、超过 8 MiB 时不进入解码且不重试、未保留项中的无效 UTF-8，以及每项／字符串预算。
- 最终 8 MiB 预算的登录只读复测返回 3290677 字节、9669 项，实际解码器成功保留 6000 条。
- `packages/bili_api` 的 `dart analyze`：通过；最终 8 MiB 预算的 `dart test --reporter expanded`：1021 项通过，包含 15 项弹幕容量回归，以及既有的取消、超时和解码排队回归。
- `tool/check.ps1 -SkipPub` 的格式与打包边界脚本通过；根静态分析复查 `flutter analyze --no-pub` 通过。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：四包测试阶段通过；其中 `bili_api` 在预算最终调整后单独重跑，如上。其余 `bili_player` 373 项、`bili_danmaku` 161 项、`bili_mux` 5 项通过；播放器原生测试跳过 3 项，mux 因未配置 `BILI_MUX_LIBRARY` 跳过 10 项，不计为原生验证通过。
- 本轮全量 `tool/check.ps1 -SkipPub -Stage RootTests`：5636 项通过、13 项跳过、56 项失败，失败位于本次未修改的 UI 路径。包括导航控件匹配到多个元素、缺少 `WindowRegistry`、发送样式的 `ChoiceChip`／tooltip 查找失败及卡片布局断言；未为使全量通过而修改这些同期 UI 改动。
- 最终 8 MiB 预算的 `flutter test --no-pub test/features/playback/comment_window_test.dart test/features/playback/playback_session_test.dart --reporter expanded`：321 项通过。

全量根测试失败分布：

| 测试文件 | 失败数 |
| --- | --- |
| `test/app/navigation_bar_mode_test.dart` | 6 |
| `test/app/workspace_image_viewer_test.dart` | 4 |
| `test/features/pgc/pgc_danmaku_test.dart` | 1 |
| `test/features/settings/danmaku_settings_controls_test.dart` | 2 |
| `test/features/settings/settings_screen_test.dart` | 1 |
| `test/features/video/video_danmaku_composer_test.dart` | 3 |
| `test/features/video/video_danmaku_send_test.dart` | 23 |
| `test/features/video/video_screen_test.dart` | 1 |
| `test/features/playback/playback_panel_test.dart` | 4 |
| `test/shared/ui/card_text_measurement_reuse_test.dart` | 2 |
| `test/shared/ui/danmaku_send_style_button_test.dart` | 7 |
| `test/shared/ui/video_card_variants_test.dart` | 2 |

不构建应用，不启动设备或测量性能；本轮在线验证覆盖请求与解码，不替代用户的播放界面验收。
