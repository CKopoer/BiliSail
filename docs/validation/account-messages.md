# 账号菜单与消息验证

日期：2026-10-06。环境：Windows x64，Flutter 3.47.6 / Dart 3.13.5。按用户要求参考相邻 UWP 客户端和 C# API 内核提前接入，不代表完整阶段或三端验收。

## 交互与范围

已登录时点击右上头像，打开从右侧滑入的全高账号面板。面板占屏幕宽度的 80%，上限 360 逻辑像素；内容避开系统安全区，关闭按钮固定在顶部，资料和入口可滚动。点击遮罩、关闭按钮、系统返回或 Esc 可关闭。显示头像、昵称、等级/经验、会员标签、硬币、关注/粉丝/动态数量；最高等级的 `next_exp="--"` 显示“已满级”，缺失资料显示占位并提供重试。未登录沿用登录窗口。

| 按钮/信息 | 当前行为 |
| --- | --- |
| 个人中心 | 打开自己的独立用户标签 |
| 关注、粉丝、动态统计 | 打开自己的用户页并选中对应列表 |
| 我的消息 | 打开可复用的消息标签，头像和菜单显示未读总数 |
| 稍后再看、我的收藏 | 跳转现有首页对应频道 |
| 历史记录 | 打开现有本地播放历史 |
| 直播中心 | 跳转现有直播“我的关注”；未扩展 UWP 的装扮/签到能力 |
| 退出登录 | 复用现有凭据清理与账号任务取消 |

消息页包含私信、回复我的、@我的、收到的赞和系统通知。宽窗口使用会话/正文双栏，窄窗口在列表与会话间切换；作者可打开用户页，支持的 BV 链接在应用内打开，其他允许的 B 站链接交由系统浏览器。

私信支持会话列表分页、加载更早消息、文本发送和独立的“标为已读”按钮。打开会话不自动写已读。发送限 1–1000 个 Unicode 字符，失败保留草稿；网络/超时导致结果不明时提示刷新核对，不自动重发。系统/群组会话关闭文本发送。图片消息可阅读；撤回内容不解析或展示，暂不支持的富消息显示类型提示。系统通知实测没有可用翻页游标，当前仅显示最近 20 条，并提供官方消息页入口。

## 端点登记

均使用 Web Cookie profile；以下读取不需要 WBI。所有 JSON 经协议包映射为不可变领域模型，页面不解析响应。

| host | method / path | 参数、响应与分页 |
| --- | --- | --- |
| `api.bilibili.com` | GET `/x/web-interface/nav`、`/x/web-interface/nav/stat` | 校验 `isLogin` 和当前 MID；读取 `level_info`、`vip_label`、`money` 与三类统计 |
| `api.bilibili.com` | GET `/x/msgfeed/unread` | `chat/reply/at/like/sys_msg`；缺失计数按 0 处理 |
| `api.vc.bilibili.com` | GET `/session_svr/v1/session_svr/get_sessions` | `session_type=1`、折叠和排序参数；`session_list/has_more`，`end_ts` 为十进制微秒游标 |
| `api.bilibili.com` | GET `/x/polymer/pc-electron/v1/user/cards` | `uids` 为逗号分隔十进制 ID；读取按 MID 键控的资料对象，兼容列表形态 |
| `api.vc.bilibili.com` | GET `/svr_sync/v1/svr_sync/fetch_session_msgs` | `talker_id/session_type/size=30`；`messages/has_more`，`end_seqno` 为十进制序号 |
| `api.bilibili.com` | GET `/x/msgfeed/reply`、`/at`、`/like` | `id` 与 `reply_time/at_time/like_time`；`cursor.is_end`，点赞合并 `latest/total` 并去重 |
| `message.bilibili.com` | GET `/x/sys-msg/query_user_notify` | `page_size=20/build=0/mobi_app=web`；`system_notify_list`，`time_at` 可为日期字符串；空 `data` 是有效空列表 |
| `api.vc.bilibili.com` | POST `/web_im/v1/web_im/send_msg` | 单人文本私信；原始 JSON 文本交传输层编码一次，携带 `csrf` 和 `csrf_token`；仅显式发送触发 |
| `api.vc.bilibili.com` | POST `/session_svr/v1/session_svr/update_ack` | `talker_id/session_type/ack_seqno`；确认已显示的最新序号，携带 CSRF；仅显式按钮触发 |

VC 写入口只允许上述两个固定路径，Cookie 按目标 host/domain/path/secure/expiry 筛选，Origin/Referer 使用消息站点，保留系统 TLS 验证。GET 沿用共享协议层最多 3 次尝试、单次 12 秒超时及 Repository 总计 25 秒 deadline；消息 Feature 不叠加重试。POST 单次尝试，不自动重放。

## 状态、容量与隐私

`auth` 负责账号摘要与菜单，`messages` 负责收件箱和线程，组合根注入未读指示端口，两个 Feature 不循环依赖。网络操作携带账号 scope/session epoch；控制器另校验列表和线程请求代次。切类别、换会话、刷新会取消旧读取；账号变化和销毁取消读写并拒绝旧响应。登出清除私信草稿。

每个收件箱/线程最多 500 条，线程保留最新 500 条；游标不前进或空页停止加载。草稿最多保留 500 个会话。序号和游标一直使用十进制字符串/BigInt，不经过浮点数；线程使用序号去重，避免上游系统消息重复 `msg_key=0` 丢失内容。

私信、草稿不写 SQLite 或普通文件。私信图片使用临时内存图像，在销毁时驱逐解码缓存，不进入公开图片磁盘缓存；图片请求不附带账号凭据。没有新增自动遥测、消息 WS、后台轮询或桌面推送。未读数在登录后的首次读取、头像菜单打开、消息手动刷新和显式写入完成后更新，不能视作实时推送。

## 行为与本机验证

测试使用 fake transport/repository 与虚构数据，不访问真实账号写接口。协议测试覆盖超出 JavaScript 精确整数范围的 ID/序号、游标停止、列表/键控用户资料、点赞合并、撤回隐藏、未知/损坏消息、空系统通知、中文及特殊字符编码、CSRF/目标 Cookie scope、写请求不重试与取消。

控制器测试覆盖账号/epoch/类别/会话旧响应、销毁取消、未知写结果、重复发送保护、只确认已显示的序号、500 条容量。Widget/路由测试覆盖所有菜单入口、对应用户页子列表、直播关注初始频道、消息标签复用与未关闭会话保留、失败草稿、发送期间换会话后成功清除草稿、登出清理及 360/375 像素窗口两倍文字大小。

Windows 原生只读测试 [windows_messages_test.dart](../../integration_test/windows_messages_test.dart) 直接读取系统安全存储中的已有 Web 会话，仅在内存恢复 Cookie，不更改安全存储、不发送消息、不写已读。日志只输出字段名/类型、条数和分页状态，不记录账号 ID、消息内容、Cookie 或 URL query。已验证结果：

- 账号摘要等级 6，关注/粉丝/动态三类统计均存在；未读响应包含五类。
- 私信会话首/次页各 20 条，线程首/次页各 30 条。
- 回复首/次页各 20 条，@列表 2 条，点赞首/次页各 20 条。
- 系统通知读取 20 条；不承诺历史翻页。

本轮最终验证结果：

| 检查 | 结果 |
| --- | --- |
| `tool/check.ps1 -SkipPub` | 根应用与三个包格式/静态分析通过；根应用 514、API 170、播放器 16、弹幕 10 项测试通过 |
| Windows 原生已有会话只读测试 | 1 项通过，上述五类响应与分页均实测；未执行写请求 |
| 菜单及宽/窄消息界面渲染 | 6 项通过，人工查看使用虚构数据的 PNG；中文字体、菜单入口和消息气泡正常 |
| 最终 `flutter analyze --no-pub` | 通过，包含同时保留的工作区图片查看器修改 |
| 独立源码快照 `flutter build windows --release --no-pub` | Windows x64 Release 构建通过；可执行文件、Flutter/SQLite/播放器运行库、AOT 和资源文件复制后哈希核对通过 |
| 文档相对链接/源码路径、`git diff --check` | 通过 |

当前正在运行的原发布版没有被停止或覆盖。新发布包位于本机忽略目录 `artifacts/bili-lite-account-messages-windows-x64/`，入口为 `bili_lite.exe`；请保持整目录一起使用。构建使用 `artifacts/account-messages-build/` 的当前源码快照，保留工作区已有及并行修改。初次原生资产下载受网络影响失败后，按锁定插件的 MD5/SHA-256 校验本机缓存的 mpv、ANGLE 与 SQLite，再复用到预览构建缓存；没有关闭 TLS 或跳过校验。独立构建的安装目录显式设置为预览 Release 目录。

界面 PNG 和脱敏日志保存于本机忽略目录 `artifacts/message-ui-preview/`：`account-menu.png`、`messages-wide.png`、`messages-narrow.png`、`check.log`、`windows-message-read.log` 和 `windows-release-build.log`。预览消息是虚构数据。

## 2026-10-07：账号右侧面板

头像账号菜单由锚定弹窗改为右侧滑入面板，菜单项触控高度至少 48 像素。面板关闭后才触发已有导航；账号变化关闭面板，未读刷新及所有账户入口沿用原有控制器。减少动画偏好下直接显示面板。没有新增依赖、协议或存储变更。

- 账号菜单及登录窗口针对性测试共 17 项通过，覆盖滑入方向/全高、关闭按钮/遮罩/Esc/系统返回、资料与跳转、账号变化、退出登录，以及 320/360 像素竖屏和 740×360 横屏两倍字号。360 像素用例另验证顶部/底部安全区和滚动后关闭按钮可用。
- `tool/check.ps1 -SkipPub` 通过：根应用和三个包格式、静态分析通过，根应用 954、API 282、播放器 22、弹幕 32 项测试通过。
- 人工查看 390×844 与 900×720 的虚构账号渲染 PNG，分别保存为 `artifacts/account-panel-preview/account-panel-390.png` 和 `account-panel-900.png`；完整检查日志为同目录 `check.log`。
- 本次仅验证 Flutter 布局与交互，未执行真实账号写操作，未构建，也未做 Android/macOS/Windows 原生设备运行验收。

## 2026-10-07：窄屏账号入口修复

原工具栏在宽度小于 760 时，用固定“账号”图标替代注入的 `AccountButton`，点击后把真正的按钮放进底部弹层。这个外层入口没有读取登录状态，造成游客看到“账号”提示，并且需要再点击一次才能打开登录窗口。

首页和搜索页工具栏改为在所有宽度直接使用同一个 `AccountButton`：游客入口提示“登录”，一次点击打开登录窗口；已登录入口显示头像和未读数，一次点击打开右侧账号面板。窗口宽度只调整工具栏的行布局，不再改变账号入口或增加底部弹层。

[工具栏回归测试](../../test/app/shell_account_test.dart)覆盖单标签页/多标签页、首页/搜索页、1200→760→759→400→320→1200 宽度变化、320 像素两倍字号，以及游客→登录→退出的入口更新和面板关闭。与现有登录窗口、账号面板及工具栏布局测试合计 26 项通过。本次使用虚构会话，没有执行真实登录或账户写操作；Android/macOS/Windows 原生设备运行未验证。

`tool/check.ps1 -SkipPub` 完整检查通过：根应用与三个包格式、静态分析通过，当前工作区根应用 965、API 282、播放器 22、弹幕 32 项测试通过，共 1301 项。文档相对链接和本次差异检查通过；日志位于本机忽略目录 `artifacts/narrow-account-entry/check.log`。本次未构建。

## 未验证或未实现

真实文本发送、真实已读写操作没有在线执行，仅模拟验证协议/行为；Android/macOS 原生构建和设备运行本轮未验证。图片上传、表情选择、新建私信会话、完整富消息渲染和后台推送未实现；系统历史超过最近 20 条使用官方消息页。没有新增依赖或数据库 migration，也没有修改原生播放实现。

菜单/协议参考源及许可范围见 [参考记录](../references.md#账号菜单与消息补充参考)。本轮读取的相邻仓库快照：UWP `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0`，内核 `e26f6dbd071e20d4220806fcff7bd675f3c29fc5`；独立实现，没有新增复制上游代码、schema 或资源。
