# 字幕、AI 原声翻译与播放菜单验证

调查日期：2026-10-08；实施日期：2026-10-09。已修复动态播放菜单选择失效、空文本字幕解析，接入字幕 AI 标识和在线点播语音选择。按用户要求，测试后提交源码，Release 构建由用户手动执行。

## 1. 会话、样本与验证范围

通过 `SystemCredentialStore` 读取现有 Release 使用的 `bilisail.web_session.v1` 槽位，在内存恢复 Cookie 后调用 `/x/web-interface/nav`，确认登录有效。没有改写、导出或打印凭据，没有读取或写入账号私有业务列表，没有进度上报或账号写操作。

| 视频 | aid | cid | 本轮字幕结果 |
| --- | --- | --- | --- |
| `BV1fnYk6eENv` | `117266733600779` | `41872396242` | 中文 154 条、英语 150 条；日语正文 143 条，修复后跳过一条空文本并正常加载 142 条 |
| `BV1jxtC6pEuU` | `117215781262882` | `41595112244` | 中文 87 条；英、日、西、阿、葡、泰、印尼语各 82 条，当前解析器均正常 |

两个样本的登录态 `/x/player/wbi/v2` 都返回 `need_login_subtitle=false` 和完整字幕列表。游客返回的空字幕列表不能用于判断登录后是否有字幕。

初次调查的立即选择测试能显示中文字幕。随后针对用户补充的多个菜单共同失效问题，在动态控件模式复现了等待后选择无效；修复后 Windows 原生验证通过真实菜单选择中文字幕，在 10 秒处确认实际字幕 Text 存在、音视频都已解码。

探针默认跳过；登录态正文读取、真实字幕显示、倍速/清晰度选择、语音切换和新版元数据探针均已显式运行通过。Android/macOS 和人工听辨翻译质量未验证。

## 2. 已确认的不显示原因

动态控件的菜单打开后仍执行一秒空闲隐藏，鼠标进入弹出菜单也会触发播放器 MouseRegion 的退出。200 毫秒淡出结束后 `_FadingPlayerControls` 卸载按钮，Flutter 的 PopupMenuButton 在路由返回时因自身已卸载而跳过选择回调。这同时影响清晰度、倍速、字幕与窄窗口更多选项。修复前回归测试等待两秒后选择 3 倍速，实际仍为 1 倍速；修复后菜单打开期间暂停空闲隐藏和鼠标退出隐藏，关闭后恢复定时器。章节菜单也接入相同生命周期。

第一个样本日语正文为 HTTP 200 JSON，`body` 有 143 条。其中从 0 开始的索引 50，也就是第 51 条，内容为：

```json
{"from":153.03,"to":153.43,"content":""}
```

修复前 `BiliApiClient.getSubtitleCues` 对每一条都调用 `_requiredString(content)`，空字符串会抛出 `ApiFailure(protocol, subtitle_body)`，使其他 142 条也全部丢失。现在先验证有限非负时间、结束时间顺序和字符串类型，再过滤空白文本，协议损坏仍分类失败。PlaybackSession 单独维护字幕加载、失败、空正文状态，成功重试和关闭会清除提示；提示不受控制栏显隐影响，取消及旧来源/账号 epoch 的结果不会更新当前字幕。

这个日语正文解析失败与 HTTP、登录、域名或地址过期无关。`/x/player/wbi/v2` 返回的 `subtitle_url` 可直接取得 JSON；生产实现沿用这一已验证端点，新版 Protobuf 接口继续作为独立调查探针。

## 3. 字幕端点与字段

| 端点 | Profile / 鉴权 / 签名 | 格式与当前归属 |
| --- | --- | --- |
| `api.bilibili.com` GET `/x/player/wbi/v2` | Web Cookie；WBI；`aid`、`cid` | JSON `data.subtitle.subtitles[]`；当前产品与探针均使用 |
| 响应提供的 `aisubtitle.hdslb.com` HTTPS GET `subtitle_url` | 不发送 API Cookie；不签名 | JSON `body[]`，秒单位 `from/to` 与字符串 `content`；当前产品使用 |
| `api.bilibili.com` GET `/x/v2/subtitle/web/view` | Web Cookie；本轮无需 WBI | HTTP Protobuf；仅本轮探针使用，产品尚未接入 |

新版请求参数：`oid=cid`、`pid=aid`、`type=1`、`context_ext={"video_type":1}`、`playlist_switch=0`，原声 `cur_language=""` / `cur_production_type=0`，语音翻译 `cur_language=en/ja` / `cur_production_type=2`。这是点播 Web 的 HTTP Protobuf，不需要 App token 或 gRPC。

字幕类型取轨道的 `type`，不能与请求参数 `type=1` 或正文根对象的 `type` 混用。

| 样本轨道 | `lan` | `lan_doc` | `type` | `ai_type` | `ai_status` |
| --- | --- | --- | --- | --- | --- |
| 中文 AI 识别 | `ai-zh` | `中文` | 1 | 0 | 2 |
| 英语 AI 翻译 | `ai-en` | `English` | 1 | 1 | 2 |
| 日语 AI 翻译 | `ai-ja` | `日本語` | 1 | 1 | 2 |

当前官方 schema：`SubtitleType` 的 `CC=0` / `AI=1`；`SubtitleAiType` 的 `Normal=0` / `Translate=1`；`SubtitleAiStatus` 的 `None=0` / `Exposure=1` / `Assist=2`。状态值不作为“是否 AI”的判断条件。

API 与领域模型现在保留轨道 ID 字符串、语言代码、类型、AI 子类型和状态，包括未知数值。展示层根据 `type` 和 `ai_type` 形成“中文 · AI”“English · AI 翻译”，手动字幕保持原标签，菜单显示当前选择。字幕偏好用语言代码恢复，避免仅依赖显示名。

新版 Protobuf 顶层 field 1 是 `subtitle`，内部 repeated field 3 为轨道。轨道字段为：1 `id`，2 `id_str`，3 `lan`，4 `lan_doc`，5 `subtitle_url`，7 `type`，8 `lan_doc_brief`，9 `ai_type`，10 `ai_status`，11 `role`，12 `subtitle_height`，13 `format`。枚举 `role=1` 是主字幕，`role=2` 是次字幕；`format=0` 的枚举名为 `Srt`（本样本正文仍是 JSON cue），`format=1` 为 `Ass`。

实测默认原声三个轨道均 `role=0`；选择英语后 `ai-en.role=1`，选择日语后 `ai-ja.role=1`，所有轨道 `format=0`。新版 field 5 的主机为 `subtitle.bilibili.com`，路径经过编码；官方播放器将其转换为 `aisubtitle.hdslb.com` 实际正文地址并保留签名参数。后续接入需独立适配和验证，此探针没有复制或部署官方地址解码代码。

## 4. AI 原声翻译端点与实测

使用 `api.bilibili.com` GET `/x/player/wbi/playurl`，Web Cookie 和 WBI，沿用现有 `bvid/cid/qn/fnval/fourk` 参数。响应通过以下字段提供能力：

```text
data.language.support
data.language.items[].lang
data.language.items[].title
data.language.items[].subtitle_lang
data.language.items[].production_type
data.language.items[].video_detext
data.language.items[].video_mouth_shape_change
data.cur_language
data.cur_production_type
data.dash.video[] / audio[]
```

第一个样本 `language.support=true`，可选 `en/English/ai-en` 和 `ja/日本語/ai-ja`；两项 `production_type=2`、`video_detext=true`、`video_mouth_shape_change=false`。官方播放器生产类型枚举为原声 `0`、投稿多语言 `1`、AI 原声翻译 `2`。第二个样本虽有八种字幕，但播放响应没有 `language`，不能从存在翻译字幕推导为支持语音翻译。

切换请求增加 `cur_language=en/ja`、`cur_production_type=2`；本轮按官方切换流程也携带 `client_attr=1`，重新计算 WBI。恢复原声使用空语言和生产类型 `0`。服务端返回所选语言与生产类型，视频和音频资源路径都与原声不同；不能只替换音频。

生产 API 已支持上述参数，Repository 验证服务端回传语言和生产类型，防止把回退原声误报为切换成功。Windows 原生探针通过实际“语音翻译”菜单选择英语、日语和恢复原声，每次打开菜单后等待两秒再选；全部确认音视频已解码，音频 2 声道 / 44100 Hz，并保留 10 秒位置、1.5 倍速和暂停意图。恢复原声资源路径与切换前一致。同一探针还确认真实倍速菜单和清晰度菜单生效，日语字幕正常加载 142 条。测试静音，没有人工听辨翻译内容和音画口型质量。

## 5. 接入范围与复现

PlaybackSession 持有所选语音并复用切源代次、取消与 DASH 双轨打开；语音能力通过可选 VoicePlaybackRepository 端口传递，组合根现有在线/离线适配器转发在线能力。宽窗口提供“语音翻译”，窄窗口在“更多播放选项”中列出原声与各语言，入口仅在服务端提供能力时显示。

语音切换保留位置、暂停、倍速、音量，快速连续换语音时保留待恢复的位置并丢弃旧响应。已开启字幕时按 `subtitle_lang` 选择关联轨道，用户手动关闭字幕和默认关闭设置均被保留；手动改选其他字幕后切清晰度不会强制改回关联字幕。清晰度切换、URL 重试和同一标签恢复保持语音；换 P/新视频重新探测能力并从原声开始。直播、PGC 和离线媒体不新增语音入口，也不改变下载媒体选择。

回归覆盖空 cue、协议损坏、AI/未知字幕类型、失败/空正文/重试、16 组动态菜单（四类选择 × 宽窄 × 普通全屏）、快速换语言、清晰度/重试、标签恢复、关闭字幕与旧账号 epoch。Android/macOS 原生验证及离线翻译媒体下载/导出不在本轮已验收范围。

探针默认跳过，只有显式启用时读取系统保存会话。输出只包含公开视频身份、字段、数量、时间与解码统计，不输出 Cookie、账号身份、正文文本或媒体/字幕签名 URL；不会写入安全存储或用户设置。

```powershell
flutter test --no-pub integration_test/windows_subtitle_translation_probe_test.dart -d windows --dart-define=BILI_SUBTITLE_SAVED_SESSION=true --dart-define=BILI_SUBTITLE_NATIVE=true
flutter test --no-pub integration_test/windows_subtitle_translation_probe_test.dart -d windows --dart-define=BILI_SUBTITLE_SAVED_SESSION=true --dart-define=BILI_SUBTITLE_MODERN_ONLY=true
```

## 6. 最终检查结果

完整 `tool/check.ps1` 已在隔离工作树通过：根应用 1427 个测试、bili_api 336 个、bili_player 32 个、bili_danmaku 65 个，四处格式与静态分析均通过。该快照包含本任务补丁，排除主工作区正在开发的其他改动；主工作区的脚本曾被下载模块格式问题阻断，直接运行播放目录测试也曾受尚未处理的 `DownloadStatus.muxing` 页面分支影响。提交只包含本任务补丁，保留并行修改。

登录态 Windows 原生探针确认：延迟菜单选择生效，中文字幕实际显示，倍速为 1.5、清晰度成功切至 360P，英语/日语/原声音视频均解码；每次保持 10 秒位置和暂停，日语字幕为 142 条。用户补充“不需要构建”后未再运行构建；仅保留此前原生探针所需的 Debug 测试构建，未生成新的 Release 或安装包。

来源：本轮两个样本的登录态端点响应与原生运行；[B 站当前播放器](https://s1.hdslb.com/bfs/static/player/main/core.ba67b466.js)中的字幕 schema、语音生产类型及切源参数。实现独立协议映射，没有导入其播放器源码或资源。
