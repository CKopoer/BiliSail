# 桌面端推荐来源

日期：2026-11-14。

## 来源与采用范围

参考 PiliPlus [PR #3463](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3463) 最终提交 `a0a6c5adcab5400a94e67e07b3fb3474a2510915`（合并提交 `e3aff4435e0df6d703b359b6999c6aa41a4fd678`）的公开协议参数和来源切换行为。只独立实现协议和交互，不复制 GPLv3 应用源码或资源，不修改相邻仓库、依赖或锁文件。

PR 早期评论中的 `fresh_type=8`、`web_location=1430650` 和 `fresh_idx_1h` 已被最终版本撤回，本次不采用。PR 作者将最终参数说明为官方 Windows Electron 客户端请求；本任务未重新提取官方客户端代码，不能把该说明当成本项目独立取证的结论。

## 行为与协议

- “设置 → 推荐流 → 推荐来源”增加“桌面端 / PC”，所有平台都可以选择。该名称表示推荐协议来源，不是仅 Windows 可用的功能。缺失／非法设置与恢复默认仍为 Web，原有 Web／App 选择保持。
- 桌面端使用 `api.bilibili.com` GET `/x/web-interface/wbi/index/top/feed/rcmd`，复用 Web Cookie、WBI 签名、共享设备上下文、风控、取消、session epoch 和有界读取。无需 App access token。
- 固定参数：`plat=1`、`feed_version=V1`、`ps=30`、`x_num=3`、`y_num=4`、`pc_wx_install=0`、`pc_wx_gm_install=0`；不传网页专用的 `homepage_ver`、`fresh_idx_1h`、`web_location`、`brush`。
- `fresh_idx` 与 Web 分开计数，同账号 epoch 首次从 0 开始。首次请求 `fresh_type=0`，后续第一页刷新为 3，翻页为 4；账号 epoch 改变时重置。PR 代码实际仅按索引发送 0／4，本项目依据其最终说明将刷新操作明确发送为 3。
- 失败页显式重试复用该页采样序号；新刷新、成功空批次与过滤后空批次继续消费序号。弱引用查询作用域不永久保留关闭页面；旧响应不能清除新请求的重试状态。
- 设置保存成功立即切换来源，清空原来源推荐、分页、反馈和保留内容；隐藏推荐只失效缓存，返回后才加载。沿用既有过滤、稳定去重、双空页预算、推荐理由、关注标记、视频导航与 Web 反馈协议。请求 30 张卡片不保证显示 30 条视频，广告和非视频仍被过滤。
- 来源继续按字符串名保存于 `AppSettings.recommendations`／`preferences.v1`，不增加数据库表或快照结构版本。保存失败保持原偏好；推荐流恢复默认仍使用既有控制器。

## 实现与验证入口

协议在 [BiliApiClient](../../packages/bili_api/lib/src/api_client.dart)，通过 [FeedRepository 能力接口](../../lib/features/feed/domain/feed_repository.dart)、[API 仓储](../../lib/features/feed/data/api_feed_repository.dart) 和 [FeedController](../../lib/features/feed/application/feed_controller.dart) 接入。[设置组件](../../lib/features/settings/presentation/recommendation_settings_section.dart)复用原有保存流程。

行为回归覆盖：完整签名参数与三种操作、非视频过滤及空页、Web／桌面端独立刷新和失败重试、取消与账号 epoch、隐藏频道、来源切换迟到响应、SQLite 往返、旧值／非法值与保存失败回退。

## 本轮验证

- 定向回归通过：首次根应用四份测试文件共 36 项、API 元数据／桌面端协议 4 项；补充 Web／桌面端交错失败重试后，完整采样序号测试文件 23 项通过。日志为 `build/desktop-recommendation-targeted.log` 和 `build/desktop-recommendation-sampling-test.log`。
- 显式 `-Online` 游客只读烟测：首次、刷新和翻页各返回 30 条视频，BV 身份格式均有效，`hasMore=true`。新建 API client，不读取已有账号、安全存储或 App 凭据；日志仅输出数量和布尔值，不输出视频内容、URL、query 或凭据。探针与日志在忽略目录 `build/validation/desktop-recommendation-2026-11-14/`。这只能证明当次接口可达及解析通过，不能证明真实账号个性化或与官方客户端推荐效果相同。
- 四份相关文档的相对链接与 `git diff --check` 通过。未变更依赖、锁文件、SQLite 表或已有设置默认值。
- 未构建或安装应用，未做真实账号推荐／反馈、Windows／Android／macOS 界面或性能验收。DTD 探测无运行中的调试应用，热重载调用未连接，未完成运行中验证。

- 主工作区运行 `tool/check.ps1 -SkipPub`：打包边界、格式、静态分析与根应用 5502 项测试通过；随后 API 包被同期修改的 `message_client.dart` 中模式匹配语法错误阻塞，74 个测试文件无法编译。保留消息、评论、投屏等同期修改，没有为本任务修改或回退它们。日志为 `build/desktop-recommendation-check-2026-11-14.log`。
- 在基线 `3cbdd098` 的独立检出中应用本次 11 份受影响代码／测试文件的当时差异，运行 `tool/check.ps1 -EnforceLockfile` 成功（退出码 0）：五份锁文件可复现解析、打包边界、格式、静态分析与全部离线测试通过。根应用 5502、`bili_api` 937、`bili_player` 312、`bili_danmaku` 161、`bili_mux` 5，共 6917 项通过。根应用 13 项 Windows 符号链接用例因权限跳过；播放器 3 项未配置 `BILI_TEST_NATIVE_MPV`／`BILI_TEST_MEDIA_DIR` 的原生用例，以及 mux 10 项未配置 `BILI_MUX_LIBRARY` 的原生用例跳过，不计为原生验证。完整日志为 `build/validation/desktop-recommendation-2026-11-14/isolated-check.log`。
- 最终核对发现，提取差异时 `api_client.dart` 同时已有另一任务新增的 `getVideoCommentRoot`，因此该独立快照也包含此方法；没有将它算作推荐功能改动，也没有移除主工作区中的该方法。其余消息／评论界面等同期修改未进入隔离快照。上述 11 份文件与隔离检出文本一致；完整检查验证这一明确快照，不代表不断变化的主工作区中其他任务已通过验收。
