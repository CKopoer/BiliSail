# 动态投票查看与参与

日期：2026-11-11。基于最新 master `87ac2be4` 补齐投票查看；原实现已支持创建投票，但动态中的投票只有通用附加卡片和外链。

## 行为与边界

- 首页动态、UP 主空间、话题和动态详情复用同一交互组件。投票卡片、卡片按钮及正文投票节点在所属窗口内打开详情；转发中的投票提交原动态身份。
- 显示标题、说明、文字／图片选项、参与人数、截止时间及选择上限；已投票或已截止时显示票数及比例。比例按各选项票数总和计算，零票时为零，与参与人数分别展示。
- 可切换结果比例和匿名投票；单选替换上一项，多选达到上限时提示。游客可以查看，登录后才允许提交；选择选项不会触发写请求。
- 提交成功才更新结果，期间阻止重复点击和关闭。过期、已投票及结果不明时停用提交；结果不明后必须成功读取服务端详情才能解除锁定，失败的刷新不会解锁。
- 账号／session epoch 变化清理选项和匿名状态、取消请求，丢弃迟到响应；关闭弹窗取消读取并释放截止计时器。弹窗限宽、内容可滚动，保留短窗口和大字号下的关闭入口。

## 协议登记

使用 Web Cookie profile、JSON 响应，无 WBI、App token 或分页。读取沿用有界重试与 25 秒应用 deadline；写入只尝试一次。

| 能力 | Host / method / path | 参数和响应 |
| --- | --- | --- |
| dynamic_poll_detail | `api.bilibili.com` GET `/x/vote/vote_info` | `vote_id`；Cookie 可选；`data.vote_info` 与外层 `data.my_votes` 分开解析 |
| dynamic_poll_vote | `api.bilibili.com` POST `/x/vote/do_vote` | Cookie／query CSRF；JSON `vote_id/voter_uid/votes/status/op_bit/dynamic_id/csrf/csrf_token`；匿名 `status=1`、公开 `0`，`op_bit=0`；响应 `data.vote_info.my_votes` |

领域身份保持十进制字符串，JSON 数值字段从 Dart 整数编码，不经浮点数。选项使用服务端 `opt_idx`，不使用列表下标。校验目标投票身份、2–20 个唯一选项、选择上限、截止时间及本人选择；畸形或身份不匹配的成功写响应按结果不明处理。成功响应省略 `my_votes` 时采用本次已确认提交的选项，避免界面再次放开投票。

动态解析优先使用投票节点的 `rid`／附加模块的 `vote_id` 生成标准投票 URL，防止无关 `jump_url` 把投票带回动态页；卡片标题缺失时兼容 `desc`。应用只识别指定官方投票页和单个合法 `vote_id`，其他链接继续走已有导航。

## 参考来源与许可

只读查看 PiliPlus 提交 [`cab0114a21ce7fad5b90b9a4d788d35d313d25f9`](https://github.com/bggRGjQaUbCoE/PiliPlus/tree/cab0114a21ce7fad5b90b9a4d788d35d313d25f9) 的 `lib/pages/dynamics/widgets/{additional_panel,rich_node_panel,vote}.dart`、`lib/models/dynamics/{result,vote_model}.dart` 和 `lib/http/{api,dynamics}.dart`，参考入口、详情、选项、两种本人选择位置及请求参数。

已核对实际 overrides／锁文件：核心及库插件解析 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频包解析 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`。仅参考协议事实与交互职责，独立编写 Dart／Flutter；未复制 GPLv3 应用源码或资源，未修改参考仓库、媒体 fork、Pub 缓存或依赖锁文件。

## 验证

新增协议测试覆盖分离的本人选择、文字／图片选项、长整数身份、CSRF、匿名字段、单次写入、非法数据／游客阻止及迟到响应。控制器与界面测试覆盖单选替换／多选限制、重复点击、结果不明锁定、账号切换、取消、卡片／正文／转发入口、已投票／过期、错误重试和 320×440 双倍字号。

验证在 Linux 云环境、Flutter 3.47.6／Dart 3.13.5 下进行。根应用与四个包通过锁文件强制解析；`flutter analyze --no-pub` 和 `bili_api` 的 `dart analyze` 均无问题，根／包及 Linux 适配器共 1125 个文件格式检查通过。`check.ps1 -Stage PackageTests -SkipPub` 通过：`bili_api` 848、`bili_player` 367、`bili_danmaku` 161、`bili_mux` 5 项；mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不算原生通过。

`check.ps1 -Stage RootTests -SkipPub` 退出码 0：主应用 5079 项通过、6 项按既有平台／工具条件跳过，包含新增投票控制器和弹窗回归。补充的截止瞬间用例、完整投票弹窗及真实主题截图夹具共 9 项定向测试通过；已人工查看 390 和 1280 宽度的截图，标题、票数、比例、选中状态及关闭／刷新图标正常。截图和临时夹具保存在忽略的 `build/dynamic-poll-*.png`、`build/dynamic_poll_visual_test.dart`。全量日志分别位于当前云环境 `/tmp/bilisail-root-check.log`、`/tmp/bilisail-package-check.log`，补充界面日志为 `/tmp/bilisail-final-poll-ui-tests.log`。

完整 `check.ps1 -EnforceLockfile` 在未改动的 `test-macos-release-validation.ps1:320` 失败：Linux 下独立父进程未能终止超时 worker 及其子进程。已继续分项运行后续检查，iOS 打包、macOS／iOS Python、SQLite、Android／Windows FVP、Windows 媒体、纹理交接和 Apple 资产检查通过；未为全量脚本通过修改无关平台代码。

未使用真实账号读取或提交投票，未构建安装包或进行 Android／Windows／Apple 实机验收；协议参考和模拟写入通过不代表在线账号写入已验收。
