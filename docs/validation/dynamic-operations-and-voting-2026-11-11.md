# 动态操作菜单与应用内投票

日期：2026-11-11。延续[动态发布能力](dynamic-publishing-parity-2026-11-11.md)，补齐阅读动态时的管理、分享、屏蔽与投票。账号写入由明确点击触发，离线测试不使用真实账号。

工作期间远端新增了[投票查看实现](dynamic-poll-viewing-2026-11-11.md)及其他修复。先合并到 `f2d10d0a`，再保留同期评论提交 `f7e0a1a9`、`0076c6fe`；沿用远端投票端口、领域模型、服务端本人选择解析和截止计时，新增关注用户投票、图片预览、响应式布局及会话内跨弹窗的不明写入锁。两组协议／控制器／界面用例均保留，动态状态克隆继续保留同期加入的头像挂件。

## 参考与采用范围

只读核对 PiliPlus `4fce4bb5a35c425aee759ef9263352316a29e355` 的 `lib/pages/dynamics/widgets/{author_panel,dynamic_panel,vote}.dart`、`lib/pages/dynamics_detail/{view,controller}.dart`、`lib/pages/member_dynamics/controller.dart`、`lib/pages/save_panel/view.dart`、`lib/http/{dynamics,msg,user,reply,api,init}.dart` 和投票／互动模型；公开协议来源为同一提交的[动态 HTTP 实现](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4fce4bb5a35c425aee759ef9263352316a29e355/lib/http/dynamics.dart)。

实际 overrides／锁文件与发布专项一致：核心和平台库 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频包 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`。仅参考协议事实与交互职责，独立实现，没有复制 GPLv3 应用代码／资源，没有修改相邻仓库、依赖和 Pub 缓存。

## 菜单与状态

首页、动态、话题、空间和详情共用 `InteractiveDynamicPostCard`。右上角更多、长按和鼠标右键打开同一菜单，保留原有详情入口。菜单使用项目主题和受当前窗口、SafeArea、键盘限制的滚动对话框。

| 动作 | 行为与范围 |
| --- | --- |
| 分享／复制 | 复用已有转发／链接分享；另提供复制正文、复制动态链接 |
| 分享至消息 | 图文、专栏、文字动态生成对应 Web IM 卡片；选择收件人后再次确认，保留业务 oid／类型 |
| 稍后再看 | 动态或原转发包含视频、且宿主提供能力时复用视频操作端口 |
| 保存动态 | 实际动态卡片和原链接生成 PNG 预览；最多 20000 高、4000 万像素、32 MB；复用现有图片导出，Windows／macOS／Android 可保存，其余平台按 capability 禁用 |
| 屏蔽与拉黑 | 临时屏蔽从共享动态列表移除作者，可在动态工具条恢复；重启／账号变化恢复。登录用户可确认后复用服务端黑名单，成功后本地隐藏。没有新增 PiliPlus 的游客持久化本地黑名单 |
| 置顶／可见性 | 仅本人动态；已加载列表同步更新，空间将置顶项移到最前；支持所有人／仅自己可见 |
| 互动设置 | 读取服务端 can_modify，控制评论精选和允许评论；使用真实 CommentTarget(oid,type) |
| 编辑 | 本人受支持的文字、图片、转发和短图文；独立草稿保留提及／表情／投票富文本、远端图片、话题、预约、转发身份及评论设置，不覆盖新动态草稿 |
| 删除／举报 | 删除前确认，成功后从共享列表移除；举报显式提交，其他理由必须填写说明，最多 500 字 |
| 公开可见性 | 无 Cookie 读取核对游客能否读取；网络／协议错误显示失败，不据此认定限流或屏蔽 |

编辑前重新读取原始内容；超过 1000 字／20 字标题／18 图边界、包含不支持的卡片或缺少可靠图片元数据时拒绝编辑，避免截断后覆盖原文。既有图片不重复上传，未知体积不捏造 img_size。编辑不提供定时发布、创建新投票／预约，已有附件身份继续保留。

动态覆盖、删除集合、临时屏蔽和写入锁由 `dynamicContentProvider` 持有，按账号／session epoch 清空，容量分别为 512／512／128／512。列表先合并和过滤再计算自然高度，不为已删／隐藏卡片留下滚动空洞。异步结果核对账号、epoch、请求 generation 和取消状态。

写请求不自动重试。网络、超时、HTTP 或协议结果不明时锁定动作，关闭重开菜单也不能直接重放；读取动态／互动状态可核对相应结果。投票结果不明时，刷新查到已投记录才自动解除；仍无记录时，需要明确确认未投票后才允许再次提交。

## 投票

投票卡片和行内链接在应用内打开，转发中的投票保留所属原动态 ID。支持文字／图片选项、单选／最多 N 项、匿名投票、显示比例、各项票数、截止时间、已投／已结束状态，以及关注的人的投票和用户入口。选项图片可长按／右键查看大图。多选百分比以全部选项票数之和计算。

游客可读取并选择，提交引导登录；已投、到期、提交中、结果不明时禁止再次投票。选择、匿名开关、查看比例不发送账号写入。正文滚动和提交区分别布局，适配窄屏、大字体、短横屏和键盘。

## 协议登记

均为 Web profile；Cookie／CSRF 从当前会话取得，读取共用有界重试与 deadline，写入只尝试一次。HTTP JSON 不表示 App token 或 gRPC 能力。

| Endpoint | Host / method / path | 请求和响应 |
| --- | --- | --- |
| dynamic_remove | api.bilibili.com POST `/x/dynamic/feed/operate/remove` | JSON dyn_id_str；query platform=web／CSRF |
| dynamic_pin | api.bilibili.com POST `/x/dynamic/feed/space/set_top` 或 `/rm_top` | JSON dyn_str；query CSRF |
| dynamic_visibility | api.bilibili.com POST `/x/dynamic/feed/dyn/private_pub_setting` | JSON object_id（dyn_id 的 JSON 字符串）／action=private_pub 或 public_pub；query platform=web／CSRF |
| dynamic_report | api.bilibili.com POST `/x/dynamic/feed/dynamic_report/add` | form accused_uid／dynamic_id／reason_type／reason_desc／CSRF |
| dynamic_interaction | api.bilibili.com GET `/x/v2/reply/subject/interaction-status` | oid／type／web_location；up_reply_selection 与 up_reply 的 can_modify／status |
| dynamic_interaction_modify | api.bilibili.com POST `/x/v2/reply/subject/modify` | form oid／type／action=1精选、2取消精选、3关闭、4开放评论／CSRF |
| dynamic_edit_draft | api.bilibili.com GET `/x/polymer/web-dynamic/v1/detail` | id／features=itemOpusStyle；读取完整富文本和远端图片，另读取原评论策略 |
| dynamic_edit | api.bilibili.com POST `/x/dynamic/feed/edit/dyn` | WBI query platform／CSRF／设备与 w_dyn_req 元信息，JSON dyn_id_str／dyn_req／可选 web_repost_src；key 读取可刷新，最终 POST 不重放 |
| dynamic_public_check | api.bilibili.com GET `/x/polymer/web-dynamic/v1/detail` | 独立空 CookieJar，共享 transport 且不关闭所有者；不导入游客响应 Cookie 到当前账号 |
| dynamic_poll_detail | api.bilibili.com GET `/x/vote/vote_info` | vote_id；vote_info 与 my_votes |
| dynamic_poll_vote | api.bilibili.com POST `/x/vote/do_vote` | JSON vote_id／votes／voter_uid／status（1匿名）／op_bit=0／dynamic_id；CSRF 位于 query 和 body csrf／csrf_token；返回 vote_info |
| dynamic_poll_followees | api.vc.bilibili.com GET `/vote_svr/v1/vote_svr/followee_votes` | vote_id；最多 100 人，无无限分页 |
| message_share_dynamic | api.vc.bilibili.com POST `/web_im/v1/web_im/send_msg` | 复用 Web IM form／CSRF；msg_type=7，content 包含 id／title／headline／source／author／author_id／thumb |

投票 ID 使用十进制字符串校验，JSON 数值由精确整数转换；选项 2 至 20 项，索引唯一、选择不超上限、截止时间有效、计数非负，关键字段损坏返回协议错误。权限、内容类型和风控以服务端响应为准。

## 验证与未验范围

动态定向 235 项通过，另补关闭重开投票不明锁定与收件人确认回归（32 项通过的定向组合）。API 管理／投票与既有投稿、内容、卡片组合 102 项通过。布局覆盖六种 TargetPlatform 主题下 320×568 双倍字体和键盘、844×390 横屏和键盘、1280×900 深色；主题测试运行在 Windows，不能代替各系统实机。

实际 BiliTheme 与 HarmonyOS 字体的 390 宽手机、1280 宽桌面、320 宽双倍字体深色，共 3 项截图夹具、6 张截图通过并人工查看。日志及临时夹具保存在忽略的 build 目录。

Windows 模拟管理／投票夹具 Debug 构建通过，DTD 连接和最终热重载成功；运行窗口完成置顶并读取更新后的状态、选项选择、匿名投票及模拟提交，显示已完成投票，运行错误读取为空。复查另修正卡片仍只展示前 9 张的遗漏，加入 18 图完整数量断言和自然高度保留回归。最终源码重新构建、热重载并完成模拟投票后退出，未保留运行中的测试窗口。

最终在隔离工作区执行 `.\tool\check.ps1 -SkipPub`，退出码 0（`build/dynamic-isolated-check.log`）：根应用 5129、bili_api 861、bili_player 372、bili_danmaku 161、bili_mux 5 项通过，合计 6528 项；根应用 13 项因 Windows 符号链接权限、mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，跳过不算原生通过。隔离初始索引树与主工作区本任务暂存树完全一致，排除了运行中变化的同期评论样式。其形成 `f7e0a1a9` 后继续保留，组合版本动态／评论 267 项回归和静态分析通过；后续 `0076c6fe` 只增加文档和排版测试，另补跑对应测试。本任务未更改依赖或版本号，未纳入其他未提交修改。文档相对链接及 `git diff --check` 通过。

没有执行真实账号删除、编辑、置顶、可见性、举报、拉黑、消息分享或投票；在线接口可用性及 Android／Apple／Linux 实机未验。模拟运行不代表正式入口 Release 构建、真实账号写入或跨平台原生保存验收。
