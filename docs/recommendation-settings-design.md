# 推荐流设置设计与实施

日期：2026-10-27。只读参考本机 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/pages/setting/models/recommend_settings.dart`、`lib/utils/recommend_filter.dart`、`lib/pages/rcmd/controller.dart`、`lib/http/video.dart`。仅参考选项职责、协议字段与交互，独立实现，不复制 GPLv3 应用源码或资源，不修改相邻仓库或依赖。

## 选项对应

| PiliPlus 选项 | BiliSail 实施 |
| --- | --- |
| buvid | 独立 App 设备标识由应用自动生成并持久化，保留已有值；2026-10-28 移除设置中的显示、手工编辑和随机生成入口 |
| 首页使用 app 端推荐 | 支持即时切换 Web/App；默认保留 Web，所有登录方式均可切换 App 来源，无 App 凭据时使用游客推荐，有效同账号凭据才用于账号推荐及反馈；设置仅显示当前推荐身份，详见[App 接入](app-recommendation-design.md) |
| 保留首页推荐刷新 | 支持；新内容在前，旧内容稳定去重后保留，旧内容最多 200 条；失败保留旧内容并提供显式重试 |
| 显示上次看到位置提示 | 支持；在新内容与保留内容之间显示提示；没有旧内容时不显示 |
| 点赞率 | 支持 0/1/2/3/4% 预设及自定义 0–100%，用于推荐、热门、排行、分区及启用过滤的相关视频；App 未提供明确点赞数时保持未知 |
| 标题关键词过滤 | 支持；以上范围均生效，每行一个普通文本关键词，忽略大小写 |
| 分区关键词过滤 | 支持 App 推荐、热门、排行、分区；Web 推荐/相关视频只有响应提供分区名称时生效，不额外请求详情 |
| 视频时长 | 支持 0/30/60/90/120 秒预设及自定义 0–604800 秒，作用于推荐与启用过滤的相关视频 |
| 播放量 | 支持 0/50/100/500/1000 预设及自定义 0–2147483647，作用于上述视频列表 |
| 已关注 UP 豁免推荐过滤 | 支持；Web 信任明确的 is_followed，App 额外识别精确“已关注/新关注”；不逐卡查询关注状态 |
| 过滤器也应用于详情页相关视频 | 支持；开关只影响相关视频，不扩大到搜索、动态、历史、收藏或下载 |

默认过滤阈值为 0、关键词为空、豁免/相关视频开关开启。刷新保留默认关闭，以保留本项目原有刷新行为；提示默认开启，随保留功能使用。有效旧偏好保持；恢复默认与缺失/非法配置回退一致。

首阶段兼容性探测：App feed 的游客 GET 返回 HTTP 200、业务码 0、10 张卡片，抽样只有 aid/player_args、无 bvid，统计为缩写字符串。后续接入以独立 profile、设备/授权仓储、aid 本地转换和服务端反馈原因解决这些适配点，不逐卡补查详情。游客成功不代表登录个性化与反馈已在线验证，当前结果见[App 接入记录](app-recommendation-design.md)。

## 代码结构

1. `lib/domain/recommendation_settings.dart` 定义不可变偏好与纯 Dart 编译过滤规则。单独嵌入 `AppSettings.recommendations`，避免把推荐选项散布到顶层。关键词最多 32 个、每个最多 64 字符，不执行任意用户正则。
2. 设置继续使用 `SettingsController` 的串行保存/失败回退和 `SqliteSettingsRepository` 的 `preferences.v1` 快照；增加嵌套字段，不改 SQLite 表或版本。新增独立 `RecommendationSettingsSection` 与“推荐流”分类，复用既有路由、滑动和页面保留。
3. API 包仅解析可选 `likeCount/categoryName/isFollowed`，不持有产品规则。主应用 Repository 映射为共享领域模型，不在 UI 解析协议。
4. `lib/shared/application/recommendation_filter_provider.dart` 按推荐偏好选择订阅并编译规则，其他设置变化不会重复编译或刷新列表。
5. Feed 应用层使用查询级原始/可见分块索引，普通分页只筛选新响应；默认无过滤直接复用原始快照。修改过滤设置时对已加载内容筛选一次，无网络请求，可恢复先前被过滤的内容。当前与保留频道、热门周刊缓存同步更新，原取消/generation/重复页预算保持。
6. 相关视频将远端读取与本地筛选分开 Provider，偏好变化只重新筛选已读结果；不重开播放器、不重新请求详情。

## 性能与生命周期约束

- 不在 build、滚动或 position 回调遍历全量内容；保留现有自然高度 Sliver、局部卡片反馈及 Widget 缓存生命周期，不扩大 cacheExtent。
- 默认关闭过滤时不额外复制列表；启用时可见索引仅增加条目引用，不复制视频对象。普通追加只处理新页；同 ID 更新导致移除时允许一次索引重建。
- 刷新最多从旧索引取 200 条，保留内容不随重复刷新额外累积。已有普通分页列表仍遵循项目既有分页生命周期，不声称总列表已有硬性内存上限。
- 自动分页仍受连续无新增页预算限制，全部被过滤也不得无限补页。页错误需要用户显式重试。刷新/频道切换/账号切换的迟到响应隔离继续有效。
- 未知点赞/播放量/时长/分区保持未知，不按 0 误杀；仅使用当前响应元数据，不补请求、不新增启动任务或后台计时器。

## 验证计划

纯规则测试覆盖阈值、缺失字段、作用范围、已关注豁免、关键词上限与文本匹配；SQLite 测试覆盖旧快照、非法配置、往返和恢复默认；控制器测试覆盖设置更新、隐藏频道、筛选空页预算、保留上限、失败恢复与迟到响应；Widget 测试覆盖分类导航、交互、保存失败及位置提示。复用推荐更新/虚拟化回归确认追加与反馈仍保持局部更新。最后执行 `tool/check.ps1 -SkipPub`，如实记录跳过项与同期改动阻塞。

本轮没有原生播放器变更；自动化工作量回归不能代替 Windows/Android/macOS 的 Profile/Release 帧耗时与真实手感验收，不能承诺所有设备性能绝对不变。

## 实施结果与数据处理探针

实现入口为[纯 Dart 偏好与规则](../lib/domain/recommendation_settings.dart)、[共享 Provider](../lib/shared/application/recommendation_filter_provider.dart)、[查询索引](../lib/features/feed/application/filtered_feed_index.dart)、[推荐控制器](../lib/features/feed/application/feed_controller.dart)、[独立设置组件](../lib/features/settings/presentation/recommendation_settings_section.dart)和[相关视频 Provider](../lib/features/video/application/video_extras_controller.dart)。首阶段设置快照增至 29，App 来源接入后增至 30，SQLite schema 保持 3。标题/分区关键词分别最多 32 条、每条最多 64 字符；不执行用户正则。保留提示按第一条仍可见的旧内容定位，调整过滤后同步更新。App/buvid 与安全授权结构见[后续接入设计](app-recommendation-design.md)。

[合成探针](../tool/benchmark_recommendation_filter.dart)使用纯 Dart AOT：每种模式预热一次，每组 600 次追加 20 条，前 100 次不计入样本。启用组包含 32 个标题关键词、32 个分区关键词及三项数值阈值，每条标题约 120 字符，关键词均未命中；模型构建在计时之外。基线直接调用本项目原 `FeedItemIndex.merge`，关闭/启用组分别调用新的查询包装层。以下为本机 Windows、Dart 3.13.5 的一次运行，单位微秒：

| 初始条目数 | 模式 | 中位数 | P95 | 最大值 |
| --- | --- | ---: | ---: | ---: |
| 1000 | 原索引 | 1 | 2 | 249 |
| 1000 | 关闭过滤 | 1 | 3 | 210 |
| 1000 | 两组各 32 词 + 阈值 | 95 | 100 | 629 |
| 10000 | 原索引 | 2 | 2 | 668 |
| 10000 | 关闭过滤 | 2 | 3 | 2111 |
| 10000 | 两组各 32 词 + 阈值 | 100 | 142 | 1521 |

两组最终分别保留 13000/22000 条。关闭过滤的中位数与原索引相同，启用组每页中位数约 0.1 ms；离群峰值包含分配/GC 等波动，不能据此保证最大延迟或设备帧预算。该探针只衡量新页的数据处理，不覆盖设置变化时对已加载内容重筛、真实 API/CDN、Flutter 布局/光栅、稳定滚动或 Android/macOS 性能。

```powershell
dart compile exe tool/benchmark_recommendation_filter.dart -o build/recommendation-filter-probe.exe
.\build\recommendation-filter-probe.exe
```

探针通过独立格式与静态分析。原始 JSON、可执行文件和编译日志位于忽略目录 `build/recommendation-filter-probe*`，不提交二进制。

## 首阶段验证（九项兼容设置）

- `tool/check.ps1 -SkipPub` 最终通过：根应用 3159、bili_api 479、bili_player 83、bili_danmaku 93、bili_mux 5，共 3819 项通过。13 项 Windows 符号链接用例和 10 项未配置 `BILI_MUX_LIBRARY` 的 mux 原生用例跳过，不算原生通过。日志为 `build/recommendation-settings-check-final.log`。
- 新增[纯规则测试](../test/domain/recommendation_settings_test.dart)、[查询与刷新测试](../test/features/feed/recommendation_settings_test.dart)、[设置/SQLite/自定义输入测试](../test/features/settings/recommendation_settings_test.dart)、[相关视频本地过滤测试](../test/features/video/recommendation_filter_test.dart)、[位置提示 Widget 测试](../test/features/feed/recommendation_marker_test.dart)和[可选协议字段测试](../packages/bili_api/test/recommendation_metadata_test.dart)。覆盖缺失/非法值、自定义阈值、文字匹配上限、作用范围、保存失败回退、数据恢复、全部过滤页预算、200 条保留上限、刷新失败/显式重试、迟到响应、过滤后提示定位与显式相关视频刷新。
- 原有分页虚拟化与反馈回归通过，包含追加后既有卡片零重建、同 ID 内容更新及相邻卡片保留。新增分类继续覆盖全部分类滑动和独立滚动位置；连续滑动断言按分类序号处理新增 tab。
- 本轮相关 5 份文档的相对链接和 `git diff --check` 通过；未改依赖/锁文件。保留开始时和同期修改，未提交或推送 Git。
- 没有本轮 Flutter 应用构建、真实设备滚动/帧率测试或登录 App 推荐验收。纯 Dart AOT 探针与自动化测试不代表三端性能实测通过。
