# 播放页简介侧栏

日期：2026-10-05。视觉参考为本次用户提供的官方桌面客户端截图；自行实现 Flutter 布局，未复制截图资源或参考客户端代码。

## 2026-10-08 滚动性能修复

简介与推荐共用一个 `CustomScrollView`，简介／标签／合集保留在顶部 box sliver，相关推荐使用 `SliverList.builder` 按视口和缓存区创建自然高度的横向卡片。卡片按视频身份保留状态，列表委托在数据和导航回调不变时复用；行级绘制边界隔离单卡悬停和预览进度。相关推荐读取仍与详情并行启动，但读取状态只更新推荐区域，不重建播放器和简介。

共用 `VideoCardCover` 监听所有祖先滚动位置的活动状态。任意祖先开始滚动时取消等待和在途预览，移除临时播放层；全部停稳后，仍被悬停的卡片重新等待 200 毫秒再启动。此规则同样用于首页、搜索、历史和个人主页等复用封面的列表。隐藏／账号变化／移开／销毁沿用原有取消与串行释放，屏幕外行淘汰时释放自己的预览，不改变主播放会话。

离线结构探针在 1100×800、DPR 1、40 条推荐中确认：

| 工作量 | 修复前 | 修复后 |
| --- | ---: | ---: |
| 初始挂载卡片 | 40 | 10 |
| 稳定小幅滚动帧的图片可见性检查 | 40 | 10 |
| 同一滚动帧的图片节点绘制遍历 | 40 | 0（复用行绘制层） |
| 简介展开时重建的推荐卡片 | 40 | 0 |
| 单卡悬停动画每帧的图片节点绘制遍历 | 40 | 1 |
| 静止鼠标、约 3 秒滚轮输入 800 像素期间的预览启动请求 | 9 | 0 |

480×800 的窄视口初始挂载 7 张卡片，滚动检查为 7 次；100 条宽屏样本仍只挂载 10 张。数字来自 debug widget 探针，表示工作范围，不表示帧时长或 GPU 最终绘制的像素数。模拟仓储和 24×24 内存 PNG 不访问网络、磁盘或账号；预览调用使用 fake，没有原生媒体开销。

[播放页回归](../../test/features/video/video_screen_test.dart) 与[共用封面回归](../../test/shared/ui/video_card_hover_test.dart) 覆盖宽／窄懒创建、滚动位置与主播放器保留、平滑滚轮期间不启动新预览、已播放／在途预览淘汰后只释放一次、外层滚动取消与迟到结果隔离，以及停稳后的静止悬停恢复。29 项定向回归和 5 项结构探针通过，日志 `build/video-sidebar-targeted.log`；探针及前后计数在本地 `artifacts/video-sidebar-performance/`，该目录不纳入发布源码。

完整检查在已提交基线 `c3a180f71f25f9e2b923b275525ab11d1dea07d4` 加本次六个文件的隔离副本执行：`tool/check.ps1 -SkipPub` 通过，根应用 1316、API 包 319、播放器包 32、弹幕包 65，共 1732 项测试；四处格式检查和静态分析通过。依赖按锁文件解析，日志 `build/video-sidebar-isolated-check.log`。主工作区同期输入／动态列表修改曾阻断分析和根测试，因此这项完整检查只验收本次修复及上述已提交基线。

本轮没有修改原生播放器或协议，没有构建应用；修复后的 Windows／Android／macOS 实机滚动、真实主视频与预览并发场景，以及 Profile 帧耗时由后续构建验收确认。前一轮离线 Windows Profile 的 40 卡 UI P95 约 1.49～1.61 ms，没有复现明显掉帧，不据此推断真实播放场景的改善幅度。

## 前序实现记录

2026-10-07：从稍后再看打开的视频在侧栏顶部显示可收起的播放列表，收起后恢复本文中的简介/评论内容。队列与播放验收见 [稍后再看队列播放](watch-later-queue.md)。

2026-10-07：播放页相关推荐的横向卡片接入共用 [VideoCardCover](../../lib/shared/ui/video_card_cover.dart)。悬停整张卡片时封面轻微放大，停留 200 毫秒后静音播放预览，并在右上角显示稍后再看按钮；键盘聚焦可访问按钮，点击按钮不打开视频。保留原有封面时长、UP 和播放／弹幕统计。移开、切到评论、收起信息面板、隐藏工作区、后台或销毁时沿用共用组件的取消／释放规则；临时预览不改变当前视频的播放会话。协议与首帧策略见 [悬停加载延迟](video-preview-loading.md)。

本次新增 [播放页组件测试](../../test/features/video/video_screen_test.dart) 覆盖标题／封面悬停、cid 直传、静音播放与进度、移开释放、按钮添加不导航、重复点击不重发、键盘添加、评论切换／侧栏隐藏取消和主播放器保留；[通用卡回归](../../test/shared/ui/video_card_hover_test.dart) 同时验证已添加按钮不会触发外层导航。`tool/check.ps1 -SkipPub` 全部通过：根应用 996、API 285、播放器 22、弹幕 32 项，共 1335 项，四部分格式与静态分析通过；日志 `build/related-video-card-check.log`。未做真实账号添加、原生悬停交互或 Android/macOS 实机验证。

`flutter build windows --release --no-pub` 通过，输出 `build/windows/x64/runner/Release/bilisail.exe`；日志 `build/related-video-card-windows-release.log`。本轮未修改原生播放后端。

## 本轮调整

- 简介顶部显示 UP 头像、名称、粉丝数和累计获赞；统计来自该 UP 的用户卡片，不使用当前视频的点赞数。缺失计数显示 `—`，读取失败可刷新。
- 关注／已关注按钮接入 Web 会话，游客点击打开现有登录入口，本人不显示关注按钮。只有显式点击才发送关注或取消关注；进行中禁止重复点击，结果不确定时先刷新关系再操作。按账号、session epoch 和请求代次隔离旧结果，离开时取消请求。
- 标题旁展开简介正文；简介、合集、推荐之间使用淡横线。推荐始终显示列表，不再提供折叠标题。
- `VideoCollectionPanel` 统一承载标题、当前序号／总数、合集播放量、选集与内嵌分 P。当前视频已在合集内时，不再重复单列其分 P；仍支持无合集的多 P 视频。合集列表高度最多 224 逻辑像素，独立滚动，初始定位当前视频；保留选中高亮、条目时长、分 P 懒加载和 CID 导航。条目高度随文字缩放增长。
- 推荐封面显示时长，右侧标题靠上，UP、播放数和弹幕数作为一组靠底排列；单行标题保留中间留白，字号增大或统计换行时卡片自然增高。宽窄切换、信息面板收起和子标签切换继续复用同一播放器。

## 端点与来源

| 能力 | Host / 方法 / Path | Profile、鉴权、响应、重试 |
| --- | --- | --- |
| UP 统计与关注态 | `api.bilibili.com` GET `/x/web-interface/card` | Web Cookie 可选，无 WBI/CSRF；`mid` 原样十进制字符串；JSON `card.mid`、`follower`、`like_num`、`following`，无分页；沿用总 deadline 25 秒与最多 3 次的有界只读请求 |
| 关注／取消关注 | `api.bilibili.com` POST `/x/relation/modify` | Web Cookie 必需，系统安全存储会话与 body CSRF；`fid`、`act=1/2`、`re_src=14`；JSON，无分页，单次 POST、不自动重放 |
| 合集补充统计 | 既有 GET `/x/web-interface/view` | `ugc_season.stat.view`、`episodes[].arc.duration`；缺省统计和时长保持未知，沿用原有合集容量上限与取消策略 |

协议定位参考相邻 MIT 仓库的 [UserCardDetailResponse.cs](../../../bili-kernel/src/Services/Services.User/Core/Models/UserCardDetailResponse.cs)、[MyClient.cs](../../../bili-kernel/src/Services/Services.User/Core/MyClient.cs) 与 `BiliApis.cs`，以及公开的 [用户资料字段](https://github.com/pskdje/bilibili-API-collect/blob/main/docs/user/info.md)、[关系参数](https://github.com/realysy/bili-apis/blob/master/docs/user/relation.md)。仅使用协议事实，Dart 实现和脱敏测试数据独立编写；未新增依赖或引入参考代码／资源。

## 验证

- 定向回归 12 项通过：UP 数据、关注／取消、游客登录、大字号、重复点击、未知结果恢复、登出／同账号新会话隔离；长合集限高、内嵌分 P、CID 导航及播放器保留。
- API 关注与合集相关测试 13 项通过，包括 CSRF、长 ID、缺失关系拒绝、缺失统计降级、503 单次提交和旧会话响应丢弃。
- `packages/bili_api/tool/video_author_smoke.dart` 游客只读烟测成功：样本 UP 粉丝 8213627、累计获赞 73667027；合集 2 项、播放量 157688、2 项均有时长。数值仅对应当次观察；不使用账号 Cookie，不打印媒体 URL，不执行真实关注写入。
- `flutter build windows --debug --no-pub` 与最终 `flutter build windows --release --no-pub` 均成功。原生播放后端本轮未改动。
- 最后一次 `tool/check.ps1 -SkipPub` 完整通过：根应用 188 项、bili_api 65 项、bili_player 16 项、bili_danmaku 5 项，共 274 项；四部分格式与静态分析均通过。此前检查遇到工作区同期路由修改尚未格式化，最终检查时已消除。
- Flutter 控件渲染已检查明暗主题，演示数据预览保存在本地 `artifacts/sidebar-light.png` 和 `artifacts/sidebar-dark.png`。使用项目实际组件，封面／头像为占位；这些是布局验证图，不是真实账号数据或原生播放截图。
- Windows 调试版通过 `flutter run -d windows --debug --no-pub -t lib/main.dart` 启动并显示首页。界面自动化在继续操作时重复报告 `call get_window_state before using this window`，因此未把播放页原生截图记作实测通过。

真实账号关注／取消关注未在线执行；Android/macOS 未构建或实机验证，不能从 Windows 结果推导。
