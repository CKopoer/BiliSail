# 私信请求签名、刷新与风控

日期：2026-11-14。用户反馈“我的消息”打开私信后经常提示限流／风控。本轮核对当前源码、PiliPlus 和官方 Web 消息站的公开脚本，独立修复请求差异；没有读取真实私信、取得该次失败的服务端响应或执行真实账号写入，因此不能确认现场唯一根因，也不能保证账号风控已解除。

## 参考与证据

- 只读参考相邻 PiliPlus 提交 `217fb54f51f6764176319bbdedab2a7522d75401` 的 `lib/pages/whisper/controller.dart`、`lib/pages/whisper_detail/controller.dart`、`lib/pages/common/common_list_controller.dart`、`lib/grpc/im.dart`、`lib/http/msg.dart` 和 `lib/http/api.dart`。当前私信首页／正文使用 App gRPC，列表控制器在 `isLoading` 时拒绝重复请求，正文每页 20 条。旧 Web 端点注释也保留 WBI 参数。PiliPlus 应用是 GPLv3，本轮仅参考职责与协议行为，没有复制应用代码、生成 schema 或资源，没有修改相邻仓库或引入其运行时依赖。
- 同日读取[官方消息站](https://message.bilibili.com/)引用的公开脚本 [index.f9c057f6.js](https://s1.hdslb.com/bfs/static/2233-monorepo/message-pc/static/js/index.f9c057f6.js)。`get_sessions` 和 `fetch_session_msgs` 均明确启用 `UNIOS_WBI_ENCODE`；聊天调用每页 20 条，附加 `sender_device_id=1/build=0/mobi_app=web`；用户资料仍使用 `/x/polymer/pc-electron/v1/user/cards`，附加 `uids/build=0/mobi_app=web`。这说明现有资料端点本身与官方一致，不应依据 PiliPlus 的旧注释换回其他端点。
- BiliSail 原先两个 IM GET 走未签名的 `requestJson`，读取使用主站 Referer／Origin，资料请求缺少 `build/mobi_app`。发送等已有写请求使用消息站上下文；本次补齐读取边界。

## 频率分析与修复

消息控制器没有定时私信轮询，页面重建也不会直接请求会话列表或正文。首屏会话读取后会批量读取昵称／头像，进入会话还可能读取表情，并在可见正文加载成功后提交已读和刷新相关状态；不能把这些有条件请求当作持续轮询。

但原来的 `refresh: true` 绕过加载锁，连续点击能取消前一读取并重新发起；取消客户端请求不等于服务端没有收到它。此次对用户触发的列表、正文和整体刷新统一加加载锁。列表刷新失败后停止继续刷新未读数及正文；刷新过程中切换分类也不再让旧刷新串联新分类请求。已经确认成功的发送／已读后更新仍可替换写入前的旧读取，保留既有账号 epoch、取消和代次隔离。

会话数据已经成功读取时，独立资料接口的限流、网络或超时不再让整页失败，使用会话自带昵称／头像或 UID 后备展示，保留消息摘要、未读数与分页。共享管线仍记录资料接口的风控冷却，冷却内不重复访问它。取消、账号鉴权失败和协议错误仍传播，不能降级成有效空列表。

这些请求差异使“请求参数／上下文不完整，叠加重复手动刷新和辅助请求失败放大”成为有源码证据的待验证解释；没有现场响应，不能断言服务端一定因缺少签名拒绝，也没有依据认定正常打开页面本身存在高频轮询。

## 当前协议登记

| host／method／path | Profile、参数、响应、分页与重试 |
| --- | --- |
| `api.vc.bilibili.com` GET `/session_svr/v1/session_svr/get_sessions` | Web Cookie + WBI；主私信沿用 `session_type=1/group_fold=1/unfollow_fold=0/sort_rule=2/build=0/mobi_app=web`，分页用十进制微秒字符串 `end_ts`。助手／粉丝团读取同样签名，沿用各自类型及折叠参数。JSON `data.session_list/has_more` |
| `api.vc.bilibili.com` GET `/svr_sync/v1/svr_sync/fetch_session_msgs` | Web Cookie + WBI；`talker_id/session_type/size=20/sender_device_id=1/build=0/mobi_app=web`，历史分页保留精确字符串 `end_seqno`。JSON `data.messages/has_more/e_infos` |
| `api.bilibili.com` GET `/x/polymer/pc-electron/v1/user/cards` | Web Cookie，无 WBI／CSRF；批量 `uids`，补齐 `build=0/mobi_app=web`；键控用户资料或兼容列表，无独立分页。仅此辅助读取的限流／网络／超时允许后备展示 |

消息读取统一携带消息站 Referer／Origin，Cookie 仍按目标域、path、secure 和 expiry 筛选。签名只允许上述两个固定 VC 路径，复用已有单飞 WBI key、缓存、总 deadline 和取消机制，不增加独立 key 初始化或新的重试层。正常只读沿用共享最多三次尝试及原单次超时；WBI `-403` 只允许一次 key 刷新，限流／风控不重签、不自动重试，继续遵守 `Retry-After` 或默认 30 秒冷却。发送、已读等写入仍为单次提交，不引入 App token／gRPC、消息落盘或后台轮询。

## 验证

- 最终消息 Feature：`flutter test --no-pub test/features/messages`，181 项通过。新增重复刷新不打断进行中的读取、已确认发送替换旧读取、列表风控后不继续刷新其他数据、旧刷新在切走再切回同一分类后不能触发未读请求的回归；原有账号切换、已读和布局测试保持通过。
- 消息协议：六个 `message_*` 测试文件共 60 项通过。新增精确序号／游标签名、三个并发 IM 读取只获取一次 key、消息站 headers、风控不重试／不刷 key、冷却、辅助资料限流降级和签名期间账号切换测试；已有富消息和单次写入继续通过。
- 根 `tool/check.ps1 -SkipPub`：格式、打包边界脚本和静态分析通过；根测试 5456 项通过、13 项跳过、2 项失败，不能记作全量通过。首轮全量运行期间补入了本次分类竞态保护与回归，该回归随后在固定源码的最终消息 181 项中通过；另一失败为同期设置改动的 `responsive_layout_settings_test.dart` 快照版本断言（实际 50、期望 49），未为本任务修改设置代码。未重复整轮根测试。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：API 935 项、播放器 280 项（另有 3 项跳过）、弹幕 161 项、mux 5 项通过。mux 的 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不能视为原生封装验证通过。
- 最终 `flutter analyze --no-pub` 无问题；文档相对链接和任务差异检查通过。日志位于 `build/validation/message-risk-control-2026-11-14/`：`check.log`、`packages.log`、`analyze-final.log`、`messages-final.log`。消息复跑曾因另一个测试进程占用 SQLite DLL 无法启动，等待该进程结束后复跑成功。
- DTD 发现没有运行中的 Flutter 调试进程，因此未执行热重载。未构建安装包，未验证 Windows／Android／Apple 真实账号的私信读取和服务端风控变化，未执行真实发送／已读／会话管理操作。
