# 评论视频链接识别与样式

日期：2026-11-17。用户要求参考 PiliPlus 扩大评论中的视频链接识别范围，支持特殊展示；完成离线检查后提交，不构建，由用户后续构建和实机测试。

## 行为与边界

[评论解析](../../lib/features/comments/domain/comment_text.dart)在原有 HTTP(S) 外链、表情、@用户与时间戳之外，支持：

- 裸 `BV117BkBsEWw`、`av170001`，BV／AV 前缀不区分大小写，BV 正文保持原有大小写。
- `bilibili.com/video/…`、`www.bilibili.com/video/…`、`m.bilibili.com/video/….html` 和带 `//` 的无协议地址，补为 HTTPS。
- `bilibili://video/<aid|av号|BV号>`，转换为同一视频的 HTTPS 目标，保留 query。
- 原有完整 Web、移动端及 `b23.tv/<BV|av号>` 地址，并兼容大小写前缀。

HTTP(S) 外链仍保留自己的整个路径和 query；其中的 BV、@用户或时间戳不会被拆成其他链接。未知 scheme、带凭据地址、伪装域名、过长／不完整 BV 和非法 AV 不会被误识别为视频；普通外链保持原来的打开行为。

[视频身份解析](../../lib/features/comments/domain/comment_video_link.dart)继续供原有链接 resolver 使用，BV 直接导航，AV 经既有只读接口解析。`b23.tv` 随机短码在点击时使用原有无凭据、有取消／超时及跳转上限的链路解析；显示评论不会额外请求短链或视频详情。未知短码可能指向其他内容，解析前仍作为普通链接，不冒充已确认的视频。

`bili_api` 保留 Web 评论 `content.jump_url` 各 token 对应的 `title`，最多 100 项、key 最多 2048 字符、标题最多 300 字符，忽略格式异常的可选元数据。Repository 映射为领域 `linkTitles`；主评论、预览、楼中楼、点赞复制和回复列表替换均保留标题。

[共享评论正文](../../lib/shared/ui/comment_rich_content.dart)为已确认的视频引用显示蓝色播放图标和半粗文字；有对应服务端标题时展示标题，缺失时保留原始 ID／链接。短链若带标题则显示链接图标和标题。图标及文字点击沿用共享评论导航，标题不会改变目标。重复引用均保留，正文仍可选择；可见组件与离线列表测量保持相同排版，标题／回调变化时刷新并释放旧手势资源。

这些行为覆盖所有采用共享评论组件的视频、PGC、动态及评论详情入口；没有新增网络端点、依赖、数据库迁移或播放器逻辑。

## 参考来源与许可

只读核对本机 PiliPlus 提交 `217fb54f51f6764176319bbdedab2a7522d75401`：

- `lib/pages/video/reply/widgets/reply_item_grpc.dart`：优先匹配服务端 `content.urls` token，使用 title 和前缀图标；识别 AV／BV 并分发点击。
- `lib/models_new/reply/content.dart`：Web 评论的 `jump_url` 字段。
- `lib/utils/{url_utils,app_scheme}.dart`、`lib/common/constants.dart`：HTTP 外链与视频 scheme 分发职责。

其应用许可证为 GPLv3；本次只借鉴协议事实和交互职责，独立编写 Dart／Flutter，没有复制应用源码、图标、资源或 schema，没有修改相邻仓库和 Pub 缓存。已核对实际 pubspec overrides 与锁文件：其核心／库插件来自 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频插件另有覆盖；本次不采用或修改媒体依赖。

## 验证

相关单元和 Widget 回归覆盖完整／无协议／App 视频地址、ID 边界、伪装 host、未知 scheme、表情和 @ 优先级、重复链接、query 时间戳隔离、元数据容量／异常、标题复制／更新、真实文字／图标点击、窄屏两倍文字、紧凑回复、离线测量及共享面板内部导航。

根检查脚本按 `Lint`、`RootTests`、`PackageTests` 完成：打包边界、全仓格式与静态分析通过；固定最终代码后，根应用 5783、`bili_api` 1035、`bili_player` 258、`bili_danmaku` 161、`bili_mux` 5 项离线测试通过，共 7242 项。根应用 13 项 Windows 符号链接用例因权限限制跳过，player 的 3 项原生用例因缺少对应环境配置跳过，mux 的 10 项原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，均不记作原生通过。

最终评论定向回归 145 项通过，覆盖解析、仓储、共享正文、面板与现有短链取消／账号边界；协议包另有 7 项新标题元数据测试，已包含在上述包检查中。最终再次运行静态分析、相关文件格式检查、文档相对路径检查和 `git diff --check`，均通过。大字体图标回归确认文本缩放两倍时 16 像素行内图标只缩放一次至 32 像素。

主要日志为本机忽略目录下的 `build/comment-video-links-check.log`（打包边界／格式／分析）、`build/comment-video-links-final-root-tests.log`、`build/comment-video-links-package-tests.log`、`build/comment-video-links-final-targeted.log` 和 `build/comment-video-links-final-analyze.log`。首次全量测试曾与定向进程重叠，导致 SQLite DLL 占用；后续均等待前一测试进程结束再运行根应用测试，上述最终结果无此阻塞。

本次未构建安装包、未执行在线 API 请求或真实账号写入、未进行三端实机验收；当前未发现可连接的 Flutter／DTD 调试进程，无法热重载现有应用。用户后续自行构建并确认真实评论标题、短链目标及设备交互。
