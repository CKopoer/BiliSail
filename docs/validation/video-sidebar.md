# 播放页简介侧栏

日期：2026-10-05。视觉参考为本次用户提供的官方桌面客户端截图；自行实现 Flutter 布局，未复制截图资源或参考客户端代码。

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
