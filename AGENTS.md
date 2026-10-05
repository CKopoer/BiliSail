# BiliSail（哔帆）开发约定

## 项目状态与入口

- 目标：Flutter Bilibili 第三方客户端，首批 Android arm64、Windows x64、macOS arm64。
- 当前已有 Flutter 0.1.0 预览工程、三个独立包、根应用/包测试和 Windows 调试入口。已实现范围与平台实测状态见 `README.md` 和 `docs/validation/m0-results.md`；M0 三端验收尚未全部完成。
- 开始前阅读 [文档索引](docs/README.md)、[整体架构](docs/architecture.md) 和与任务有关的专项文档。
- 实施顺序见 [实施与验收](docs/implementation-plan.md)，从 M0 技术验证开始。目录树和命令是目标设计，不能把未创建的结构写为现状。
- 重要选择和改变记录在 [架构决策](docs/decisions.md)。文档默认中文，类型、变量和文件名使用清晰的英文。

## 参考仓库

- 相邻 `../biliuwp-lite` 提供功能和交互/模块划分参考；`../bili-kernel` 提供 C#/.NET API 实现参考，后者不是 Rust 项目。
- 定位源码、提交与采用限制见 [参考文档](docs/references.md)。除用户明确要求外，不修改相邻仓库，不将它们作为需要发布的运行时依赖。
- 借鉴职责、协议和模型，避免机械翻译 UWP 控件、静态全局服务或整仓导入。引用代码/schema/资源前记录来源与明确的许可范围。
- 参考 API 不等于在线可用；未做在线验证必须注明。不要把对话中的性能概括当作测量结果。

## 架构边界

1. 根应用按 `features/<feature>/{domain,data,application,presentation}` 组织。`app` 为唯一组合根，`core` 为通用基础能力，`shared/ui` 为通用组件。
2. `domain` 保持纯 Dart，不引用 Flutter、Riverpod、Dio、SQLite 或平台插件。Repository 接口属于领域层，实现属于 data。
3. 页面只消费应用控制器与领域状态；不直接发网络请求、访问数据库、解析 JSON/Protobuf 或调用 media_kit。
4. 控制器通过构造器/Provider 注入 Repository 和端口。Riverpod 是默认状态与 DI 方案，go_router 管导航；不另起全局 service locator。
5. `packages/bili_api` 是纯 Dart 协议包，不存 UI/数据库状态；`bili_player` 只处理通用媒体；`bili_danmaku` 不做网络请求。
6. 独立包只开放公共入口，不导入其他包的 `src/`。包不能反向依赖主应用；Feature 不导入另一 Feature 的 data/presentation，不产生环形依赖。
7. 简单功能直接调用 Repository；只对跨仓储或复杂规则增加 UseCase。按实际需求建文件，不预建空架构或给每个方法套抽象层。
8. Rust 不是 MVP 必需项。有 profile 数据或明确复用需求时按决策 D2 评估 FRB；先隔离纯计算，保持单一状态所有者。

## Dart 与状态约定

- 文件/目录 `snake_case`，类型 `UpperCamelCase`，成员 `lowerCamelCase`。启用 sound null safety，边界检查空值，不用 `dynamic` 或强制 `!` 掩盖协议问题。
- 对外模型不可变；JSON/Protobuf DTO 不泄漏到 UI。简单类型直接编写，生成工具按需要引入，生成文件不手改。
- 名称表达职责，例如 `VideoRepository`、`SearchController`、`VideoScreen`、`MediaKitEngine`。注释解释原因、单位和约束。
- 外部 ID 使用明确值类型，传输/落盘避免浮点数转换；时间内部用 Duration 或标明毫秒的字段。
- 异步操作必须有取消、超时和错误分类。不要用宽泛 catch 返回空成功；取消不弹通用错误提示。
- 账号请求携带 account scope/session epoch，搜索携带 query generation，播放携带 source generation；旧响应不能改变新状态。
- 明确释放 StreamSubscription、Ticker、Timer、isolate、WebSocket、播放器和文件句柄。不要用页面销毁意外终止进程级任务。
- 高频 position/弹幕更新只影响局部绘制，禁止经全局 Provider 逐帧重建页面。

## API 与凭据

- 按 [API 方案](docs/api-design.md) 接入端点：登记 profile、host/method、鉴权、签名、响应格式、分页与重试规则。
- MVP 优先 Web Cookie/WBI/CSRF。HTTP Protobuf 不等于 gRPC；App/TV token 不可由 Web 会话凭空假定存在。
- 参数只编码一次；WBI/key 刷新与账号刷新各自单飞。可重试读请求设置总次数和 deadline，不允许多层无限重试。
- 点赞、投币、收藏、发送等操作仅由明确用户动作触发；结果不明的写请求不得自动重放。
- 凭据用 CredentialStore/系统安全存储；禁止写入日志、普通 JSON、SQLite、fixture、设置导出或源码。安全存储失败不得退回明文。
- Cookie 遵守域/path/secure/expiry，重定向不得泄漏凭据；保留系统 TLS 验证。禁止采用参考源码的无条件证书接受回调。
- 数据缓存按账号隔离；登出取消请求、上报、WS 与依赖账号的任务，清理凭据和私有缓存。离线媒体与普通缓存区分。
- 默认不添加自动遥测。诊断须过滤 token、Cookie、二维码 key、URL query 和 native 播放器日志中的敏感数据。

## 播放、弹幕与平台

- 遵守 [播放设计](docs/playback-and-danmaku.md)。MVP 只有一个活动 PlaybackSession，主应用仅使用 PlayerEngine/VideoSurface 契约。
- 点播必须验证 DASH 音视频分轨；不能把视频 URL 单独可播视作完成。原生播放器请求不经过 Dio，需要独立设置并验证 headers/Range/重定向。
- seek、换清晰度、换 P、URL 刷新都要隔离旧事件并保留用户播放意图；全屏/布局改变不得产生第二路音频。
- 点播弹幕以确认的播放位置为主时钟，暂停/缓冲冻结、seek 重建、倍速校正；直播弹幕与点播时钟语义分开。
- 弹幕、聊天、解压任务、文件缓存均需容量上限和降级规则。复杂解码在 isolate，Flutter 绘制留 UI isolate。
- 平台差异放在小型 PlatformServices/适配器，通过 capability 显示入口；不在业务代码到处判断 OS。
- 后台播放、PiP、媒体键、硬解和后台下载均需逐平台验证，不能从插件支持列表推导成项目已支持。

## 存储、依赖与生成

- SQLite migration 必须增版本并有迁移验证；禁止靠清空用户数据完成升级。
- 下载实现校验 206/Content-Range、文件完整性和 URL 刷新后的资源身份；任务完成与文件落盘须可从中断恢复。
- 初始化时固定实际验证的 Flutter SDK、直接依赖和原生二进制来源；提交根应用 pubspec.lock，不依赖“始终取最新”构建。
- 新依赖先确认目标平台、维护接口、二进制依赖和许可；选择能满足具体需求的最小组合。
- 生成器/schema 记录版本、命令和来源；提交项目需要的生成物，改源后重生成，不手修输出。

## 检查与交付

当前已有可执行工程：改动后运行 `tool/check.ps1` 覆盖根应用与三个包。纯文档改动只检查相对链接、源码路径、术语/阶段一致性和差异。原生播放改动另外运行受影响平台的原生测试和构建。

初始化后按实际存在的目录运行：

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

# packages/bili_player、packages/bili_danmaku 中分别执行
flutter pub get
flutter analyze
flutter test
```

- 各 package 同样格式检查，根命令不替代子包检查。尚未存在 integration_test 等目录时只传实际目录。
- 只读文档或低风险样式变更不强制新增测试；协议、会话竞态、播放状态机、存储迁移需要行为测试。
- 优先 fake clock/transport/repository/player 和脱敏 fixture。正常 CI 不使用真实账号，不自动执行投币/发送等账户写操作。
- 原生播放改动至少在受影响平台构建并实机验证；三端验证记录与未测项均写明。性能用 profile/release，不能用 debug 帧率作结论。
- 构建按主机执行 Windows、Android、macOS 目标；工具链或设备不可用时准确报告，不能声称通过。
- 完成后说明改动、验证结果、未验证部分；重要边界变化同步 docs。保持用户已有修改，不顺带重排或迁移无关代码。

