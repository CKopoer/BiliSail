# 番剧剧集与位置续播修复

日期：2026-11-09。按用户要求只做自动检查与提交，不构建、不安装，由用户后续实机验收。

## 问题与行为

番剧入口只有季号时，详情控制器直接选择第一集；API 解码也丢弃 `user_status.progress`。已有本地分集位置虽然会保存，但无法用于选择最近看的剧集。影视云端位置还沿用普通视频的 WBI 分 P 读取，没有采用 PGC 自己的记录。

修复后：明确剧集链接、手动选集及已有页面选择优先；仅季号入口开启“记住播放进度”时，先按当前账号在已有 SQLite 进度中选择本季最近观看的一集，缺失再使用云端 `last_ep_id`，无有效记录才选择首个可播剧集。支持正片和特别篇，不按集号最大值选择，回看较早剧集也会记住。

选集完成后继续由同一 `PlaybackSession` 读取该集的本地位置；本地缺失才读 PGC 云端位置，保留零／已完成记录的本地优先规则。云端位置沿用媒体准备并行、源就绪后 seek 的行为，不增加播放器或确认弹窗；结束前五秒内和已完成记录继续从头播放。关闭记忆不自动恢复剧集或位置。

本地查询复用 `playback_progress.pgc_episode_id`，无表结构变更、不迁移或清空数据；每账号最多 500 条已有记录，与最多 5000 集的当前详情集合求交集，避免 SQLite 参数数量限制。初次剧集恢复最多等待三秒，读取失败显示提示并保留可播放详情。刷新期间的手动选择优先，取消、关闭、账号 scope／session epoch 改变后旧结果不能更新页面。

## 协议与参考

- Web Cookie GET `api.bilibili.com/pgc/view/web/season`：`season_id`／`ep_id`，无 WBI／CSRF；JSON `result.user_status.progress.last_ep_id` 为十进制集号，`last_time` 为秒数，-1／0 按从头处理，缺失或非法可选字段视为没有进度。无分页，沿用现有请求超时、重试和取消管线；读取位置必须匹配当前集号。
- 普通视频保留 `/x/player/wbi/v2` 毫秒读取；上报仍使用既有 Web heartbeat，不新增写操作或重放。
- 只读参考 PiliPlus `4fce4bb5a35c425aee759ef9263352316a29e355`：`lib/utils/page_utils.dart` 的 `viewPgc`、`lib/models_new/pgc/pgc_info_model/result.dart` 的 `findEpisode` 与 `user_status.dart`／`user_progress.dart`，以及 `lib/http/search.dart` 的 season 请求、`lib/http/video.dart` 和 `lib/pages/video/controller.dart` 的影视进度／定位职责。已核对其 pubspec overrides 和锁文件；本次不采用或更换其媒体依赖。
- 秒数单位另核对 bili-kernel `e26f6dbd071e20d4220806fcff7bd675f3c29fc5` 的 `src/Services/Services.Media/Core/Models/PgcDetailResponse.cs`。仅借鉴行为职责和协议字段，独立实现，未复制 GPLv3 应用源码、schema 或资源，未修改相邻仓库或新增运行时依赖。

## 验证

离线测试覆盖 API 主线程／worker 解码、十进制大 ID、秒数／完成标记／缺失非法记录、集号不匹配、普通视频协议保留、本地优先和云端回退、特别篇、开关关闭、取消／账号代次／显式选集竞态，以及共享会话恢复位置和单一播放器。

专项 `flutter test --no-pub test/features/pgc test/core/storage/app_database_test.dart test/features/playback/playback_session_test.dart` 373 项通过；API `dart test test/pgc_decode_test.dart test/playback_history_client_test.dart` 42 项通过。根应用 `flutter analyze --no-pub` 无问题。

完整 `tool/check.ps1 -SkipPub` 通过：根应用 4790、API 748、player 360、danmaku 161、mux 5，共 6064 项 Dart／Flutter 测试通过；格式、静态分析和打包边界脚本通过。13 项 Windows 符号链接测试因权限跳过，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不算原生通过。文档相对链接与 `git diff --check` 通过。日志保存在 `build/pgc-resume-{targeted-test,api-test,analyze,check}.log`。

未使用真实账号请求或写入历史；未构建、安装或进行 Android／Windows／macOS 实机验收，实际番剧入口和播放体验由用户后续构建确认。
