# 消息表情、发送与管理入口补齐

日期：2026-11-05。在[首轮消息中心重构](messages-redesign-2026-11-05.md)之后，按用户反馈继续完善消息解析、私信、回复通知与外层管理入口。本轮完成验证后单独提交，保留同期个人空间及性能专项改动。

## 参考与方案

只读参考 PiliPlus `3565a2031fbdca180d03fad9999e48b4b0f7a4b5` 的 `lib/pages/whisper`、`whisper_detail`、`whisper_link_setting`、`whisper_settings`、`msg_feed_top`、`lib/utils/extension/three_dot_ext.dart` 和 `lib/http/msg.dart`。仅借鉴职责与协议字段，独立实现，不复制 GPLv3 应用源码、资源或 gRPC schema。

同日复核[官方消息中心](https://message.bilibili.com/)公开脚本 [index.f9c057f6.js](https://s1.hdslb.com/bfs/static/2233-monorepo/message-pc/static/js/index.f9c057f6.js)的 Web 设置、会话批量已读、屏蔽词、举报和通知回复参数。公开脚本核对不等于在线写操作验收；正常验证不访问真实账号写接口。

- 消息内容解析表情元数据；私信展示使用临时内存图像，未知 token 保留文字。输入框提供表情选择、选图预览和显式发送；不因选择图片自动上传或发送，图片与文字采用服务端不同消息类型。
- 移除最外层刷新／官方消息页按钮，消息首页提供新增粉丝、一键已读和更多；聊天标题显示头像昵称，右侧齿轮打开原生聊天设置。宽窄布局、返回优先级、草稿及隐藏页面规则保留。
- 消息设置、屏蔽词、黑名单、通讯录、粉丝及已有助手／群消息均在应用内呈现。PiliPlus 的粉丝团助手分支本身尚为 TODO，不编造助手账号；通过 Web 会话数据展示真实已有会话和空态。
- 一键已读在已加载且具有有效精确序号的私信范围内逐条提交真实回执，不仅修改本地计数；确认框明确条数及未加载内容不在范围内。清空操作也明确列出已加载并确认的会话范围，不声称删除服务端全部历史。写入单次尝试，未知结果停止后续写并提示核对。
- 回复／点赞通知用紧凑列表，仅展示回复正文、短原评论／标题与可用封面，不展开完整视频简介。回复按钮与原视频入口分开。
- 回复身份严格来自 `item.business_id/subject_id/source_id/root_id`；对应 `type/oid/parent/root`，根 ID 缺失时回退 `source_id`，不使用通知 ID。复用现有 `CommentsController` 与共享 `CommentsPanel` 的独立发送模式，不重复实现评论上传与发送协议。评论楼中楼图片仍遵循现有平台限制；私信支持图片发送。
- 所有读取／写入继续检查账号 scope、session epoch、取消与 deadline，迟到选图／上传／设置响应不得写入新账号。用户未显式发起发送或设置变更时不提交账户写操作。

## 协议补充

| 能力 | Web 端点 | 边界 |
| --- | --- | --- |
| 私信表情 | GET `api.bilibili.com/x/emote/user/panel/web?business=im` | 有界列表与单条元数据，缺失表情保留 token |
| 私信图片上传 | POST `api.bilibili.com/x/dynamic/feed/draw/upload_bfs` | multipart `file_up/biz=im/CSRF`，10 MiB，JPEG/PNG/GIF，校验 CDN 与像素上限，单次尝试 |
| 私信发送 | POST `api.vc.bilibili.com/web_im/v1/web_im/send_msg` | `msg_type=1/2`，图片内容仅来自本次有效上传，单次提交 |
| 私信一键已读 | GET 会话列表与 POST `api.vc.bilibili.com/session_svr/v1/session_svr/update_ack` | 在用户确认范围内逐条单次确认，未知结果停止；`ack_sessions` 为已读变更同步读取，不误作批量写入 |
| 消息设置 | GET/POST `api.vc.bilibili.com/link_setting/v1/link_setting/get`、`/set` | 只提交已登记键和精确枚举值，成功后更新 |
| 聊天内容推送 | GET/POST `api.vc.bilibili.com/link_setting/v1/link_setting/get_session_ss`、`/set_push_ss` | 与免打扰分别管理，服务端允许显示时才提供内容推送开关 |
| 屏蔽词 | GET/POST `api.vc.bilibili.com/x/im/link_setting/get_block_words`、`/add_block_word`、`/del_block_word` | 沿用服务端数量／长度限制，写入不重放 |
| 黑名单 | GET/POST `api.bilibili.com/x/relation`、`/x/relation/blacks`、`/x/relation/modify` | 使用现有关系修改端点，明确确认拉黑影响 |
| 举报 | POST `api.vc.bilibili.com/x/bplus/im/report/add` | 明确用户选择原因后单次提交，不自动上报 |

## 验证记录

本轮以 `af38c9f` 为基线，将消息改动与共享文件中的本任务差异复制到独立校验工作区；没有复制同期个人空间或性能专项改动。提交前比较 Git tree，确认暂存源码与该校验目录一致。没有新增依赖、数据库迁移或消息持久化，五份锁文件保持原样。

| 检查 | 结果 |
| --- | --- |
| `tool/check.ps1 -EnforceLockfile -Stage Lint` | 根应用及四包锁定解析、格式、静态分析、Linux 维护适配器和打包边界脚本通过 |
| `tool/check.ps1 -SkipPub -Stage RootTests` | 独立消息补丁全量 4241 项通过，13 项按既有开关跳过 |
| `tool/check.ps1 -SkipPub -Stage PackageTests` | API 621、播放器 148、弹幕 161、mux 5 项通过，共 935 项；另 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过 |
| 最终消息目录回归 | 151 项通过，包括全量之后新增的两项举报交互回归；默认理由无需补充说明即可提交，“其他”缺说明显示校验且不写入 |
| UI／共享组件定向 | UI 原有与新增 65 项通过；最后举报修正后中心 UI 9 项通过；共享评论及路由 66 项、通知直接回复 3 项、工具栏 2 项通过 |
| 视觉检查 | 390×900 与 1440×900 虚构数据预览 2 项通过；检查消息首页、聊天与紧凑通知，图片保存在本机忽略目录 |
| 公开只读在线烟测 | 匿名 `business=im` 表情面板返回 `code=0` 和 1 个表情包；未读取真实账号私信或执行写请求 |
| 最终分析／差异 | 最后举报修改重新执行根静态分析、格式及 `git diff --check`；无问题 |

主工作区初次全量混有同期个人空间改动；本任务的旧标题／返回断言已按宽窄布局修正，未为通过检查而修改个人空间。最终验收使用上述独立源码。全量之后只调整了举报说明校验并新增两项测试，由最新消息目录 151 项覆盖；随后重新完成静态分析。

独立工作区首次 SQLite 3.7.0 原生组件下载因网络中断失败，之后仅向其构建缓存复制 SHA-256 为 `98b4be674137b85ec111a7a29223e87aa41c3e964d61f73602471ddd7b9c56ce` 的现有 Windows x64 DLL，交由固定版本构建 hook 正常重新校验。没有改动 Pub 缓存、关闭 TLS 或跳过哈希校验，组件不进入提交。

检查及预览位于忽略目录 `artifacts/messages-rich-followup/`：`isolated-lint.log`、`isolated-root-final.log`、`isolated-packages.log`、`isolated-messages-final.log`、`isolated-analyze-final.log`、`center-ui-final.log` 和 `preview-final.log`；PNG 包含 `messages-narrow.png`、`messages-wide.png`、`conversation-narrow.png`、`notifications-narrow.png`、`notifications-wide.png`。全部消息 fixture 为虚构内容。

检测到 Windows Flutter 调试实例时曾热重载成功；该实例入口为个人空间预览，工具同时报告该预览中 `ProfileScreen/_ProfileBiographyState` 的类型异常，不能视为消息界面原生验收。最后一次重试时调试实例已退出。没有执行真实账号图片上传、发送、回复、设置写入或设备安装验收，也未构建安装包。App gRPC 专属能力仍不从 Web 登录凭空推导：粉丝团入口展示已有群会话、只读；楼中楼评论图片沿用现有平台限制，私信图片完整支持。
