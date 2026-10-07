# 动态分享、评论与点赞

日期：2026-10-07。覆盖首页“动态”的全部／视频／图文子标签和个人／UP 主空间动态，沿用既有图片预览、富文本、作者及视频导航；“视频动态”频道继续使用专用视频网格。

## 交互与状态

- 卡片分享入口提供复制 `https://t.bilibili.com/<动态 ID>` 链接和带可选文字的转发弹窗。复制允许游客；只有用户明确点击“转发动态”才提交一次账号写请求。成功更新转发数，未知结果保留草稿并要求用户核对后才允许再次提交。
- 评论在应用内弹窗查看，复用 `features/comments` 控制器和 `shared/ui` 评论区的最热／最新、分页、楼中楼、回复、评论点赞、表情选择、图片预览和用户主页跳转。草稿只在当前编辑框保存；成功发送后只清空仍与提交内容相同的草稿。账号 scope/epoch 改变时清理草稿和评论状态。控制栏和草稿按实际可用高度测量；键盘/大字体导致空间不足时，发送区可滚动，不把按钮挤出布局。
- 动态点赞和取消点赞读取服务端初始 `module_stat.like.status`，提交成功才更新数量/选中态。进行中禁用重复点击；未知结果禁止重复提交，可通过详情只读请求确认新的服务端点赞状态。
- 被删除、服务端关闭评论或禁止转发／点赞的动态停用相应写入口。未知评论类型不猜测 `oid/type`；列表缺少目标时先读取详情，仍不支持则提示使用官方页面。
- 操作控制器以动态 ID 共享首页／空间的即时操作状态；评论按 `(oid, type)` 隔离。账号变化和关闭页面取消请求，scope/epoch 与请求代次丢弃迟到结果。评论和楼中楼各保留最多 500 条；动态列表原有容量和取消规则保持。

## 协议登记

以下均为 Web Cookie profile、JSON 响应、无 WBI／App token。读取沿用 API 层有界重试、25 秒应用 deadline；写入只发送一次，无自动重试或结果不明时重放。

| 能力 | host / method / path | 关键参数、鉴权与分页 |
| --- | --- | --- |
| 动态详情/点赞确认 | `api.bilibili.com` GET `/x/polymer/web-dynamic/v1/detail` | `id` 十进制字符串，`features=itemOpusStyle`；Cookie 可选，无 CSRF |
| 评论列表 | `api.bilibili.com` GET `/x/v2/reply` | `oid`、`type`、`pn`、`ps=20`、`sort=1/0`、`nohot=1`；Cookie 可选 |
| 楼中楼 | `api.bilibili.com` GET `/x/v2/reply/reply` | 同一 `oid/type`，`root`、`pn`、`ps=20` |
| 评论点赞/取消 | `api.bilibili.com` POST `/x/v2/reply/action` | form：`oid/type/rpid/action=1/0`；Cookie 必需，表单注入 `csrf` |
| 发送评论/回复 | `api.bilibili.com` POST `/x/v2/reply/add` | form：`oid/type/message/root/parent`；Cookie/CSRF；正文最多 1000 字符 |
| 评论表情 | `api.bilibili.com` GET `/x/emote/user/panel/web` | 沿用 `business=reply`、按需读取；选中仅插入草稿 |
| 动态点赞/取消 | `api.bilibili.com` POST `/x/dynamic/feed/dyn/thumb` | JSON：`dyn_id_str` 字符串、`up=1/2`；Cookie，query 注入 `csrf` |
| 转发动态 | `api.bilibili.com` POST `/x/dynamic/feed/create/dyn` | JSON：`dyn_req.scene=4`、`content.contents`、Web 来源 meta，根 `web_repost_src.dyn_id_str`；query `platform=web`、`csrf` |

评论身份优先直接采用 `basic.comment_id_str/comment_type`，与分享／点赞使用的动态 ID 分开。支持类型 1 视频、11 图片、12 专栏、14 音频、17 文字／转发、33 课程；老响应缺少 basic 评论字段时，只对明确内容类型使用对应业务 ID，文字／转发使用动态 ID。服务端已经给出但格式错误/未知的 basic 字段不被猜测覆盖。所有 ID 保留十进制字符串，禁止经浮点数转换。

`ApiJsonTransport` 与既有 form 共用凭据作用域、会话检查、deadline、响应分类和显式写端点白名单，Dio 不跟随重定向。JSON 序列化一次；CSRF 从目标 host 可用的 Cookie 获取，不能从 UI 或普通设置取值。

## 来源与采用范围

只读参考本地 `biliuwp-lite` 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [DynamicAPI](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/DynamicAPI.cs)、[动态详情评论身份](../../../biliuwp-lite/src/BiliLite.UWP/Pages/User/DynamicDetailPage.xaml.cs) 和 [动态操作服务](../../../biliuwp-lite/src/BiliLite.UWP/Services/Biz/UserDynamicService.cs)；`bili-kernel` 提交 `e26f6dbd071e20d4220806fcff7bd675f3c29fc5` 的 [MomentAdapter](../../../bili-kernel/src/Services/Services.Moment/Core/Adapters/MomentAdapter.cs)、[CommentTargetType](../../../bili-kernel/src/BiliKernel.Abstractions/Models/CommentTargetType.cs) 和 [MomentClient](../../../bili-kernel/src/Services/Services.Moment/Core/MomentClient.cs)。借鉴 ID/type、点赞取消和转发职责，自行编写 Dart/Flutter，未复制 C#、schema 或新资源，沿用 [许可边界](../references.md#4-许可与来源记录)。

同时读取 [官网动态页](https://t.bilibili.com/) 公开加载的 [Web 脚本](https://s1.hdslb.com/bfs/static/2233-monorepo/dyn-home/static/js/index.611b9e16.js)：评论取 basic 的评论身份，点赞使用上述新 Web JSON 端点，转发是 `scene=4` 和根 `web_repost_src.dyn_id_str`。因此没有将参考仓库 App 签名／gRPC 通道照搬到 Web 会话。

## 验证与边界

本轮 `tool/check.ps1 -SkipPub` 通过：根应用 1051、`bili_api` 291、`bili_player` 22、`bili_danmaku` 32 项测试，共 1396 项；根应用和三个包的格式／静态分析通过。覆盖 JSON/CSRF、长 ID 与原文编码、不同评论 type 的全部读写、禁止重定向、单次写、重复点击、账号切换取消／迟到响应、未知结果锁定、游客复制、评论／回复／转发入口、发送草稿保留、窄屏两倍文字和键盘上的四行草稿发布；现有视频评论、富内容与图文预览回归通过。

Windows Profile 只读探针构建成功、进程退出码 0。现有登录会话读取 20 条动态，20 条都有合法评论目标；采样 type=1（视频）、17（文字/转发）、11（图片）三类评论分别返回 20／2／20 条，各自楼中楼返回 5／1／1 条，动态详情读取成功。只记录类型和数量，不输出内容或账号身份。游客的独立 HTTP 读取受到服务端限制，不将该结果当作登录态功能失败。

`flutter build windows --profile -t lib/main.dart` 成功，已将 `build/windows/x64/runner/Profile/bilisail.exe` 恢复为普通应用入口。未自动提交真实账号的点赞、发送或转发；实际写入、桌面鼠标／触感及 Android/macOS 设备交互尚未验证。本轮共用评论布局的视觉证据来自 widget 测试，不宣称完成三端实机验收。日志位于本机忽略目录 `artifacts/dynamic-interactions-check.log`、`dynamic-interactions-probe-build.log`、`dynamic-interactions-probe.log` 和 `dynamic-interactions-build.log`。

显式开发探针 [dynamic_interactions_probe.dart](../../tool/dynamic_interactions_probe.dart) 使用既有安全会话读取一页动态、最多三类评论及其楼中楼、一个动态详情。只输出类型/数量/错误分类，不输出 ID、正文、URL 或凭据；普通启动和 CI 不运行此探针，也没有写操作路径。运行后需以 `lib/main.dart` 恢复普通 Windows 构建。
