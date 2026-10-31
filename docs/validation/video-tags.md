# 视频标签与标签搜索

日期：2026-10-06。按用户要求参考相邻 `biliuwp-lite`，独立实现 Dart／Flutter；参考仓库保持只读，没有复制新的上游代码或资源。

## 参考与交互

参考快照为 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0`：

- [VideoDetailPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/VideoDetailPage.xaml) 的标签标题、可换行列表和点击入口。
- [VideoDetailPage.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/Pages/VideoDetailPage.xaml.cs) 的 `btnTagItem_Click`，按 `TagName` 打开关键词搜索。
- [VideoDetailPageViewModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Video/VideoDetailPageViewModel.cs) 的独立标签读取，以及 [VideoAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/VideoAPI.cs) 的 `Tags` 端点。

本项目在视频播放页“简介”中、正文之后显示独立的“标签”区域；当前正文和标签默认收起，一同展开／收起。标签按钮按可用宽度换行，过长名称省略并通过悬停提示保留完整名称；点击按完整名称打开已有综合搜索，中文、空格、`&`、`/`、`+` 通过 `Uri.queryParameters` 编码一次。导航遵守用户现有单／多标签模式，返回仍保留原视频、当前分 P 与播放器实例。

标签有独立加载状态；失败只显示该区域的手动重试入口，不阻塞视频详情、播放或推荐。无标签时隐藏区域，取消不显示错误。`videoTagsProvider` 按视频身份隔离，销毁时取消读取，旧视频迟到响应不能更新新视频。2026-10-31 修复收起动画卸载标签组件后 Provider 自动释放、再次展开重复请求的问题：首次展开才读取，此后由播放页持续监听当前视频的标签，收起和宽窄布局变化保留进行中的请求、成功／空结果及失败状态，标签返回不触发整页重建。换视频重置按需读取，关闭页面释放监听；不增加全局常驻缓存。账号变化沿用 `ApiRequests` 的 session epoch 与工作区作用域销毁逻辑。禁用此 Provider 的默认自动重试，避免在传输层重试之外重复请求；独立重试按钮、播放页刷新快捷键与菜单刷新仍可重新读取当前视频的标签。

## 协议登记

| 项目 | 实际采用 |
| --- | --- |
| Host／方法／路径 | `api.bilibili.com`，GET `/x/tag/archive/tags` |
| Profile／鉴权／签名 | Web，Cookie 可选，游客可读；无 WBI／CSRF／App token |
| 参数 | `bvid`；参考实现使用 `aid`，本项目直接使用已有 BV 身份，避免再读一次详情 |
| 响应 | JSON `data[]`，只映射字符串 `tag_name`；保留首次出现顺序，去首尾空白并去重 |
| 容量／分页 | 无分页，最多处理前 100 个条目，返回不可变列表 |
| 重试／取消 | 沿用传输层最多两次额外网络／超时／指定 5xx 重试，25 秒 Repository 总 deadline；风控不重试，格式错误显式失败；UI 只手动重试 |

常规测试使用脱敏的本地标签 fixture；不访问账号或发送任何账户写操作。

## 验证

- 游客只读烟测：`dart run tool/video_tags_smoke.dart`（在 `packages/bili_api` 内）。样例 `BV1cGbK6hEQK` 成功返回 5 个非空标签。此结果只对应本次样例观测，不代表所有视频或登录态均已验收。
- API 测试覆盖路径／BV 参数、中文与特殊字符名称、去重／顺序／不可变列表、空列表、容量上限、损坏结构和取消后的迟到响应。
- Widget 测试覆盖简介与标签同时展开／收起、完整名称回调、独立失败与手动重试、切换视频的取消／迟到响应、空标签／取消静默和 240 逻辑像素宽度／2 倍字体的长标签布局。
- 2026-10-31 新增宽／窄布局下的重复展开请求计数、加载中收起不取消、收起期间返回后直接复用、空结果／失败不自动重试、换视频和关闭页面释放，以及普通／减少动画模式的生命周期回归。
- 本次修复以 `f20c5af` 为基线在隔离工作树验证：`video_screen_test.dart`／`video_tags_panel_test.dart` 中按 `tags` 筛选的 11 项及按 `description transition` 筛选的 4 项全部通过；原实现可复现再次展开的加载提示。修改文件的格式与静态分析通过。按用户要求仅做定向验证，未完成全量检查；未运行构建或实机验收。
- 路由测试覆盖单／多标签模式的真实播放页到搜索页导航、特殊字符往返、返回后的当前分 P 与播放器实例保留。
- 使用项目主题和内置 HarmonyOS Sans 生成并检查宽／窄 fixture 预览：`flutter test test/features/video/video_screen_test.dart --dart-define=VIDEO_TAGS_PREVIEW=true`，产物为 `build/video-tags-preview/`。

- 原始接入时 `tool/check.ps1 -SkipPub` 通过：根应用 736、`bili_api` 231、`bili_player` 16、`bili_danmaku` 23 项测试，共 1006 项；格式检查与静态分析通过。此总数包含当时工作区中已有的其他改动，日志保存在 `build/video-tags-check.log`。

没有原生播放器变更；本轮未验证登录态、Android／macOS 实机或已安装 Windows 客户端的实际点击流程，fixture 渲染和路由测试不代替这些平台验收。
