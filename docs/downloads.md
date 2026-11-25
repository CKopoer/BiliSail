# 下载与离线播放方案

日期：2026-10-07。下列是本轮实施方案，验收结果另列于文末；不能从参考项目或插件支持列表推导三端后台下载已完成。

2026-10-09 按用户选择接入独立精简封装组件与“合并为单个 MP4”选项；保留分轨方式和旧任务。依赖核对见[文件封装能力评估](validation/download-muxing-evaluation.md)，实现与手动构建步骤见[合并验收记录](validation/download-muxing-results.md)。

2026-10-11 下载窗口改为“保存格式”：音视频分轨／合并 MP4／合并 MKV。两种封装使用同一精简组件、取消与提交链路；合并文件按单文件媒体打开，修复旧 MP4 被当作缺音轨 DASH 而报“未取得点播音频轨道”的问题。旧 MP4 完成项无需重新下载；本轮验证见[封装与离线播放修复](validation/download-muxing-results.md#mp4-离线播放修复与-mkv2026-10-11)。

## 功能与界面

离线播放页复用视频／影视的宽窄屏布局，可浏览当前作品和全部下载；新下载保存本地简介、合集归属与季类型。下载中心的已完成项可按全部／视频／番剧／国创／影视筛选。新旧任务兼容与切集规则见[离线播放页设计与实现](offline-playback-page-design.md)。

- 普通视频按分 P、影视按可播放剧集多选。下载弹窗根据当前账号实际返回的 DASH 视频轨道列出画质和对应编码，并要求有可下载的 AAC 音轨。多选时只提供每个分 P 或剧集都有的画质与编码组合。任务开始时重新核对所选轨道，已失效的组合会提示不可用。
- 新下载默认选中「合并 MP4」，也可选「音视频分轨」或「合并 MKV」。封装组件不可用时预选「音视频分轨」。
- 下载中心沿用当前 Material 3 主题、粉色强调色、圆角、封面比例与字体。2026-10-25 统一为消息／设置页的顶部标题和下划线分类标签，队列／已完成标签各自显示数量。嵌入“我的”页时，刷新／设置入口始终与分类标签同行并靠右。独立下载页的内容区宽度小于 600 逻辑像素时，操作入口也与分类标签同行，达到 600 时则位于标题右侧。大字体下分类标签可横向滚动，两个操作入口保持可见。搜索与批量暂停／继续在宽屏同排、窄屏或大字体下分行；窗口宽度变化保留搜索文字。任务卡分层显示标题、分 P／剧集、画质／编码／格式、状态、字节、速度与进度，宽屏将状态和操作同排，窄屏操作区换行。全部颜色复用现有明暗主题；下载、筛选、批量操作、删除确认与离线播放逻辑保持原有行为。
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

macOS 构建、Android/macOS 设备离线播放、真实登录账号/会员 PGC 下载、公网长视频断网/休眠恢复和发布窗口鼠标操作尚未验收。当时的 Android 版本在退入后台时主动暂停下载。当前行为见[移动端后台下载](#移动端后台下载2026-11-22)。暂停或重启后的资源若缺少强 ETag，会保留记录后安全从头重新下载该轨，避免拼接不同对象。

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
默认路径直接使用平台给出的锚点，不强制 realpath，以免解析本身再次查询受限
系统祖先。仅当旧记录使用不同锚点写法时，解析双方并要求指向同一目录；解析
失败不放宽。所有 I/O 使用平台锚点，从 `BiliSail/offline` 到 scope/task 逐级无链接检查，
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


## 2026-10-26：离线播放不做内容完整性门禁

按用户取舍，完成、打开、刷新和初始化不再读取完整媒体计算 SHA，也不比较完成文件的历史大小或修改时间。旧摘要仅兼容读取；新轨道以 committed 标识落盘提交，旧摘要非空记录兼容为已提交。用户修改媒体后仍交给播放器尝试，分轨缺失显示具体轨道错误。

账号和任务归属、受限文件名、符号链接及删除边界继续生效；HTTP Range/ETag/响应长度仍用于传输正确性。私有临时文件刷新关闭及改名后才记录提交，不因播放器错误删除文件。旧文档中的“打开时完整校验”由本节取代。

新增/调整回归覆盖分轨修改、刷新和重启、合并文件修改、原分轨清理及缺音轨错误。当前执行环境无 Flutter/Dart SDK，SDK 下载代理返回 HTTP 403；本地仅做 WASM Dart 格式预检和差异检查，正式分析/单测由分支 CI 验证。Android 实机未验证。

原生合并器也取消了写完后重读整个输出并比较压缩包 SHA 的运行时强核验。保留封装所需的输入轨道/编码识别、包大小限制、读写和 trailer/close 错误、取消及截止时间。CI 原生封装回归仍独立比较音视频包内容/时间戳，用于验证实现正确性，不作为用户媒体的播放门禁。


## 2026-10-26：Android 公共保存位置

首次下载只提供文件夹选择，不再提供默认 Downloads/BiliSail 或推荐保存位置。应用内选择器复用 Material 主题、粉色强调色及明暗外观，浏览内部存储和可用外部存储，支持进入文件夹、返回上一级并明确确认当前文件夹；取消不添加任务。用户选择持久保存，设置修改仅影响新任务；旧任务不迁移。

Android 11+ 的 SAF 即使获得“所有文件访问权限”也不能选择 Downloads 根目录，因此本轮按用户要求采用获得存储授权后的本地文件夹浏览器。Android 11+ 在系统设置页申请 MANAGE_EXTERNAL_STORAGE，并在返回后通过 Environment.isExternalStorageManager() 确认实际状态；Android 6–10 申请 READ/WRITE_EXTERNAL_STORAGE（maxSdkVersion=29），Android 10 使用 requestLegacyExternalStorage。拒绝、撤销或不再询问时显示重新授权入口，未授权不读取文件夹或保存新位置。权限申请仅由打开文件夹选择流程触发，不在启动时申请。依据 [Android 所有文件访问](https://developer.android.com/training/data-storage/manage-all-files) 和 [SAF 目录限制](https://developer.android.com/training/data-storage/shared/documents-files#document-tree-access-restrictions)。

私有 .part 维持续传和原生合并，最终媒体流式写入用户确认的文件夹，使用 <taskId>_video.m4s / audio.m4s 或合并文件；不额外创建 BiliSail 默认目录。选定前用独占临时文件检查写入能力，随后清理探针；创建媒体也使用独占创建，不覆盖现有文件。平台返回的共享存储根作为可信锚点，仅遍历其下目录，拒绝点路径、符号链接及 Android 私有目录。每次最多显示 2000 个子文件夹并提示截断。原生私有日志逐个记录创建的 URI，失败保留原文件，重试只清理自己的未提交条目；已发布记录重复调用返回原 URI。SQLite 持久保存 URI 后才清理私有媒体，字幕/弹幕及归属信息仍私有。旧 MediaStore/SAF 任务继续按原有 URI 读取与删除，旧默认目的地不再用于新任务，必须重新明确选择文件夹。

Android 新下载的合并 MP4／MKV 在关闭目标文件并提交发布记录后，请求系统扫描原目录中的视频。分轨文件不触发扫描。可导出的核心日志以 `downloadMediaScan` 记录格式与结果（返回媒体 URI、未返回 URI、请求异常或 15 秒无回调），不记录文件路径或媒体 URI。扫描异步完成，失败不影响下载和离线播放。

2026-11-22 在 Android 16 模拟器验证，两种合并格式均从所选目录进入 `MediaStore.Video`，且分别记录一次扫描结果。分轨文件和重复发布未产生扫描事件。荣耀 Android 17 实机图库仍待验证。

新任务通过本地 file URI 播放；旧公共任务继续通过 ContentResolver 只读 FD，主视频及外部音轨分别持有句柄直到 mpv 释放；不在播放前复制媒体。仅支持可 seek 的提供者，流式管道给出明确错误。原生仅打开本应用发布日志中的 URI；删除检查选定文件夹及精确任务文件名，旧任务检查 MediaStore 相对位置或 SAF 子树归属，不递归公共目录。存储撤销、离线、空间不足保留任务和可恢复私有源。公共文件通常保留至卸载后，但任务数据库和授权不恢复；没有自动重新导入功能。

发布阶段需额外写出及峰值双份空间；多轨发布不是跨文件原子事务。提供者创建成功到私有日志落盘之间存在系统 API 无法原子提交的极小窗口，进程在此时终止可能留下孤立条目，应用不会通过广泛扫描/删除来冒险清理它。

验证包括仓储公共提交/重启/授权恢复/发布失败重试，以及播放器双轨 FD 生命周期测试。

本轮在 master 整合原 feat/android-public-downloads 分支并修复选择器：

- 下载选择器、下载页面、仓储、文件边界和离线播放定向测试 77 项通过；Windows 缺少建链权限，13 项符号链接测试明确跳过。新选择器覆盖无默认位置、授权先于浏览、拒绝后重新授权、明确选择 Downloads 根目录、上一级导航、保存失败重试、取消和重复操作保护。320/390 宽度的明暗主题共 4 张静态预览通过，320 使用 1.5 倍文字；输出在 `build/validation/android-download-folder/`，日志 `build/android-download-targeted.log`。
- 下载相关 Dart 文件和新增设备测试静态分析无错误；相关格式与 `git diff --check` 通过。四个包共 641 项测试通过（bili_api 460、bili_player 83、bili_danmaku 93、bili_mux 5）；10 项 mux 原生测试未配置 BILI_MUX_LIBRARY 而跳过。日志 `build/android-download-package-tests.log`。
- Android arm64 的 mux 组件重建及完整应用 Debug APK 构建通过，日志 `build/android-download-mux-build.log`、`build/android-download-apk-build.log`。Android 16/API 36 x86_64 临时只读模拟器中，选定 Downloads 根目录后的真实发布/读取/重复提交/精确删除，以及旧 MediaStore 发布/只读 FD/删除，共 2 项集成测试通过；不存在账号或网络写操作。第二轮还观察到真实系统授权设置页打开，再由测试宿主授予该模拟器的 app-op 并关闭设置页，原生返回后继续测试；这不等同于用户手动切换权限或厂商系统实机验收。日志 `build/android-download-device-test.log`、`build/android-download-permission-activity.log`。
- 模拟器暴露旧 MediaStore 条目尚未首次打开写入流时无法读取的问题，现先创建底层文件再检查可 seek，仍在复制媒体之前拒绝流式提供者。
- 已执行 `tool/check.ps1 -SkipPub`，被同期其他任务文件的格式检查阻塞；单独运行根测试为 2852 项通过、13 项跳过，`primary_switch_layout_test.dart` 的保留页面尺寸断言失败（390×682 与 390×734），属于同期导航改动，未修改这些文件。日志 `build/android-download-check.log`、`build/android-download-root-tests.log`。本轮无可连接的 DTD 调试进程，未执行热重载；原生改动需重新安装构建。

Android 6–10 权限窗口、厂商 Android 实机、可移除设备/拔出恢复和实际媒体解码仍需验收；不将 mock、模拟器或编译结果视为这些项目通过。

## 移动端后台下载（2026-11-22）

进入后台或锁屏时，下载队列继续处理当前任务和后续排队项。手动暂停、账号切换和进程重启仍沿用原有的断点恢复流程。各平台添加下载成功后的底部提示停留 1.5 秒。

Android 在首项任务运行前启动 `dataSync` 前台服务，向系统发布下载通知，并在传输、封装及发布期间持有部分唤醒锁。通知的可见位置取决于系统版本及通知权限。并发任务共享服务，最后一项退出时释放。Android 15 及以上的系统后台运行配额耗尽时，服务退出并请求队列保存断点。

iOS 在应用可见时沿用流式下载。切入后台时，当前轨道从已写入的断点交给系统后台 `URLSession`，后续轨道按队列继续调度。系统会话管理临时请求，应用的任务索引只保存轨道身份和断点。只有强 ETag 匹配时才拼接分段。系统临时响应经原有范围和长度校验后写入任务文件。iOS 决定后台传输的调度时机，挂起期间的本地封装或发布会在系统再次给应用执行时间时继续。结束进程后沿用重启等待手动继续的规则。

## iOS 自动导入下载视频到相册

iOS 的下载保存在应用 Documents 中，可通过「文件」应用访问。系统「照片」使用独立的媒体库。用户添加或继续合并下载时，在前台按需请求仅添加权限。合并文件写完并提交下载记录后，系统检查视频兼容性并在已授权时自动创建相册副本。原文件保留，分轨任务不导入，旧的已完成任务不补导入。MKV 或部分 MP4 编码若被系统拒绝，可改用 H.264 编码的合并 MP4。

核心日志以 `downloadPhotosExport` 记录容器格式和系统导入结果。没有权限、格式不兼容或导入失败时，合并下载照常完成。后台导入依赖 iOS 分配给应用的执行时间。iOS 构建、权限弹窗与系统相册显示需 Apple SDK 和设备验证。

## 长列表浏览与页面生命周期

完成列表在缩略图进入视口并绘制后才安排本地读取，每个页面最多同时处理两个缩略图。离开视口的等待项在开始前重新核对，切页或销毁时释放等待项。已开始的读取占用名额至完成，旧封面结果仅能更新仍挂载且身份匹配的组件。Flutter 的图片缓存负责复用解码结果。

完成列表最多复用 512 条已测量的行高，窗口宽度、字体、布局或列表内容变化后重新测量。卡片由视口按需构建。下载页隐藏时暂停界面订阅，保留搜索词和滚动状态。可见的返回预览恢复界面订阅，封面读取等到页面激活。字节数、速度和进度条各自处理进度更新。仓储继续持有后台任务，并复用按创建时间排列的任务 ID。
