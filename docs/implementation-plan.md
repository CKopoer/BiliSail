# 实施计划与验收

日期：2026-10-05。已开展 M0 Windows 验证并实现 M1 工程基础与部分 M2 观看闭环，交付 0.1.0 本地预览版；三端 M0、完整 M2 和 M3–M5 未验收。实际证据见 [M0 实测记录](validation/m0-results.md)。

按用户要求提前接入 M3/M4 中的影视选集与直播内置观看，前序 Windows 播放与平台构建证据见 [影视与直播内置播放](validation/content-playback.md)。影视弹幕/发送和直播实时消息已接入，当前证据及未测项见 [影视与直播弹幕修复](validation/pgc-live-danmaku.md)。三端稳定性、真实账号写入及会员/地区权益仍待验收，不改变下列阶段的完整退出条件。

## M0：技术验证

头像菜单与 Web 消息系统也已按用户要求提前接入。五类收件箱、文本私信和显式已读的实现与 Windows 只读实测见 [账号菜单与消息](validation/account-messages.md)；真实写操作、Android/macOS 和推送尚未验收，不改变下列阶段的退出条件。

目标是解决最可能推翻选型的风险。先建立最小 Flutter 验证工程和必要的包，不先铺设全部页面。产出包含代码、脱敏 fixture、固定版本与三端验证记录。

| 验证项 | 工作与验收出口 | 失败处理 |
| --- | --- | --- |
| 工具链与二进制 | 固定 Flutter/Dart、三个 media_kit 包和原生二进制；Android arm64、Windows x64、macOS arm64 分别成功构建启动 | 确定最低 OS/ABI，记录缺失 runner；未跑的平台保持待验 |
| Web 会话 | 扫码、过期/取消、nav 校验、安全存储恢复/退出；凭据不会出现在日志 | 修复 Web 会话；不默默混入 TV token |
| API 闭环 | guest/signed-in 的搜索、详情、playurl、字幕/弹幕协议解析 | 登记失败端点与能力降级；基础闭环失败不得进入 M2 |
| 音视频分轨 | 三端 video+audio 正常同步；带 headers、Range、seek、暂停、倍速、备用 URL | 先评估 MPD 适配，再对比 fvp；记录同一测试矩阵 |
| 直播 | HLS、HTTP-FLV、断网恢复、房间下播；消息独立断开/重连、压缩消息 fixture | 已验证的协议作为默认；不支持能力明确关闭 |
| 密集弹幕 | 视频同时播放，100 条/秒输入、最多 120 条可见、10 分钟；seek、暂停、2 倍速 | 先调度/密度/缓存优化，再比较现成渲染器或 Rust 算法 |
| 原生生命周期 | 全屏/旋转、后台/前台、音频焦点、休眠恢复、释放后重开 | 在平台适配层修复；不得遗留后台音频或句柄 |
| 持久化 | 三端安全存储、SQLite、应用文件目录；版本化凭据异常恢复 | 不退回明文凭据；调整支持下限或插件 |
| 依赖来源 | 记录原生库版本、获取来源、校验、许可；确认参考代码/资源可采用范围 | 未明确前只参考结构，不直接复制有疑义的内容 |

M0 退出条件：三端完成基础点播验证，选定后端与分轨策略，基本 API/认证闭环可用；所有阻塞问题有解决结果。直播/特定 codec 若暂不支持，必须明确缩小 M3 能力，不能标记为已支持。没有 macOS runner 时可以继续独立的 Dart 工作，但不能声称 M0 三端验收完成。

M0 的实际测试结果记录在 [m0-results.md](validation/m0-results.md)。失败修复和未测项必须同时记录；如果后端改变，同步更新决策 D3。

## M1：工程基础

在验证工程上建立正式 AppShell、三个包的边界、Riverpod 注入、go_router、主题、响应式导航、结构化错误/日志、SQLite 迁移、安全存储、设置和 CI。

完成一条 fixture 驱动的“列表 → 详情 → FakePlayerEngine”流程；建立会话 epoch、取消和分页约定。外部链接只转换为已知目标，不直接执行 query 中的操作。

验收：三个包能独立检查/测试；根应用能在三端构建；窄屏/宽屏、字体缩放、键盘导航与返回栈通过；没有真实账号也能运行离线演示和测试。

## M2：UGC 观看 MVP

按完整纵向功能交付，而非先写完所有 API：

1. 游客首页/搜索 → 视频详情/分 P → 解析播放 → 暂停/seek/倍速/清晰度/全屏。
2. Web 扫码与会话恢复 → 权限显示 → 退出和重新登录。
3. 分段弹幕、字幕、屏蔽/密度设置 → 本地续播与异常恢复。

验收：新安装可游客使用；正常与错误路径有 UI；账号切换/退出后旧数据不回写；普通 UGC 连播 30 分钟、快速换 P/seek 和窗口调整没有持续内存增长或双重音频。MVP 不依赖云历史上报成功。

## M3：直播与日常功能

直播列表/房间、聊天室与弹幕、线路选择、重连/下播；加入收藏、稍后再看、云历史、UP 主、动态只读和评论阅读。互动操作都由明确用户动作触发，失败恢复不重复提交。

验收：视频和消息故障隔离；用户手动关闭房间后不再重连；三端 30 分钟直播稳定；缓存按账号隔离；云同步离线恢复无重复写操作。

## M4：下载、PGC 与系统集成

下载暂停/恢复/校验、重启恢复、离线 manifest、本地分轨播放；PGC 权限/选集适配；按平台验证媒体键、后台音频、文件导出与 PiP。未通过的能力保持关闭。

验收：200/206/416、URL 过期、磁盘不足、强杀/重启、文件损坏、目录权限变化均有可恢复行为；会员/地区限制正确展示；不允许用户误删离线媒体时只显示“清缓存”。

## M5：发布稳定化

三端发行构建、更新包完整性验证、诊断导出、第三方 notices、升级回归、最终性能基线。先支持应用内提示下载已发布版本；静默自更新和平台商店投放另行设计。

发布包有版本号、源码 revision、SDK/依赖锁定、校验值。Windows 安装/卸载、Android 签名升级、macOS 签名/notarization 与文件访问权限在相应环境完成；签名材料只在发布环境提供，不进入仓库。

## 测试分层

| 层次 | 核心测试 |
| --- | --- |
| 纯 Dart 单测 | 协议模型/签名、分页、失败分类、取消、会话刷新单飞、直播包/压缩、弹幕时钟/轨道碰撞、任务状态迁移 |
| Repository/存储 | DTO 到领域、过期缓存、scope/epoch 隔离、SQLite 升级、下载一致性恢复 |
| Widget | 加载/空态/错误/重试、宽窄布局、字体缩放、焦点、路由/深链、播放控件 |
| 集成 | 登录关闭时取消、换 P 与旧请求竞态、全屏不重建后端、离线恢复、权限提示 |
| 三端实机 | 原生解码、音频设备、窗口/旋转/后台、系统存储、30 分钟播放、发行包启动 |
| 性能 | 同一 fixture/媒体输入比较 UI/raster 帧时间、解码掉帧、native/Dart 内存、CPU/GPU、首帧与 seek |

纯 Dart 包使用 `dart test`，含 Flutter 的包和根应用使用 `flutter test`。测试 UI 与播放器编排尽量注入 fake clock、fake transport、fake repositories、FakePlayerEngine，避免普通单测加载原生视频库。

CI 默认不接真实 Bilibili 账号；fixture 必须脱敏。访问真实服务的测试显式选择、低频只读；不把投币、发送评论或弹幕等变更账号的操作作为自动回归流量。

## 性能预算与记录

以下是**初始验收目标**，M0 选定真实设备后测量、记录并修订，不能作为产品宣传数据。默认参考 60 Hz 显示，Flutter 使用 profile 模式分析、release 模式做最终媒体测试。

| 场景 | 初始目标 | 测量条件 |
| --- | --- | --- |
| 列表滚动 | UI 与 raster 各自 p95 ≤ 16.7 ms | 固定 1,000 条 fixture、封面缓存状态注明、连续滚动 60 秒 |
| 视频+弹幕 | UI/raster 各自 p95 ≤ 16.7 ms；解码掉帧单独记录 | 1080p60 H.264/AAC、100 条/秒、最多 120 条可见、10 分钟 |
| 本地/受控源首帧 | p95 ≤ 1.5 秒 | 30 次打开；区分热/冷、轨道就绪与首帧；不包含扫码/API 时间 |
| 受控源 seek | p95 ≤ 1 秒恢复画面 | 30 个固定位置，含前跳/后跳；后端确认定位 |
| 长时间资源 | 30 分钟无持续增长；关闭后 60 秒资源回落接近热稳态 | 记录 Dart heap、native RSS、decoder/texture/订阅数量；缓存预热后比较 |
| 故障恢复 | 退避/次数有上限，退出后任务归零 | 断网/过期 URL/WS 断开/磁盘满场景 |

公网首帧耗时另按“API 解析 / DNS+连接 / CDN 缓冲 / 解码首帧”拆分，记录网络条件，不把网络波动归因于 Flutter。硬解必须记录实际 decoder 或后端诊断证据，不用 CPU 低推断全部 codec 已硬解。

每份验证报告包括：日期、commit、SDK/依赖/native binary 版本、OS/CPU/GPU/RAM/显示刷新率、设备真机或模拟器、网络、输入样本说明、步骤、次数、原始统计、失败与未测项。M0 首次选 Android 中端真机、Windows x64 机器和 Apple Silicon Mac，具体型号待实际环境登记。

## 构建与检查

已实现 `tool/check.ps1`，失败即退出并遍历根应用与所有 package。下列命令适用于当前工程；真实媒体测试需显式运行 `tool/test-windows-media.ps1`。

```text
# 根应用
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test

# packages/bili_api 中
dart pub get
dart analyze
dart test

# packages/bili_player 和 packages/bili_danmaku 中分别执行
flutter pub get
flutter analyze
flutter test
```

只对已存在目录执行 format；各 package 的 `lib/test` 也必须格式检查。增加生成器时在对应包执行固定版本生成流程，生成后确认没有未提交差异；根命令不会自动替代所有子包测试。

当前 GitHub Actions 已配置下列检查与构建，详见 [CI/CD 与 MSIX](validation/ci-cd.md)。原生播放、模拟器／真机与正式安装升级仍属于后续验收，不自动包含在常规 CI。

| CI 环境 | 当前配置的任务 |
| --- | --- |
| Ubuntu 分析 runner | 复用 `tool/check.ps1 -EnforceLockfile`，根与三个包的 format/analyze/unit/widget tests |
| Windows runner | Visual Studio C++ 工具链、Windows x64 release 构建、MakeAppx MSIX 打包与签名 |
| Ubuntu Android runner | JDK 17、锁定 SDK/工程选择的 Android SDK/NDK、Android arm64 release APK |
| macOS runner | Xcode/所需原生依赖、macOS arm64 release `.app` 构建与 ZIP |

Android release 测试产物和正式签名包区分；Windows 主机上的构建成功不能证明 macOS 可用。工具链缺失时报告缺失项和影响，不能将命令未运行写为通过。

## 主要风险与决策出口

| 风险 | 应对 | 决策阶段 |
| --- | --- | --- |
| API、风控、Cookie 机制变化 | 端点登记、fixture、错误分类、可关闭能力；停止盲目重试 | M0 及每次协议变更 |
| 分轨/headers/硬解兼容性 | 同一 PlayerEngine 契约比较 media_kit 和 fvp，记录实测 | M0，阻塞播放选型定稿 |
| 密集弹幕卡顿 | 限流、轨道调度、文本缓存、isolate；CPU 热点有证据再用 Rust | M0/M2 |
| 后台/PiP 平台差异 | 系统能力接口和开关；独立生命周期测试 | M4 |
| 原生依赖体积与发布 | 固定二进制来源和 ABI，逐平台验证 | M0/M5 |
| 参考项目许可信息不一致 | 先借鉴设计；复制代码、schema、图片前厘清来源和条件 | 采用前，详见参考文档 |

后续第一次实现任务应完成 M0 的最小纵向验证并回填结果，然后再扩展业务模块。

