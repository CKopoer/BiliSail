# 播放器页面与未关闭标签状态保留

日期：2026-10-05。Flutter 3.47.6 / Dart 3.13.5，Windows x64 主机。本轮替换上一轮切离视频即卸载页面的策略；原始工程尚无提交，不填写虚构 revision。

本页保留早期四子标签及切离暂停策略的历史验证；当前简介／评论双标签及可折叠合集方案见 [播放页与评论交互](video-comments.md)，普通标签继续播放及当前验证见 [用户页、倍速与标签播放](profile-playback-rates.md)。

## 页面与子标签

本机已安装的“哔哩哔哩 UWP”播放页实际查看到：工作区标签下为左侧全高黑色播放器，右侧约 320 像素固定导航和可滚动信息；详情包含封面、标题、统计、UP、日期、简介。结合相邻 UWP 播放页源码独立实现 Flutter 布局，没有复制 XAML、代码、图片或图标。

桌面视频页隐藏首页频道/搜索工具行，媒体区贴边显示，右栏提供详情、选集、评论、推荐四个子标签。窄屏改为上下排列；媒体面板通过稳定 key 在布局间保留。右栏固定子导航，仅内容滚动，各子标签保持独立滚动位置；评论按页读取，换页滚至开头，已访问评论/推荐在页面存活期间保持订阅。

首页频道和子导航的只读接入、逐端在线边界见 [首页子频道](home-subtabs.md)。UGC 进入应用播放器；PGC、直播和图文内容通过明确的外部入口打开官方 HTTPS 页面，当前未实现原生 PGC/直播播放。未新增点赞、投币、收藏、关注、评论发送或自动上报。

## 播放状态所有权

- 工作区未关闭页面持续挂载，隐藏页面关闭 Ticker；`WorkspaceActivity` 只控制可见性，不销毁局部状态。
- `PlaybackSession` 仍独占一个 native engine。切到普通页面暂停，返回同视频沿用原媒体源与精确位置，并恢复原先播放/暂停意图。
- 视频标签之间切换时，按 owner 在内存记录毫秒位置、账号 scope、所选 cid、清晰度、倍速、音量、字幕选择及播放意图；复用单一播放器切源并恢复对应标签。不依赖磁盘续播的 5 秒阈值，因此短视频和开头几秒也可恢复。
- 关闭只释放该标签 owner；关闭 B 不清除仍打开的 A 的快照。账号变化清除全部播放快照、页面作用域和旧请求。
- 隐藏面板不挂媒体 surface，进度订阅限制在活动播放器局部；全屏异步请求按身份隔离，并且只操作自己拥有的弹出路由。
- 标签达到 16 个时拒绝新增并提示，不静默替换仍打开的标签。标签和内存快照在退出应用后不恢复。

## 新视频端点

| 能力 | Host / 方法 / Path | Profile 与鉴权 | 响应 / 分页 / 重试 | 本轮游客在线结果 |
| --- | --- | --- | --- | --- |
| 相关推荐 `getRelatedVideos` | `api.bilibili.com` GET `/x/web-interface/archive/related` | Web；Cookie 可选；无签名 | JSON `data[]`；bvid；单次列表；继承总 deadline、取消、epoch、最多 2 次额外网络/指定 5xx 重试 | 指定公开视频返回 40 条 |
| 评论 `getVideoComments` | `api.bilibili.com` GET `/x/v2/reply` | Web；Cookie 可选，游客展示范围由服务端决定；无签名 | JSON `data.replies[]/page`；oid=aid、type=1、pn、ps=20、sort=2；按服务器 count/size 翻页；同上 | 同一视频游客返回 3 条；未验证登录后的完整评论和真实多页 |

定位参考相邻 UWP 的 `Models/Requests/Api/VideoAPI.cs`、`CommentApi.cs`，采用协议含义并独立编写请求和映射。风控/认证/权限/格式错误不重试，也不回退其他内容；评论 ID 优先使用十进制字符串。回归样本手工生成且不含真实账号信息。可复现只读烟测入口为 `packages/bili_api/tool/video_extras_smoke.dart`。

## 验证记录

`tool/check.ps1 -SkipPub` 全量通过：根应用 **79** 项、`bili_api` **26** 项、`bili_player` **8** 项、`bili_danmaku` **4** 项，共 **117** 项。根与所有包格式检查、静态分析均通过。覆盖未关闭页面保留、短于 5 秒/短视频精确进度、各标签播放选项、关闭另一标签、快速请求交替、账号清理、恢复失败后切换与直接重试、16 标签上限保留，以及子标签/收藏夹导航状态。

`tool/test-windows-media.ps1` 通过。实际执行四项本地验证：受控 DASH 分轨的 headers/重定向/Range、隔离安全存储、六次全屏/Esc、工作区双视频标签。工作区原生用例确认：A 播放后切首页暂停、返回沿用 source generation；A 在约 1700ms 暂停并设置 1.5x，切 B 播放/seek 4000ms，再回 A 恢复原位置、暂停状态及 1.5x；关闭 B 不改变 A，关闭 A 后 idle。保留两个页面时仅挂一个 VideoSurface。测试器显示 5 项，其中游客公网媒体分支未启用，本轮不据此宣称公网视频原生烟测已执行。

`packages/bili_api/tool/home_smoke.dart` 通过真实 HomeClient 验证解析链：番剧推荐 20 条、时间表 57 条、直播分区 12 条；推荐直播返回 `-352`，正确分类为 rateLimited。`video_extras_smoke.dart` 验证相关推荐 40 条、游客评论 3 条。未读取真实私有账号列表。

Markdown 的 102 条本地链接已检查，无缺失；领域层、页面网络与跨包私有入口依赖边界检查通过。

Windows x64 Release 构建成功（`flutter build windows --release`），Android arm64 Debug 构建成功（`flutter build apk --debug --target-platform android-arm64`）。最终输出分别在 `build/windows/x64/runner/Release/` 和 `build/app/outputs/flutter-apk/app-debug.apk`。已启动最终 Windows Release 核对真实推荐封面及播放器贴边黑色主区、右侧固定四个子标签、详情信息与独立滚动布局。

最终 Release 手工界面复核：打开首页公开视频后正常显示实际画面与进度；评论读取并显示成功。在 00:15 暂停、选中评论子标签后，鼠标切回首页再回到视频，仍为 00:15 暂停，评论子标签与已加载内容均保持。使用应用已有会话，没有执行登录或账号写入；这只验证公开视频页面，不扩展为私有列表验收。

未用真实登录账号验证私有列表，没有执行账户写操作。Android/macOS 原生运行、长期稳定性和性能未在本轮测量；不以 debug 帧率或插件平台声明代替实机结论。
