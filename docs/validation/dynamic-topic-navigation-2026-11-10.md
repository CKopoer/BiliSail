# 动态话题外跳与双重顶部栏修复

日期：2026-11-10。用户反馈[应用内话题页](dynamic-topics-and-text-2026-11-09.md)加入后，点击动态中的话题仍会外跳，话题页还出现双重顶部栏。本次保留不构建、不操作真实设备的范围，定位点击链与工作区页面组合并补充回归。

同日按用户后续要求，话题页进一步改为页内独立导航，不再显示通用工作区工具栏，并加入收藏、举报和参与发布；该布局取代本文先前保留单个通用栏的方案，见[后续实现与验证](dynamic-publishing-and-topic-page-2026-11-10.md)。

## 原因与复现

旧 `dynamicTopicId` 只接受 `www/m.bilibili.com/v/topic/detail`。动态内容还可能提供移动端 `/topic-detail`，例如 `https://m.bilibili.com/topic-detail?topic_id=1028161&frommodule=H5`；该形式可以在本地 PiliPlus `4fce4bb5a35c425aee759ef9263352316a29e355` 的 `lib/utils/app_scheme.dart` 及其话题分发中核对。

协议解析保留 `module_dynamic.topic.id` 和 `jump_url`，但卡片点击直接转发 `jump_url`。因此，即使已经有合法 ID，移动端 URL 仍无法通过旧识别器，落入 `HomeContent._openDynamicLink` 的公共浏览器入口。富文本话题同样转发原链接；其 `rid` 还可能被优先读取的 `jump_url` 覆盖。

新增脱敏协议 fixture，经公开 `HomeClient` → 共享 mapper → 首页动态组件实际点击。修改前，独立话题标签和富文本话题都记录到了上述移动端 URL 的浏览器调用；并非话题页缺少路由。上一轮测试主要手工构造规范 `/v/topic/detail` 地址，未覆盖这条解析与点击链。

双重顶部栏来自 `router.dart` 的话题分支额外调用 `WorkspacePageHeader.wrap`。该包装实际创建搜索页专用的 `_searchHeader`，但话题页没有采用搜索页的外层排除规则，工作区 `_workspaceFrame` 已经提供通用顶部栏。两者叠加造成工具栏重复，甚至额外带入搜索分类。修复前新增的真实路由测试在 Android／Windows 窄屏都检测到两个 `workspace-common-tools`。

## 修复

- 新增共享 `dynamicTopicDestination`：独立标签优先使用已解析 ID，其次使用可识别话题 URL 的 ID；无法确定 ID 时按名称进入应用内搜索。没有身份或可用名称时不创建动作。追踪参数或未知跳转格式不再决定话题标签是否外跳。
- 富文本 `topic` 节点也使用同一目的地规则；API 层先采用合法的节点 `rid`，避免跳转元数据将已知身份替换成其他话题。没有 `rid` 时，可识别移动端链接仍可提取 ID，未知链接则按标签名称搜索。
- `dynamicTopicId` 补充官方 `/topic-detail`、`/topic` 及明确的 `bilibili://topic`、`topic-detail`、移动端 app URI 形式。仅将已识别身份转为内部页面，不启动外部 App；继续检查 host、路径、端口、userinfo 和十进制 ID，伪造子域不进入内部路由。
- 首页、空间、话题页和详情沿用既有回调与工作区，不再各自猜测标签的跳转形式。普通网页和商品入口保留原先的公共外链语义。
- 话题路由直接组合 `DynamicTopicScreen`，移除误套的搜索页顶部栏，由既有工作区负责通用顶部导航；保留话题名称、简介、刷新、排序及动态内容。

## 验证

新增 12 项协议到点击的 Widget 回归：列表／详情 × 独立标签／富文本 × 移动端别名／身份优先／未知 URL 名称回退。每项都断言浏览器没有被调用、内部目标正确；详情跳转还断言弹窗已关闭。

另增 12 项真实话题路由顶部栏回归：Android／Windows × 390／1280 宽度 × 单／双／多标签模式。每项断言通用工具栏、搜索框各一处，没有搜索页分类条，话题名称与简介仍正常显示；单／双标签的返回入口各一处，多标签沿用既有关闭标签的导航语义。

另补充官方别名、app URI、伪造域名／端口／凭据／非法 ID、名称中的 `#` 与身份优先的领域测试，以及富文本 `rid` 优先的 API 测试。定向运行 `dynamic_link_test.dart`、`dynamic_topic_navigation_regression_test.dart`、`dynamic_topic_screen_test.dart` 共 60 项通过，日志为 `build/dynamic-topic-combined-tests.log`。

最终运行 `.\tool\check.ps1 -SkipPub`，退出码 0，日志为 `build/dynamic-topic-combined-check.log`。格式、静态分析及打包边界检查通过；离线测试结果为：

| 范围 | 通过 | 跳过 |
| --- | ---: | ---: |
| 根应用 | 4950 | 13（Windows 符号链接权限不足） |
| bili_api | 806 | 0 |
| bili_player | 367 | 0 |
| bili_danmaku | 161 | 0 |
| bili_mux | 5 | 10（未配置 `BILI_MUX_LIBRARY` 的原生用例） |

文档相对链接与 `git diff --check` 通过。跳过的原生用例不代表原生集成通过。

只读核对上述 PiliPlus 提交的 `lib/utils/app_scheme.dart` 与动态话题分发职责，独立编写 URL 识别和目的地规则；未复制 GPLv3 应用源码或资源、修改相邻仓库或依赖。复现使用本地 fixture，没有读取用户账号的真实动态或记录凭据。未做真实接口在线可用性、设备点击或应用构建验收。
