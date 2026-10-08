# 下载与离线播放方案

日期：2026-10-07。下列是本轮实施方案，验收结果另列于文末；不能从参考项目或插件支持列表推导三端后台下载已完成。

2026-10-09 按用户选择接入独立精简封装组件与“合并为单个 MP4”选项；保留分轨方式和旧任务。依赖核对见[文件封装能力评估](validation/download-muxing-evaluation.md)，实现与手动构建步骤见[合并验收记录](validation/download-muxing-results.md)。

## 功能与界面

- 普通视频按分 P、影视按可播放剧集多选；读取当前账号实际返回的清晰度，选择清晰度与视频编码，保存 AAC 音频。不存在选定轨道时明确失败，避免任务悄悄降画质。
- 下载中心沿用当前 Material 3 主题、粉色强调色、圆角、封面比例与字体。顶部显示队列/已完成分类、搜索、批量暂停/继续及设置；任务卡展示标题、分 P/剧集、画质、状态、字节、速度和操作。窄屏让工具栏和操作换行。
- 设置默认同时下载两项，可选 1–3 项；默认应用文档目录中的独立离线目录，桌面可指定后续任务目录，已有任务保留原目录。离线文件不受普通缓存清理影响。
- 本地完成项可打开专属离线播放标签，共用现有 PlaybackSession、PlaybackManager 与播放器控件；离线播放读取本地音视频、字幕、弹幕和封面，不依赖详情/播放/云进度网络请求。
- 删除前显示任务名称，并明确选择是否删除文件。暂停、失败、重启恢复都保留断点；重启后等待用户继续，避免启动时立即占用网络。未完成队列最多 500 项；超出剩余容量整批拒绝，并发添加同一内容/画质/编码只创建一项。

## 状态与边界

`downloads/domain` 持有不可变任务、内容身份、轨道和仓储契约；`data` 实现 Web 源解析、SQLite 索引、受限 HTTP 续传和文件校验；`application` 为进程级服务提供 UI 控制器；`presentation` 只消费领域状态及控制器。`app` 负责下载入口、账号变化、退出、离线播放器和平台文件夹能力的组合。

状态为排队 → 解析 → 下载 → 校验 → 可选合并 → 完成；暂停和失败可显式恢复。任务和文件按账号 scope 隔离，异步操作同时核对 session epoch 和运行代次。账号变化立即取消旧解析/传输，完成的离线媒体保留在原账号下；新账号不会看到或继续旧账号任务。

SQLite 版本由 2 增至 3，保留设置与历史，增加下载索引；任务只保存内容/轨道身份、相对文件名、断点和校验信息，不保存签名 URL 或凭据。每次恢复重新请求 Web 播放信息。旧记录与分轨选择保留独立本地文件；可选合并由随应用携带的精简组件执行无损封装，输出和索引提交后清理分轨。无需用户安装完整 FFmpeg，也不进行转码。

传输要求：系统 TLS；媒体请求仅带 Referer/User-Agent，不带 API Cookie；有限重定向、连接/读超时和取消；续传验证 HTTP 206、Content-Range 起始/结束/总长以及对象身份；遇到不支持 Range 的 200 安全从头重下；无法确认同一资源时丢弃旧片段重下。下载结束核对长度并计算 SHA-256，临时文件刷新/关闭后原子改名，写完成 manifest 后再更新 SQLite。启动与离线打开复核本地文件，处理断电、强杀、文件丢失和 DB/文件提交窗口。

续传语义按 [RFC 9110 的 Range/Content-Range](https://www.rfc-editor.org/rfc/rfc9110.html#name-range) 实现，客户端生命周期依据 [Dart HttpClient](https://api.dart.dev/dart-io/HttpClient-class.html)。每轮轨道传输最多 6 次 HTTP 尝试；整个任务最多刷新一次源，因此每轨最多两轮、12 次 HTTP 尝试。双轨传输共用 3 小时总 deadline，连接与每次读均独立超时。哈希计算在 isolate，启动只复核轻量索引/文件信息，离线打开和完成时进行完整校验。

封面、字幕和普通弹幕各自限量并允许降级，缺失显示警告而不使已完整音视频失效。离线附属文件只保存正文，不保存远端媒体/字幕地址或会话信息。后台/休眠/系统服务能力不从前台 HTTP 实现推导，Android/macOS 设备验证单独记录。

## 参考来源与采用范围

只读参考 `biliuwp-lite` 的 `Controls/Dialogs/DownloadDialog.xaml.cs`、`ViewModels/Download/DownloadDialogViewModel.cs`、`Services/BackgroundDownloadService.cs`、`Services/DownloadService.cs` 与 `Models/Download/*` 的选集、轨道、附属文件和队列职责；参考 `bili-kernel/src/Services/Services.Media/Core/PlayerClient.cs` 的 UGC/PGC DASH 解析与公开模型。参考仓库提交及许可限制沿用 [参考文档](references.md)。独立编写 Dart/Flutter，不复制 C#/XAML、资源或引入相邻仓库运行时依赖；界面按本项目主题设计。

沿用既有 Web GET `/x/player/playurl`、`/pgc/player/web/playurl`、`/x/player/wbi/v2`、`/x/v2/dm/web/seg.so` 和公开字幕 JSON。API 请求沿用 Cookie 可选、WBI 按端点、25 秒 deadline 和取消；内容权益按服务端结果执行。不会使用参考 App/TV token 或绕过 PGC 地区/会员权限。

## 验收记录

2026-10-07，Windows x64 主机、Flutter 3.47.6：

| 验证 | 结果与边界 |
| --- | --- |
| `tool/check.ps1` | 格式及静态分析通过；根应用 945、bili_api 282、bili_player 22、bili_danmaku 32 项测试通过，共 1,281 项 |
| 下载协议与队列回归 | 覆盖 200 忽略 Range、206 范围/长度错误及分段响应、强 ETag 改变、416、取消真实断点、过期地址刷新与双轨重置、重启/文件损坏、账号切换和删除竞态、后台数据库故障、非零速度；v1/v2 数据库升级保留设置与历史 |
| 界面与离线适配器 | 多选、共同画质、旧请求取消、账号变化、删除文件选择、离线文件校验前不挂载播放器；320/390/1000 宽度与大字体检查。静态预览使用项目 HarmonyOS Sans 字体复核，不等同于发布窗口操作验收 |
| Windows 原生离线 | `flutter test integration_test/windows_downloads_test.dart -d windows` 通过；真实 HTTP 下载合成分轨、重开 SQLite、关闭服务器后用 media_kit 播放本地音视频、字幕和弹幕，seek/播放/暂停通过；无远端源重解析或云进度读写 |
| Windows x64 Release | `flutter build windows --release` 通过；入口为 `build/windows/x64/runner/Release/bilisail.exe`，分发需保留整个 Release 目录。本轮没有替换已安装版本或发布 Release |
| Android arm64 Debug | `flutter build apk --debug --target-platform android-arm64` 通过；产物为 `build/app/outputs/flutter-apk/app-debug.apk`。未安装到设备，不能据此确认下载、离线解码或后台行为通过 |
| Windows 游客公网下载 | `flutter test integration_test/windows_downloads_online_probe_test.dart -d windows --dart-define=BILI_DOWNLOAD_ONLINE=true` 通过；公开 UGC 的实际可用 360P（qn 16）双轨完整下载 14,700,421 字节，本地 SHA-256 复核通过，附属下载警告为 0。没有加载登录凭据或执行账号写操作；此探针默认跳过，不进入常规离线 CI |

macOS 构建、Android/macOS 设备离线播放、真实登录账号/会员 PGC 下载、公网长视频断网/休眠恢复和发布窗口鼠标操作尚未验收。Android 退入后台主动暂停当前应用下载；未实现系统下载服务、后台保活或系统通知，不能声称具备这些能力。暂停或重启后的资源若缺少强 ETag，会保留记录后安全从头重新下载该轨，避免拼接不同对象。
