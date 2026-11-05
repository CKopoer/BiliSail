# 消息通知页标题与系统通知布局修复

日期：2026-11-05。

## 参考与采用范围

只读参考相邻 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/pages/whisper/controller.dart`、`lib/pages/msg_feed_top/reply_me/view.dart` 和 `lib/pages/msg_feed_top/sys_msg/view.dart`：通知分类有自己的标题与返回入口，系统通知以标题、正文和时间呈现，不设置用户头像。本轮仅借鉴交互和信息排列，独立实现 Flutter 组件修改；没有复制 GPLv3 应用源码、资源或 schema，没有修改相邻仓库或增加依赖。

## 修改

- 消息页可用宽度小于 600px 时，进入回复我的、@我的、收到的赞和系统通知后，隐藏外层“我的消息”、新增粉丝、一键已读和更多操作。分类自己的标题与“返回消息首页”继续显示，页内返回和系统返回仍复用原控制器与 `PageBackHandler`。
- 返回私信首页后恢复外层标题与操作；调整到宽屏时恢复外层工具栏与分类导航，保留当前分类及已有页面状态。
- 系统通知移除左侧头像、头像间距和分隔线缩进，正文利用原头像列的宽度。互动通知继续保留作者头像、点击入口和原有缩进。原内容链接、正文、时间、已读与分页逻辑沿用原实现。

源码入口为 `lib/features/messages/presentation/messages_screen.dart`；新增回归为 `test/features/messages/message_notification_layout_test.dart`。

## 验证

| 检查 | 结果 |
| --- | --- |
| `flutter test --no-pub test/features/messages/message_notification_layout_test.dart test/features/messages/messages_header_test.dart test/features/messages/messages_redesign_test.dart test/features/messages/messages_screen_test.dart` | 54 项通过 |
| 新增 Widget 回归 | 5 项通过：320/390px 两倍字号下四类通知隐藏首页工具栏、返回恢复及宽窄切换保留分类；390/1200px 系统通知无头像且标题靠左、分隔线及原内容链接；互动通知保留作者头像与缩进 |
| `dart analyze lib/features/messages/presentation/messages_screen.dart test/features/messages/message_notification_layout_test.dart` | 无问题 |
| 新测试 `dart format`、`git diff --check` | 通过 |

根应用与四包的全量检查由汇总会话执行，结果以汇总记录为准。本轮仅做离线 Widget 回归，没有访问真实账号或执行真实账户写请求。按用户要求不构建、不安装；Windows、Android、macOS 的实际布局与触控/鼠标体验由用户后续构建实机确认。
