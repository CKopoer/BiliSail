# BiliSail（哔帆）开发约定

## 项目状态与入口

- Flutter/Dart Bilibili 第三方客户端，工程名为 `bilisail`，首批交付 Android arm64、Windows x64、macOS arm64；Windows 是当前主要本地开发与原生验证平台。
- 截至 2026-10-18，工程已包含根应用、四个独立包、单/多标签工作区、视频/PGC/直播播放、账号与消息、共享评论和动态互动、云端历史、本地续播、下载与离线播放。功能概览和平台状态见 [README](README.md)；源码版本以 [pubspec.yaml](pubspec.yaml) 为准，不在本文件重复维护版本号，也不将工作区版本等同于已发布版本。
- 仓库已有 Windows 本地/CI 构建、原生媒体及部分安装运行记录，Android 本地/CI 构建和 macOS CI 构建/打包记录。构建记录不代表设备启动、完整账号流程、安装升级、长期稳定性或性能验收；Android/macOS 实机未测项仍按专项记录保留。
- 开始前阅读 [文档索引](docs/README.md)、[整体架构](docs/architecture.md) 和相关专项文档。文档中的 0.1.0、M0、目标目录树等可能是早期快照；判断现状须核对当前源码、锁文件、脚本和对应日期的验证记录。
- [实施与验收](docs/implementation-plan.md) 保留里程碑和退出条件，不再将每项任务视为从 M0 初始化工程。已实现部分 M3–M5 功能不等于这些阶段或三端验收已全部完成。
- 重要选择和改变记录在 [架构决策](docs/decisions.md)。文档默认中文，类型、变量和文件名使用清晰的英文。

按任务补读以下入口，避免只依据首版 [M0 记录](docs/validation/m0-results.md) 判断当前能力：

| 任务 | 入口 |
| --- | --- |
| 播放、弹幕与标签生命周期 | [播放设计](docs/playback-and-danmaku.md)、[多标签播放](docs/validation/multi-tab-playback.md)、[旧单标签导航记录](docs/validation/single-page-navigation.md) |
| 协议、账号与登录 | [API 方案](docs/api-design.md)、[密码/短信登录](docs/validation/password-sms-login.md) |
| 下载、封装与离线播放 | [下载方案](docs/downloads.md)、[bili_mux](packages/bili_mux/README.md)、[封装验证](docs/validation/download-muxing-results.md) |
| 评论与动态共享交互 | [动态互动](docs/validation/dynamic-interactions.md) |
| 快捷键、焦点与 Windows 输入法 | [快捷键实施记录](docs/shortcut-system/implementation-results.md) |
| 滚轮与持久化阻尼设置 | [平滑滚动](docs/validation/smooth-scrolling.md) |
| media-kit 依赖与 Android Surface | [fork 移植与验证](docs/validation/piliplus-media-kit-port.md) |
| 构建、签名与安装包 | [CI/CD](docs/validation/ci-cd.md)、[macOS 启动与安全存储](docs/validation/macos-release-startup.md) |

## 参考仓库

- 相邻 `../biliuwp-lite` 提供功能和交互/模块划分参考；`../bili-kernel` 提供 C#/.NET API 实现参考，后者不是 Rust 项目。
- `../PiliPlus` 用于协议、播放器与弹幕行为参考；采用前核对实际 Git overrides、锁文件和精确提交。PiliPlus 应用的 GPLv3 与其所用 media-kit 分支的 MIT 许可分别处理，不能将应用源码按 MIT 使用。
- 定位源码、提交与采用限制见 [参考文档](docs/references.md)。除用户明确要求外，不修改相邻仓库，不将它们作为需要发布的运行时依赖。
- 当前 media-kit 使用 `Predidit/media-kit` 的固定提交，并非相邻 `../media-kit` 的 path 依赖。弹幕绘制使用固定 `Predidit/canvas_danmaku`；迁移边界见 [切换方案](docs/predidit-media-migration.md)。需要修改 fork 时遵循用户授权范围，应用只依赖已固定、可获取的源码。
- 借鉴职责、协议和模型，避免机械翻译 UWP 控件、静态全局服务或整仓导入。引用代码/schema/资源前记录来源与明确的许可范围。
- 参考 API 不等于在线可用；未做在线验证必须注明。不要把对话中的性能概括当作测量结果。

## 架构边界

1. 根应用按 `lib/features/<feature>/{domain,data,application,presentation}` 组织。`lib/app` 为唯一组合根，`lib/core` 为通用基础能力，`lib/domain` 为共享领域类型，`lib/shared` 放共用映射和 UI。
2. `domain` 保持纯 Dart，不引用 Flutter、Riverpod、Dio、SQLite 或平台插件。Repository 接口属于领域层，实现属于 data。
3. 页面只消费应用控制器与领域状态；不直接发网络请求、访问数据库、解析 JSON/Protobuf 或调用 media_kit。
4. 控制器通过构造器/Provider 注入 Repository 和端口。Riverpod 是默认状态与 DI 方案，go_router 管导航；不另起全局 service locator。
5. 四个独立包的职责见下表；内容身份、账号、队列和业务规则留在主应用，不能下沉到通用媒体包。
6. 独立包只开放公共入口，不导入其他包的 `src/`。包不能反向依赖主应用；Feature 不导入另一 Feature 的 data/presentation，不产生环形依赖。
7. 简单功能直接调用 Repository；只对跨仓储或复杂规则增加 UseCase。按实际需求建文件，不预建空架构或给每个方法套抽象层。
8. 当前不依赖 Rust。只有 profile 数据或明确复用需求时才按决策 D2 评估 FRB；先隔离纯计算，保持单一状态所有者。

| 包 | 职责与边界 |
| --- | --- |
| `bili_api` | 纯 Dart HTTP/Protobuf/WebSocket 协议与远端模型；不持有 UI、数据库或产品设置 |
| `bili_player` | 通用 source/engine 契约、`MediaKitEngine`、`VideoSurface` 和播放控件；不认识 bvid/cid、账号或 Bilibili API |
| `bili_danmaku` | 无网络的点播/直播弹幕调度、布局与绘制；时钟和事件由调用方提供 |
| `bili_mux` | 独立精简 FFmpeg 与 Dart FFI，仅处理本地 MP4/MKV 流复制；不解码、转码、访问网络或复用播放器内部 FFmpeg ABI |

## Dart 与状态约定

- 文件/目录 `snake_case`，类型 `UpperCamelCase`，成员 `lowerCamelCase`。启用 sound null safety，边界检查空值，不用 `dynamic` 或强制 `!` 掩盖协议问题。
- 对外模型不可变；JSON/Protobuf DTO 不泄漏到 UI。简单类型直接编写，生成工具按需要引入，生成文件不手改。
- 名称表达职责，例如 `VideoRepository`、`SearchController`、`VideoScreen`、`MediaKitEngine`。注释解释原因、单位和约束。
- 外部 ID 使用明确值类型，传输/落盘避免浮点数转换；时间内部用 Duration 或标明毫秒的字段。
- 异步操作必须有取消、超时和错误分类。不要用宽泛 catch 返回空成功；取消不弹通用错误提示。
- 账号请求携带 account scope/session epoch，搜索携带 query generation，播放携带 source generation；旧响应不能改变新状态。
- 明确释放 StreamSubscription、Ticker、Timer、isolate、WebSocket、播放器和文件句柄。不要用页面销毁意外终止进程级任务。
- 高频 position/弹幕更新只影响局部绘制，禁止经全局 Provider 逐帧重建页面。

## 工作区、设置与共享交互

- 工作区共用页面身份、访问历史和 PageStorage；切换标签或导航模式保留未关闭页面的状态。页面缓存上限 16、访问历史上限 64，不引入无界页面保留。
- 首页、动态、直播、我的、消息、下载、设置共用固定根标签，一级切换不新增可关闭标签，已访问分支分别保留状态。双标签返回关闭离开的临时浏览页；播放返回优先媒体历史，历史为空关闭播放窗并释放会话。页内详情与模态返回保持优先，根页面不能关闭。
- 导航提供单／双／多标签；平台默认值集中在 `lib/app/platform_defaults.dart` 并注入设置仓储。2026-10-25 按用户后续要求恢复单标签并设为 Android 默认，其他平台默认双标签；保留已保存的所有有效选择，旧 `singlePage` 直接恢复。单标签按实际访问顺序返回，出栈仅释放不再被历史引用的临时页；播放进入 UP 空间等页面后返回沿用原会话。默认值只影响缺失／非法配置。
- `WorkspaceActivity` 表达页面可见性，不代替播放所有权。隐藏页面停用绘制、媒体 surface 和快捷键；关闭页面取消其拥有的请求并释放对应播放会话。系统后台与应用内切页分别处理。
- 设置沿用 `AppSettings`、设置控制器和 `SqliteSettingsRepository`；可调项按既有流程保存并立即应用，保存失败保留或回退已保存配置。默认、恢复默认、非法值回退和迁移须一致，不能覆盖有效旧值。
- 跨视频/PGC/直播、普通/全屏的相同行为优先修改共享会话或组件。视频与动态评论复用 `lib/features/comments` 和 `lib/shared/ui`，以 `CommentTarget(oid, type)` 区分身份；不复制页面专属的协议/交互实现。
- 快捷键与侧键共用根 Navigator 外的 `AppInputHost`、纯 Dart `core/input` 分发器和显式作用域；保留编辑保护、模态隔离及普通/全屏同一播放 owner，不增设页面级业务全局监听。
- Windows IME 由同一输入宿主和 `windows/runner/window_ime_context.h` 协调：编辑焦点保留当前关联，缺失时恢复系统默认上下文，非编辑焦点解除关联，窗口重新聚焦/恢复活动时重新核对。不缓存跨输入法切换的借用 HIMC；原生消息注入不能代替真实候选、组合与中文提交验收。
- 桌面滚轮集中在 `lib/shared/ui/smooth_scroll_behavior.dart`，使用 Flutter `ScrollSpringSimulation`；保留信号仲裁、嵌套边界接管、Shift 换轴、触摸/触控板、减少动画和 PageStorage。阻尼经共享 `SmoothScrollScope` 应用，实际手感需用户在运行构建中确认。
- `NetworkAvatar` 在首帧加载前保持固定尺寸空白，无 URL/错误时保留后备内容；不要把加载态改成会切换内容的头像。播放页简介/标签折叠与整个信息区显隐是两个状态，修改时保留各自展开和交互语义。

## API 与凭据

- 按 [API 方案](docs/api-design.md) 接入端点：登记 profile、host/method、鉴权、签名、响应格式、分页与重试规则。
- 当前优先 Web Cookie/WBI/CSRF。HTTP Protobuf 不等于 gRPC；App/TV token 不可由 Web 会话凭空假定存在。
- 登录入口复用 `SessionRepository` 的 Cookie 校验、`/x/web-interface/nav` 验证、安全存储和会话提交；扫码及内嵌官网登录遵守同一 epoch、取消和旧响应隔离规则。风控/验证码按服务端流程处理。
- 参数只编码一次；WBI/key 刷新与账号刷新各自单飞。可重试读请求设置总次数和 deadline，不允许多层无限重试。
- 点赞、投币、收藏、发送等操作仅由明确用户动作触发；结果不明的写请求不得自动重放。
- 凭据用 CredentialStore/系统安全存储；禁止写入日志、普通 JSON、SQLite、fixture、设置导出或源码。安全存储失败不得退回明文。
- Cookie 遵守域/path/secure/expiry，重定向不得泄漏凭据；保留系统 TLS 验证。禁止采用参考源码的无条件证书接受回调。
- 数据缓存按账号隔离；登出取消请求、上报、WS 与依赖账号的任务，清理凭据和私有缓存。离线媒体与普通缓存区分。
- 默认不添加自动遥测。诊断须过滤 token、Cookie、二维码 key、URL query 和 native 播放器日志中的敏感数据。

## 播放、弹幕与平台

- 遵守 [播放设计](docs/playback-and-danmaku.md)。视频、PGC、直播及离线播放共用契约，每个播放标签只拥有一个 `PlaybackSession` 和 engine；主应用通过 `PlayerEngine`/`VideoSurface` 使用播放器，不直接调用 media_kit。
- 只有多标签且 `allowConcurrentPlayback` 开启时允许不同标签同时播放；双标签或关闭并发开关时由 `PlaybackManager` 先完成旧会话暂停，再允许目标播放。导航暂停保留源、位置和用户意图，手动暂停不得自动恢复；关闭标签只释放自己的会话，账号变化停止全部会话，退出等待原生释放完成。
- 点播必须验证 DASH 音视频分轨；不能把视频 URL 单独可播视作完成。原生播放器请求不经过 Dio，需要独立设置并验证 headers/Range/重定向。
- seek、换清晰度、换 P、URL 刷新都要隔离旧事件并保留用户播放意图；全屏/布局改变不得产生第二路音频。
- 点播弹幕按确认的播放位置加载/触发，动画时间独立控制滚动与停留；暂停/缓冲冻结、seek 重建、倍速语义不能混用。直播按单调到达时间调度；沿用当前随刷新率运行的 Ticker，不将已撤回的合帧实验当作现行实现。
- 弹幕、聊天、解压任务、文件缓存均需容量上限和降级规则。复杂解码在 isolate，Flutter 绘制留 UI isolate。
- 平台差异放在小型 PlatformServices/适配器，通过 capability 显示入口；不在业务代码到处判断 OS。
- 后台播放、PiP、媒体键、硬解和后台下载均需逐平台验证，不能从插件支持列表推导成项目已支持。

## 存储、依赖与生成

- SQLite migration 必须增版本并有迁移验证；禁止靠清空用户数据完成升级。数据库 schema 与 `preferences.v1` 等 JSON 快照版本分别管理；当前定义以 `AppDatabase` 和对应仓储为准，增加设置字段不必然改表。
- 下载队列由进程级仓储持有，页面关闭不停止任务；账号变化暂停旧任务，重启等待用户显式继续。校验 206/Content-Range、文件完整性及 URL 刷新后的资源身份，不将带签名 URL 或凭据落盘。
- 下载文件、manifest 与 SQLite 按可恢复的提交顺序处理；分轨/MP4/MKV 均需兼容已有任务及离线打开。封装在 worker isolate 执行，取消、临时文件清理、校验和原子发布由下载仓储负责，离线媒体不受普通缓存清理影响。
- 工程固定 Flutter **3.47.6 stable / Dart 3.13.5**，以 `.flutter-version`、检查脚本和 CI 配置共同约束；升级须同步这些入口及验证记录。直接依赖使用精确版本，提交根应用和四个包的五份 `pubspec.lock`。
- media-kit fork 的 Git ref 必须固定完整提交；更新时同步根应用核心 override、`bili_player` 的核心／视频依赖及核心 override，以及两处锁文件。Native Assets 已替代旧的 `media_kit_libs_*`，不再维护旧七处 ref。保留根应用的 overrides，Pub 不会采纳传递依赖包的 overrides；弹幕依赖更新同步根应用与 `bili_danmaku` 锁文件。
- 原生 libmpv 由固定 media-kit 的 `hook/native_bundles.json` 和构建钩子校验／打包。Windows 使用匹配的 DXGI DLL 与 D3D11 输出，不启用历史 `windows/native/mpv.cmake` 的 ANGLE 库覆盖。渲染/释放补丁由 `windows/patches/media_kit_video/apply.cmake` 校验源码并应用到构建副本。不得修改 Pub 缓存或绕过来源/哈希校验；依赖升级需重新审查补丁兼容性。
- `bili_mux` 原生资产按其 README 从固定源码构建，不能借用系统 FFmpeg 或播放器私有库；预构建资产不提交 Git，分发保留许可、来源和可重建材料。
- 新依赖先确认目标平台、维护接口、二进制依赖和许可；选择能满足具体需求的最小组合。
- 生成器/schema 记录版本、命令和来源；提交项目需要的生成物，改源后重生成，不手修输出。

## Android 本地开发测试包

- 后续连接设备的本地开发测试统一使用独立包名 **`dev.bilisail.bilisail.test`**，桌面名称 **`BiliSail 测试版`**；Debug、Profile、Release 都使用这个身份。历史 `.primaryswitch` 临时包不再用于后续测试，不自动卸载或迁移它的数据。
- 开发测试包可与正式包 `dev.bilisail.bilisail` 共存，私有账号、数据库和缓存按 Android 包隔离。除用户明确要求正式包安装/升级验收外，不将本地测试构建安装到正式包名，也不复制正式包凭据。
- 构建入口为 `tool/build-android-development.ps1`，默认 **Release**，默认构建 Android arm64 mux；例如 `./tool/build-android-development.ps1 -Mode Release -Install -DeviceId <adb-device-id>`。Debug/Profile 仅在对应调试/采样需要时显式选择；普通入口固定 `lib/main.dart`。
- 底层构建参数固定 `--android-project-arg=bilisailDevelopmentBuild=true`，统一添加 `.test` 和测试版名称。参数默认关闭；CI/正式打包不传该参数，仍沿用现有正式包名、名称和签名边界。开发 Release 是实际 Release/AOT 构建，使用本机开发签名，仅供本地测试，不作为正式发布包上传。
- 此构建入口不能加 `--no-pub`：Flutter 3.47.6 会同时跳过原生插件注册文件重生成，Profile/Debug 与 Release 切换时可能留下 integration_test 等 dev-only 注册，导致 Release 编译失败。使用 Flutter 自身生成流程，不手改 GeneratedPluginRegistrant。
- 三种模式沿用同一本机 Android debug keystore；本机默认位于 `%USERPROFILE%/.android/debug.keystore`。不得删除、重新生成或随意更换已有开发签名，否则无法保持覆盖升级和数据。脚本记录证书指纹；跨机器签名不同须先厘清已有签名，不能通过卸载绕过。
- 安装前校验 APK 的实际包名、名称、版本和签名，Release 还须确认不可调试；覆盖安装使用 `adb install -r`。安装失败时保留原应用，不自动卸载、不执行 `pm clear`、不强制降级，不让 Flutter 的自动重装流程清除测试数据。
- 集成测试也统一使用此别名，`flutter drive` 必须带 `--keep-app-running`，避免默认结束流程卸载应用。使用 fixture 入口前构建并保留当前普通入口的开发 Release APK；测试后在 `finally` 中覆盖恢复普通入口，保留已有数据。底栏基准使用 `tool/test-android-primary-switch.ps1`，不能把 fixture 包留作用户日常测试入口。
- 测试 APK、SHA-256 和构建元信息保存在 `build/development/android-arm64/`；Release 固定文件名为 `BiliSail-test-arm64-release.apk`。临时屏幕常亮等设备设置必须记录原值并在结束后恢复。

## 检查与交付

代码改动运行根检查脚本，覆盖根应用与四个包的格式、静态分析、离线测试及打包边界脚本：

```powershell
.\tool\check.ps1

# 依赖已解析且此次未变更时可跳过 pub get
.\tool\check.ps1 -SkipPub

# 与 CI 一致，验证锁文件可复现解析
.\tool\check.ps1 -EnforceLockfile
```

- 分别运行检查时，`bili_api` 使用 `dart analyze/test`，根应用与另三个包使用 `flutter analyze/test`；各包还需检查自己的 `lib/test` 格式。根应用测试不替代子包或原生集成测试，具体命令以 `tool/check.ps1` 为准。
- 纯文档改动只检查相对链接、源码路径、术语/阶段一致性和 `git diff --check`，无需运行 Flutter 全套或构建。
- 只读文档或低风险样式变更不强制新增测试；协议、会话竞态、播放状态机、存储迁移需要行为测试。
- 优先 fake clock/transport/repository/player 和脱敏 fixture。正常 CI 不使用真实账号，不自动执行投币/发送等账户写操作。
- Windows 受控媒体回归使用 `tool/test-windows-media.ps1`，PGC/直播相关使用 `tool/test-windows-content.ps1`；公开在线烟测用脚本的 `-Online` 显式启用。原生释放改动补跑 `tool/test-windows-video-dispose.ps1`，输入法改动补跑 `tool/test-windows-ime.ps1`，其他测试按受影响路径选择。
- 普通检查未配置 `BILI_MUX_LIBRARY` 时会跳过 mux 原生用例，必须如实报告。完整原生回归按包 README 准备组件及 `BILI_MUX_FFPROBE` 后执行，不能把配置跳过算作原生通过。
- 原生播放改动至少在受影响平台构建并实机验证；三端验证记录与未测项均写明。性能用 profile/release，不能用 debug 帧率作结论。
- Flutter 构建前按 [bili_mux 说明](packages/bili_mux/README.md) 准备目标原生资产，例如 `.\tool\build-download-mux.ps1 -Target windows-x64`；`tool/build-release.ps1` 已包含组件构建与安装包流程。Windows Release 入口为 `build/windows/x64/runner/Release/bilisail.exe`，分发须保留整个 Release 目录。
- 构建按主机执行 Windows、Android、macOS 目标；工具链或设备不可用时准确报告，不能声称通过。
- 用户明确要求自行构建、实机确认或暂不测性能时遵循该范围，完成授权的自动检查并列明余下验收。测试、构建、实际设备操作和性能测量分别报告；历史通过记录不代表当前工作区已通过。
- 开始和交付前检查 `git status`，保留用户已有及同期修改；提交时只包含本任务文件，不为凑全量通过而改动无关代码。全量检查若被既有问题阻塞，记录具体失败和已完成的定向验证。
- 完成后说明改动、验证结果、未验证部分；重要边界变化同步 docs。保持用户已有修改，不顺带重排或迁移无关代码。

