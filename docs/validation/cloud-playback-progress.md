# 云端播放进度上报与本地优先续播

日期：2026-10-06。工具链沿用 Flutter 3.47.6 / Dart 3.13.5。

## 行为

开启“记住播放进度”后，打开点播按当前账号、bvid、cid 先查询本地 SQLite；只有本地记录不存在时才读取云端。已有的 0 秒记录和本地已完成记录都优先保留，不能被云端旧进度覆盖。云端只使用与当前 cid 一致的记录，不自动切换分 P；记录缺失则从头播放。沿用结束前 5 秒内重新从头播放的规则，云端完成标记也从头播放。关闭设置后不读取两种历史，首次打开从头播放；工作区内未关闭页面的精确位置和换清晰度的播放意图仍按原有会话规则保留。

登录后的普通视频和具有真实 bvid/cid 的影视剧集，在准备完成后提交当前进度，播放中每 15 秒提交新位置；暂停、seek、换视频/分 P、停止和关闭时补交最新观察，结束使用完成标记。记住播放进度开关只控制续播，上报不随该开关关闭。游客和直播不发点播历史请求。本地写入保持 5 秒节流，并在暂停、seek、结束、停止和关闭时保存。

云端读失败不使播放器进入错误态，显示读取失败提示并从头播放。云端上报失败不阻塞媒体控制和本地保存；提示不包含账号信息或服务端原文。账号作用域、session epoch、源 generation 和取消信号隔离旧响应。换账号取消在途请求、清空待发记录；同账号退出后重新登录也不能复用旧 epoch。

上报仅有一个在途请求，每个分 P 的待发记录保留最新观察，最多 8 个分 P；不取最大进度，因此主动回看可正常覆盖。失败写请求被消费，不自动重放；后续真实位置变化可以提交新观察。认证、权限或协议失败在当前账号 epoch 停止后续自动上报；限流丢弃待发记录并冷却一分钟。队列仅在内存，不持久化未确认写操作，不声称已实现持久化离线同步或云历史列表浏览。关闭时为整个队列最多等待 5 秒，超时取消并保留已保存的本地进度；先处理最后上报，再撤销账号 epoch。

## 端点登记

| 能力 | Host / method / path | Profile、鉴权、签名、格式 | 字段与重试 |
| --- | --- | --- | --- |
| 当前内容云进度 | `api.bilibili.com` GET `/x/player/wbi/v2` | Web Cookie，WBI，JSON，无 CSRF | `bvid`、`cid`，剧集带 `ep_id`/`season_id`；`last_play_time` 毫秒、`last_play_cid` 十进制 ID；0 未开始、-1 完成；无分页。读请求沿用最多额外 2 次网络/5xx 尝试和总 deadline |
| 播放进度上报 | `api.bilibili.com` POST `/x/click-interface/web/heartbeat` | Web Cookie/CSRF，JSON，无 App/WBI 签名 | 表单 `bvid`、`cid`、`played_time` 秒（完成为 -1）、`video_duration` 秒、`type=3/4`；剧集带 `epid`、可用时的 `sid`。单次提交，不重试或重放 |

API 请求沿用现有 Cookie 域/path/secure/expiry、TLS、重定向和 session epoch 管线；读写总 deadline 为 25 秒，单次请求受 API timeout 限制。仅协议包处理 JSON 与表单；主应用领域端口不引用 DTO、SQLite 或播放器实现。`PlaybackProgressStore.read` 改为可空返回以区分缺失记录，没有改变数据库结构，无需 schema migration。

## 参考与采用范围

按用户要求只读参考相邻 UWP 的 [PlayerAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/PlayerAPI.cs) 的 `SeasonHistoryReport`/`GetPlayerInfo`、[PlayerVM.cs](../../../biliuwp-lite/src/BiliLite.UWP/Modules/Player/PlayerVM.cs) 的 `ReportHistory`，以及 [PlayerControl.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/Controls/PlayerControl.xaml.cs) 的播放/切集/关闭上报职责。源码快照为 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0`；kernel `PlayerClient`/`VideoAdapter.ToPlayerProgress` 快照为 `e26f6dbd071e20d4220806fcff7bd675f3c29fc5`。参考协议字段、单位和调用时机，不复制 C#、schema 或资源，不修改相邻仓库。

UWP 的 `/x/v2/history/report` 使用 App 签名，不能将其凭据假定为本项目的 Web 会话；Web 心跳端点与字段交叉核查 [PiliPlus 自有实现](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/video.dart) 的 `heartBeat`/`playInfo` 和 [端点声明](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/api.dart)。本轮只参考协议，自行编写 Dart，不引入上游运行时依赖或复制 GPL 源码。参考实现不等于本项目真实账号已在线验证。

## 验证

离线测试使用 fake repository/player/clock/transport 和脱敏样本，覆盖本地优先（包括 0/已完成）、云端毫秒/完成标记、cid 不一致、开关关闭、游客、暂停/回退/结束/换源、15 秒节流、容量/串行、网络/限流/认证失败、不重放以及账号 epoch/旧源竞态。

Windows 原生回归使用现有本地 DASH 音视频分轨样本与 fake 云历史端口，验证实际播放器从云端样本位置启动、本地优先、开关关闭以及实际位置补报；不使用真实账号，不向 Bilibili 提交历史。

Windows `tool/test-windows-media.ps1` 已通过：播放套件报告 6 项、原生错误诊断 1 项通过；未启用 `BILI_ONLINE_SMOKE`，套件中的线上游客播放用例未执行。新进度测试输出 `NATIVE_PROGRESS cloudFallback=true localPrecedence=true rememberOff=true heartbeat=true`，本地样本两轨实际解码成功。日志为 `build/cloud-progress-windows.log`。普通游客在线 GET 烟测 `dart run tool/playback_history_smoke.dart` 返回 `code=0 hasProgress=false`，核对公开内容的播放器信息无账号进度；脚本不加载凭据、不发 POST。

最终 `tool/check.ps1 -SkipPub` 通过：根应用 668、API 包 225、播放器包 16、弹幕包 21 项，共 930 项；根应用和三个包格式检查、静态分析均通过。新增 API 协议测试 18 项、上报队列测试 8 项、续播/上报会话测试 12 项，以及 SQLite null/0/完成记录区分测试 1 项。日志为 `build/cloud-progress-check.log`。

`flutter build windows --release` 成功，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/cloud-progress-release.log`。文档相对链接与差异检查通过。本轮真实账号云端 GET/POST 及 Android/macOS 实机播放尚未验证。
