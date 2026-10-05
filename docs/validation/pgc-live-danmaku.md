# 影视弹幕、直播实时消息与分区修复

日期：2026-10-05。基于现有未提交工程增量修改，保留用户已有改动；相邻参考仓库只读，不复制源码、schema 或视觉资源。本轮 SC 样式参考用户提供的官方哔哩哔哩截图，没有重新操作本机官方客户端。

## 影视播放

PGC 组合根原本已通过合成的 `VideoDetail` / `VideoPart` 间接提供剧集 cid，发送栏则没有接入。当前将真实 cid 明确绑定到 `PgcPlaybackTarget`，点播弹幕直接使用目标 cid，兼容原来的 UGC 分 P；即使没有 UGC 详情/分 P 对象，影视仍可读取弹幕。番剧、国创和放映厅共用该路径。

沿用 Web HTTP Protobuf `/x/v2/dm/web/seg.so`、有界解码和确认播放位置驱动的 `DanmakuController`。换集、seek、清晰度切换隔离旧分段请求；模式、关键词、密度、字号和范围继续消费共享设置。影视无需新的弹幕协议或额外播放器。

新增 `PgcDanmakuComposer` / `PgcDanmakuController` / `PgcDanmakuRepository`，由 app 注入实现；发送复用现有 Web Cookie/CSRF POST `/x/v2/dm/post`，真实 bvid/cid 和后端确认进度在用户点击时固定。登录、输入模式/颜色、100 字符上限、busy、账号 epoch 与 source generation 均检查；未知结果不自动重试、不清空新剧集草稿。影视发送不读取普通视频的点赞/投币状态，不依赖另一 feature 的 presentation/data。

游客只读烟测 `tool/pgc_danmaku_smoke.dart`：作品 `28747`、剧集 `733316`、cid `1022370693`，第 1 段成功解码 1544 条（滚动 1293、顶部 220、底部 31）。此结果证明现有 PGC 分段协议可读取，不证明登录发送已经实测；工具只输出公开 ID 与数量。

## 直播实时消息和绘制

直播消息传输独立于媒体播放。连接发现使用 Web WBI `getDanmuInfo`，与现有请求复用 nav/WBI key 单飞；服务器下发 token、可信 WSS host 和房间 ID 用于认证。发现结果允许 `*.chat.bilibili.com` 的 WSS 443/2245 端口，保留系统 TLS 验证并拒绝 Upgrade 重定向；Cookie 不交给 WebSocket。Socket、鉴权、心跳、解码 isolate、有界队列、重连和退出由独立会话管理。正常 CI 只连接 fake/local socket，不使用真实账号。

支持 raw/zlib 包，声明 `protover=2`；没有 Brotli 解码器时不声明协议版本 3。校验完整协议包头、合包、嵌套解压与容量上限。`DANMU_MSG` 更新聊天和画面弹幕；SC 新增/删除独立合并；账号切换、换房、隐藏页面和销毁清理连接、心跳、待处理消息及旧响应。聊天、SC 和消息断开各自显示状态，消息断线不停止原生播放器。

历史快照用于初始补充，历史消息不会作为实时画面弹幕重播。`LivePlayerDanmaku` 订阅新消息批次，独立的单调到达时间驱动直播渲染，不使用点播的 position/seek/rate。`PlaybackPanel` 提供 overlay builder 并贯通内嵌/全屏，直播开放弹幕开关和配置；继续只拥有一个 native engine/surface。

短房号的侧栏控制器以 requested room ID 为 family key，网络使用解析后的 canonical ID；播放器通过 `LiveDanmakuRoomScope` 沿用同一控制器 key，全屏闭包也保留该 key，避免短号房间创建第二个未激活消息控制器。历史/WS 的不同消息 ID 通过昵称、正文和北京时间归一后的秒级指纹合并；独立 WS ID 再控制画面去重。同一用户在同秒重复相同文本时，聊天列表会合并，画面仍保留不同 WS ID。

30 秒心跳，75 秒未确认心跳判超时；连续失败至多 5 次，带抖动退避上限 30 秒，稳定连接恢复后重置连续失败预算。断线重新发现连接信息；认证、权限和风控失败不循环自动重放。单个 WS message/packet 至多 1 MiB，解压总量 8 MiB，嵌套 4 层，解码批次最多 500 个事件；接收队列至多 8 个 message / 4 MiB。UI 聊天 500 条，SC 100 条，屏幕 pending 500 / visible 120 / 文本布局 256；超限丢弃或受控断线，不无限积压。

SC 胶囊和完整卡片共用领域状态。样式改为紧凑头像/金额胶囊、独立信息头和正文色块，明暗主题与 320px 大字号均可用；金额保留 API 的人民币单位，不推断电池/代币转换。服务端颜色优先，缺省按金额档位选色并检查文本对比度。脱敏 Flutter 组件预览为 `artifacts/live-danmaku/sc-preview.png`，使用项目字体；头像是占位，不是真实账户截图。

## 分区接口

旧 `/xlive/web-interface/v1/second/getList` 在本机无签名读取返回业务 `-352`；当前官方 Web 页面构建也给该请求加 WBI。对照官方签名后本机仍返回 `-352`，未设置盲目重试或自动备用接口链。

固定采用参考仓登记且本轮游客成功验证的 `/room/v3/Area/getRoomList`，不是收到风控后的动态降级。主分区/子分区依然使用 `parent_area_id` / `area_id`；返回房间 ID、主播 `uid` 和封面在 API 边界转换，空封面回落到 `user_cover` / `system_cover`。推荐首页仍使用现有 `index/getList` 快照。

| 端点 | profile / 鉴权 / 格式 | 参数、分页和重试 | 在线证据 |
| --- | --- | --- | --- |
| `api.live.bilibili.com` GET `/room/v3/Area/getRoomList` | Web、Cookie 可选、无签名、JSON `data.list` / `data.count` | `platform=web`、`sort_type=online`、`page_size=36`、page 从 1 开始；`page*36<count` 判后续页；沿用有限只读重试，风控/429 不自动重放 | 网游主分区首屏和第二页、英雄联盟子分区均 `code=0`、36 个房间；应用实际 UA/Referer 也成功 |
| `api.live.bilibili.com` GET `/xlive/web-room/v1/index/getDanmuInfo` | Web、Cookie 可选、WBI、JSON `token` / `host_list` | canonical `id`、`type=0`，无分页；复用 nav key 单飞和有界读 deadline；认证/风控不自动切端点 | 游客 WSS 2245 连接鉴权成功，热门房间 40 秒收到 141 条聊天和 2 次心跳 |
| `api.bilibili.com` GET `/x/frontend/finger/spi` | Web、无 App token、JSON `b_3` | 缺少 buvid3 时取得设备标识，Cookie domain/path/secure 约束保留；单飞且 caller 取消独立 | 与上述游客发现/鉴权链路一并读取；标识不输出 |

官方调用证据是 [分区页面](https://live.bilibili.com/p/eden/area-tags?parentAreaId=2&areaId=0) 的 [主 bundle](https://s1.hdslb.com/bfs/static/blive/live-region/static/js/app.397b4bcc.js)、[端点 chunk](https://s1.hdslb.com/bfs/static/blive/live-region/static/js/81.d56e5df2.js) 和 [WBI chunk](https://s1.hdslb.com/bfs/static/blive/live-region/static/js/221.391a2d3a.js)；主 bundle 的构建日期为 2026-08-18。代码由本项目独立编写，只参考参数与响应语义。

## 验证与边界

- `tool/test-windows-content.ps1 -Online` 两项通过：受控 HLS/HTTP-FLV 继续验证原生 headers、媒体控制和单会话；真实游客 PGC DASH 音视频解码后，目标 cid 载入的弹幕在真实 `DanmakuOverlay` 中达到 `visibleCount>0`；随后直播公开 CDN 解码音视频。
- 纯 Dart 在线入口是 `packages/bili_api/tool/live_chat_smoke.dart`。第一次游客 `7734200` 认证成功、40 秒心跳 2 次、聊天 0 条；随后显式 `--popular` 从公开列表选择活跃房间，40 秒内 `connected=true, chat_messages=141, super_chats=0, heartbeats=2`。工具只输出阶段和数量，不打印正文、昵称、身份、Cookie/token/buvid 或 URL；未执行账户写。真实 raw/zlib 普通聊天已接收，SC 新增/删除和压缩边界由 fixture 验证。
- `tool/check.ps1 -SkipPub` 通过：根应用 398、`bili_api` 116、`bili_player` 16、`bili_danmaku` 10，共 540 项测试；四处格式检查及静态分析均通过。覆盖影视发送权限/未知结果/换集竞态，直播包与容量边界、连接取消/重连/账号切换、聊天与 SC 合并、画面过滤、短房号控制器、全屏单 surface 和侧栏行为。完整日志在 `artifacts/live-danmaku/check.log`。
- `flutter build windows --debug --target lib/main.dart` 通过，最终入口恢复为应用，产物 `build/windows/x64/runner/Debug/bili_lite.exe`。`flutter build apk --release --target-platform android-arm64 --target lib/main.dart` 通过，产物 `build/app/outputs/flutter-apk/app-release.apk`；构建日志分别在 `artifacts/live-danmaku/windows-build.log` 和 `android-build.log`。Android 构建不代表实机播放已验收。

真实账号发送、真实非空 SC、Android 实机/macOS 运行和长时间/profile 性能均需分别验证，不能从 fixture、插件或 Windows 结果推导。
