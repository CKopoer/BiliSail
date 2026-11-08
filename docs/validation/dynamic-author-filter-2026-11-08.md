# 动态页 UP 主筛选

日期：2026-11-08。

2026-11-09 按用户反馈，将宽屏侧栏 UP 主名称对齐官方客户端的 14 / 400、主要文字色与 17.5 行高，选中时保持相同文字样式；窄屏名称也统一采用主要文字色，保留原字号、字重、行高及既有交互。来源与验证见[文字排版对齐](official-client-typography-2026-11-09.md)。

## 交互与布局

- 动态／视频动态共用一个 UP 主选择器，提供“全部”入口、头像、名称、更新标记、分页和失败重试。保留服务端最近更新列表顺序，不按姓名或访问频率重排。
- 内容区宽度至少 880 逻辑像素时显示 224 像素侧栏；大字体提高分栏阈值。窄屏在顶部频道标签下显示横向头像列表，支持触摸、触控板和桌面滚轮。沿用主题色、圆角和 `NetworkAvatar` 首帧行为。
- 点击 UP 主重新请求该作者的动态，动态的全部／视频／图文和视频动态均保留作者条件。视频模式对作者接口的每一页筛选视频；图文仍按既有文字、图片、专栏类型筛选。空匹配页沿用动态控制器的有界扫描和手动重试。
- 选择器位于频道 pager 外，动态／视频动态切换保留同一个组件、选中作者及滚动位置。内容列表分别保留各标签位置；宽窄切换分别保存横向／纵向列表位置。
- 刷新内容时同时刷新作者目录，刷新期间保留目录和显式选择。若已选作者暂时不在目录第一页，提供固定选中项；返回“全部”即可解除条件。

## 生命周期与边界

`DynamicAuthorsController` 按工作区 Provider scope 和账号隔离，关闭页面取消请求；沿用组合根既有账号／session epoch 重建。目录最多保留 500 名作者，每个内容标签最多保留 200 条动态，重复游标／无新作者页面停止并展示重试入口。

作者内容沿用 `HomeController` 的分页、去重、取消和 generation 检查，通过独立 `dynamicAuthorFeedProvider` 区分作者。快速改选释放旧查询，迟到结果不能进入新作者列表；隐藏标签保持原列表，激活时才应用新选择，不为所有已访问标签同时请求。过滤列表切换作者时不保存无界的作者滚动快照；同一标签和作者的已挂载列表仍可跨频道切换保留位置。选择器隐藏时停用焦点和动画。

`HomeDynamicRepository` 是可选领域端口，由 `ApiHomeRepository` 实现。页面不访问 HTTP 或解析 JSON；不新增依赖、设置项、数据库字段或账号写操作。

## 协议与来源

以下均为 `api.bilibili.com` 的 Web Cookie profile、GET JSON，无 WBI／CSRF。沿用 `ApiRequests` 的 25 秒 deadline、session epoch 和 API 层有界读取重试；无 App token，也不持久化作者列表或带凭据 URL。

| 能力 | 路径 | 参数与分页 |
| --- | --- | --- |
| 最近更新 UP 主首屏 | `/x/polymer/web-dynamic/v1/portal` | `up_list_more=1`、`platform=web`；读取 `up_list.items/has_more/offset` |
| 更多 UP 主 | `/x/polymer/web-dynamic/v1/uplist` | `offset` 原样单次编码，`platform=web`；读取 `items/has_more/offset` |
| 作者动态 | `/x/polymer/web-dynamic/v1/feed/all` | `host_mid` 十进制字符串、`offset`、`page`、`features=itemOpusStyle`、`platform=web`；作者模式不同时发送 `type`，逐页按当前内容分类过滤 |

只读参考本地 PiliPlus 提交 `4fce4bb5a35c425aee759ef9263352316a29e355` 的 [HTTP 动态接口](../../../PiliPlus/lib/http/dynamics.dart)、[端点定义](../../../PiliPlus/lib/http/api.dart) 和 [UP 主响应模型](../../../PiliPlus/lib/models/dynamics/up.dart)。同时核对[官网动态脚本](https://s1.hdslb.com/bfs/static/2233-monorepo/dyn-home/static/js/index.611b9e16.js) 中的 `portal`、`uplist` 和 `feed/all` 作者请求。只采用端点、字段和分页语义，独立实现 Dart／Flutter；未复制 GPL 应用源码、资源或状态管理，未修改相邻仓库。

## 验证

新增离线测试覆盖作者映射／目录顺序、长 UID、畸形响应、单次游标编码、逐页图文／视频筛选、空匹配页、账号／epoch 隔离、快速切换取消、刷新迟到结果、目录容量与重复游标、宽窄屏／两倍字体、组件与滚动位置保留、隐藏标签不额外加载、关闭释放及工作区隔离。

- `tool/check.ps1 -SkipPub` 通过：根应用 4,762、`bili_api` 733、`bili_player` 360、`bili_danmaku` 161、`bili_mux` 5 项，共 6,021 项通过。根应用 13 项按既有条件跳过；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。格式、静态分析及打包边界脚本通过。
- 最后补充刷新失败重试／账号隔离回归后，作者控制器、作者组件、API 仓储与原有 `HomeController` 共 49 项定向测试通过；最终 `flutter analyze --no-pub` 无问题。API 新用例与原有 HomeClient 的 42 项定向测试通过。
- 375 像素浅色／深色、1280 像素浅色的合成数据组件截图已人工检查；320–1440 像素及两倍字体的布局和点击由 widget 测试覆盖。文档相对链接和 `git diff --check` 通过。

日志与截图保存在本机忽略目录 `build/validation/dynamic-author-filter/`，分别为 `check.log`、`focused.log`、`analyze.log`、`preview.log` 和 `preview-*.png`。

本任务按用户要求不构建应用、不安装设备。未完成真实账号在线目录／筛选验收以及 Android、Windows、macOS、iOS、Linux 实机交互；公开动态页 HTTP 访问返回 412，未将公开脚本可读取算作账号接口在线成功。本机无运行中的 Flutter 调试进程，未执行热重载。
