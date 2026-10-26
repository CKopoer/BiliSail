# 下载与离线播放方案

日期：2026-10-07。下列是本轮实施方案，验收结果另列于文末；不能从参考项目或插件支持列表推导三端后台下载已完成。

2026-10-09 按用户选择接入独立精简封装组件与“合并为单个 MP4”选项；保留分轨方式和旧任务。依赖核对见[文件封装能力评估](validation/download-muxing-evaluation.md)，实现与手动构建步骤见[合并验收记录](validation/download-muxing-results.md)。

2026-10-11 下载窗口改为“保存格式”：音视频分轨（默认）／合并 MP4／合并 MKV。两种封装使用同一精简组件、取消与提交链路；合并文件按单文件媒体打开，修复旧 MP4 被当作缺音轨 DASH 而报“未取得点播音频轨道”的问题。旧 MP4 完成项无需重新下载；本轮验证见[封装与离线播放修复](validation/download-muxing-results.md#mp4-离线播放修复与-mkv2026-10-11)。

## 功能与界面

- 普通视频按分 P、影视按可播放剧集多选；读取当前账号实际返回的清晰度，选择清晰度与视频编码，保存 AAC 音频。不存在选定轨道时明确失败，避免任务悄悄降画质。
- 下载中心沿用当前 Material 3 主题、粉色强调色、圆角、封面比例与字体。2026-10-25 统一为消息／设置页的顶部标题和下划线分类标签，队列／已完成标签各自显示数量。内容区宽度小于 600 时，刷新／设置入口与分类标签同排靠右；较宽布局仍放在标题右侧。大字体下分类标签可横向滚动，两个操作入口保持可见；嵌入“我的”页且不显示标题时，不额外占用空标题行。搜索与批量暂停／继续在宽屏同排、窄屏或大字体下分行；窗口宽度变化保留搜索文字。任务卡分层显示标题、分 P／剧集、画质／编码／格式、状态、字节、速度与进度，宽屏将状态和操作同排，窄屏操作区换行。全部颜色复用现有明暗主题；下载、筛选、批量操作、删除确认与离线播放逻辑保持原有行为。
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

### 2026-10-25 下载页样式与布局

仅调整下载中心的展示层，复用共享分类标签和现有主题；下载控制器、仓储、协议、状态流转及删除确认保持原有实现。

- `tool/check.ps1 -SkipPub` 通过：根应用 2696、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2 项，共 3328 项通过；格式、静态分析和打包边界检查通过。10 项 mux 原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，不计为原生封装通过。日志：`build/downloads-style-check.log`。
- 下载页和账号工作区定向 34 项通过，覆盖暂停／重试、删除取消与文件选择、进度动画、窄屏／大字体、离线入口和页面状态保留；最终下载页专项 16 项复测通过。日志：`build/downloads-style-targeted.log`、`build/validation/downloads-style/final-ui.log`。
- 使用应用字体和明暗主题，检查 320／390／600／1000／1440 宽度的队列与完成列表，共 20 张静态渲染；320 宽度同时使用 1.5 倍文字。10 项渲染场景均复查宽窄布局切换后的搜索文字和筛选结果保留，无布局异常。截图与日志：`build/validation/downloads-style/`。这些是 fake 数据的组件渲染，不代表真实窗口或设备验收。

未构建安装包或操作真实客户端；当前没有可连接的 Dart 调试进程，无法执行热重载。Windows、Android、macOS 实际窗口与触控体验仍待运行构建确认。

同日按窄屏反馈，将刷新／设置移至子标签行右侧，内容区 600 及以上仍使用标题右侧布局。下载页与工作区定向 34 项通过；明暗主题的 320／390／599／600／1000／1440 宽度共 12 个渲染场景通过，包含 320 宽度的 1.5 倍文字、599／600 边界、无标题嵌入模式、宽窄切换后的搜索保留，以及窄屏按钮与标签同行的位置检查。输出：`build/downloads-compact-header-targeted.log`、`build/validation/downloads-compact-header/`。仍仅为组件渲染，未打包或实机操作。

此次微调后的 `tool/check.ps1 -SkipPub` 再次通过：3328 项测试、格式、静态分析及打包边界检查通过，10 项 mux 原生测试仍因未配置 `BILI_MUX_LIBRARY` 跳过。日志：`build/downloads-compact-header-check.log`。


### 2026-10-26 Android 默认下载路径校验

Android 默认目录仍由 `getApplicationDocumentsDirectory()` 提供，追加
`BiliSail/offline`；锁定的 `path_provider_android 2.3.1` 通过 JNI 调用
`Context.getDir("flutter", MODE_PRIVATE)`，不是 `/sdcard` 或公共 Download。
旧实现对完整祖先链一直检查到 `/`，把所有非 directory 结果（包括查找失败的
notFound）都报为符号链接，可能误拒绝系统合法路径别名或不可查询的祖先。

组合根向 `DownloadFileStore` 注入 Android 平台提供的应用文档目录作为可信锚点。
只解析该锚点，以及旧任务记录中对应锚点的历史写法；两者必须解析为同一目录。
随后使用 canonical 锚点，从 `BiliSail/offline` 到 scope/task 逐级无链接检查，
先验证父目录再创建子目录。下载子树中的链接（含指向子树内部的链接）不获豁免。
其他平台仍使用原来的全祖先边界；非法任务 ID、`..`、错误目录布局、任意其他
DB 根路径不能借此成为受信目录。

新建、续传、封装文件访问、离线校验和删除共用文件存储校验。文件名白名单、
归属标记、媒体/临时文件链接拒绝和递归删除前子树检查保留。旧任务保留原目录
记录及媒体，不迁移文件、不清设置、不增加系统权限；无法证明属于当前应用
锚点的旧路径安全拒绝。目录缺失/不可访问、非目录和真实链接使用不同提示。

新增文件存储正反向回归与仓储端到端回归：默认创建、平台锚点别名、旧路径
恢复/续传/离线打开/删除、错误根目录和越界、根/scope/task/media/tmp/归属标记
链接、悬空链接与外部文件不变。符号链接测试在 Linux CI 执行；Windows 无额外
建链权限时明确跳过。环境没有 Flutter/Dart SDK，本地仅完成代码审查、WASM
版 dart_style 格式化及 diff 检查，正式格式、分析和测试以分支 CI 为准。

尚未采集用户设备的首次失败祖先或安装验证，不能视作设备问题已复现。
最小诊断应包含版本、Android API、路径来源、脱敏后的平台/实际根路径、首次
失败节点及 no-follow 类型、解析错误码。该修复保持现有基于路径的 I/O 模型，
不宣称消除了拥有目录并发写权限的攻击者造成的检查/使用竞态；若扩展到
不可信共享存储，应另行评估目录句柄/no-follow 原生 I/O 或 SAF 适配。
