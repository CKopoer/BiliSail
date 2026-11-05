# 私信宽屏头像与助手跳转修复

日期：2026-11-05。按用户反馈修复消息中心中的宽屏聊天与 UP 助手入口；构建和实机确认由用户后续执行。

## 参考与实现

只读核对相邻 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/pages/whisper/widgets/item.dart`、`lib/pages/whisper_secondary/{controller,view}.dart`、`lib/pages/whisper_detail/view.dart`、`lib/pages/whisper_detail/widget/chat_item.dart` 及 `lib/http/msg.dart`，并核对其 `pubspec.yaml` overrides 与锁文件。参考目标会话身份、助手列表进入聊天和左右气泡的交互职责，独立编写 Flutter 实现；没有复制 GPLv3 应用源码、资源或生成 schema，没有修改相邻仓库、依赖或五份锁文件。

- 聊天消息列表占满分配给正文的区域，双方头像分别距离区域左右边界 16px。气泡继续保留 460px 最大宽度，窄屏自然换行。修复仅移除整个列表的 625px 居中限制，没有扩大单个富消息或图片的阅读宽度。
- 工作区的消息页在根 Navigator 下拥有独立的 `messagesControllerProvider`。助手弹窗由根 Navigator 承载，原先从弹窗读取控制器会更新另一份消息状态，导致弹窗关闭而原页面没有打开会话。现在由调用页面提供打开会话回调，使用原始 talker ID 与 session type，进入私信分类并选择目标会话；同名创作助手不会合并。
- 打开回调检查源页面仍挂载、Repository 身份及账号 scope/session epoch。源页面关闭、账号切换或同账号会话过期后，旧弹窗不能更新新的消息状态。原有系统助手只读限制继续生效。
- 沿用现有 Web 会话与历史消息协议，没有引入 App gRPC、假定助手账号或发起额外账户写请求。

## 自动验证

| 检查 | 结果 |
| --- | --- |
| 新增 `private_message_layout_navigation_test.dart` | 12 项通过：390/1280/1800px 头像边界及气泡限宽；两个同名创作助手和社区会话在 390/1440px 中打开；账号切换与迟到列表、同账号 epoch 更新、源页面关闭隔离 |
| 首轮修复前回归 | 9 项中的 8 项按预期失败：两个宽屏头像位置、三个助手在两种宽度中的目标页选择；390px 头像布局原本通过 |
| `flutter test --no-pub test/features/messages` | 最终 168 项全部通过，包含消息布局另一子会话的通知改动与既有消息测试 |
| 定向 `dart analyze` | `messages_screen.dart`、`message_center_views.dart` 和新增测试均无问题 |
| 格式与差异 | 本任务 Dart 文件格式检查及 `git diff --check` 通过 |
| 调试实例发现 | DTD 工具未发现运行中的 DTD/Flutter 调试进程，未执行热重载 |

消息性能回归仍通过，未读、发送中、已读标记变化保持已有列表与消息正文零重建断言。根应用和四包的全量检查由汇总会话统一执行，其结果在汇总记录中登记。

本轮测试使用虚构账号、消息和助手列表，没有读取真实私信或执行真实账号发送、举报、设置、拉黑操作；没有构建、安装或进行 Android/Windows/macOS 实机验收。线上助手内容与实际交互仍需用户构建后确认。
