# 隐藏控件进度条与直播弹幕发送

日期：2026-10-05。在现有未提交工程上增量修改，保留已有改动。用户随后要求暂时跳过影视弹幕不显示的问题，本轮没有针对该问题修改协议或渲染实现。

## 播放进度

视频和影视在控件隐藏时，画面最底部显示 2 逻辑像素的粉色播放进度条，没有滑块或额外点击区域。使用确认的播放位置与时长，暂停时保留进度，内嵌和全屏共用逻辑；直播和未知时长不显示。

“隐藏控件时显示底部进度条”默认开启，可在应用设置的“播放”分类和播放器设置的“播放”页即时开关。设置快照版本由 5 升为 6，旧快照缺省开启，其他偏好保留；没有 SQLite 表结构变化或清空数据。

## 直播发送

直播播放器新增 `LiveDanmakuComposer`，常规布局直接显示，小窗使用现有发送入口展开；侧栏聊天／SC 下方常驻同一组件。两处按 requested room ID 使用同一 `LiveDanmakuController`，同步草稿、表情选择、busy 和未知结果状态；网络发送使用详情解析后的 canonical room ID。

发送只由点击“发送”或输入框 Enter 触发。游客进入登录；未开播、空内容、正在发送或结果不明时阻止写入。成功清空共享草稿，失败保留；超时、网络、HTTP 和响应格式错误作为结果不明处理，不自动重放，用户核对后点击“已核对”才能再次提交。账号 scope/epoch、房间身份与操作代次隔离旧读写；切换账号／房间取消待完成操作，旧结果不能清空新草稿。

表情面板按需读取房间表情包，最多 30 包／500 项；显示名称、图片和解锁提示。普通表情插入文本，图片表情选择后预览，仍需显式发送。权限不明／未解锁项不可选择。图片统一 HTTPS，不携带 Cookie；未新增离线图片资源或账号付费操作。表情读取失败可手动重试，不影响文字输入。

全屏路由保留所属播放页的 `ProviderContainer`，因此侧栏、内嵌和全屏发送栏使用同一个作用域，不额外创建播放器或发送控制器。

## 协议登记和来源

| 端点 | profile／鉴权／格式 | 参数与重试 | 本轮在线验证 |
| --- | --- | --- | --- |
| `api.live.bilibili.com` POST `/msg/send` | Web Cookie `SESSDATA` + `bili_jct`；`csrf`／`csrf_token`；form／JSON | canonical `roomid`；文字 `dm_type=0,msg=正文`，图片表情 `dm_type=1,msg=emoticon_unique`；`rnd` 秒时间戳、白色滚动 25 字号；沿用 25 秒总 deadline，单次 POST，无分页／自动重试 | 未执行真实账号发送；只用脱敏 fake transport 验证 |
| `api.live.bilibili.com` GET `/xlive/web-ucenter/v2/emoticon/GetEmoticons` | Web Cookie，JSON `data.data` 包列表 | `platform=pc,room_id=canonical`；沿用有界只读重试／deadline，鉴权失败不循环重试 | 游客读取返回 `-101`；登录非空表情列表尚未在线验证 |

独立的 live mutation allowlist 固定发送 host 和 Origin／Referer，Cookie 仍由域、路径和 secure 规则决定，不将视频 host-only Cookie 扩散到直播 host。直播成功码 0 但带拒绝信息也按失败处理；频率和权限错误分别反馈，服务端文本不进入日志。

协议语义参考相邻仓库的 [LiveRoomAPI](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/Live/LiveRoomAPI.cs) 和 [LiveRoomEmoticon](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveRoomEmoticon.cs)，另核对 [API-collect 的原始协议研究](https://sessionhu.github.io/bilibili-API-collect/docs/live/danmaku.html)（该研究文档声明 CC-BY-NC-4.0）。这里只参考端点／字段语义，没有复制源码、schema、文档段落或图片；参考中的 App 签名和 iOS 发送协议没有采用。

## 验证

- `tool/check.ps1 -SkipPub`：根应用与三个包的格式、静态分析及离线测试通过，共 555 项（根应用 409、API 120、播放器 16、弹幕 10）。包括旧设置迁移／重载、隐藏进度、全屏作用域、直播双发送栏／表情权限、单次写、账号／房间竞态和未知结果。日志：`artifacts/player-danmaku/check.log`。
- `tool/test-windows-media.ps1`：Windows 主播放套件及独立错误诊断通过。新增原生画面隐藏控件后的真实进度比例检查，继续验证 DASH 音视频、headers／Range／重定向、宽窄布局、全屏单 surface、工作区与安全存储；错误诊断记录 HTTP 403 且未保存原始 URL。游客 UGC 分支未启用。日志：`artifacts/player-danmaku/windows-media.log`。
- 本轮开始前的公开番剧只读探针读取 1552 条弹幕；Windows content 两项测试解码 PGC 音视频和非空弹幕、直播音视频。日志：`artifacts/player-danmaku/content-before.log`。这只是样本验证，不宣称用户报告的影视问题已修复。

- `flutter build windows --release --no-pub --target lib/main.dart` 通过，最终入口恢复为应用。程序位于 `build/windows/x64/runner/Release/bili_lite.exe`，运行时需保留同目录依赖与资源。日志：`artifacts/player-danmaku/windows-build.log`。
- `flutter build apk --release --target-platform android-arm64 --target lib/main.dart` 通过，产物 `build/app/outputs/flutter-apk/app-release.apk`。首次 `--no-pub` 构建遇到 Windows 集成测试遗留的 `integration_test` 插件注册信息；常规构建重新生成注册文件后通过，没有手改生成物。日志：`artifacts/player-danmaku/android-build.log`。构建不代表 Android 实机验收。

真实账号文字／图片表情发送、登录后的非空直播表情包、Android／macOS 实机和性能未验收。
