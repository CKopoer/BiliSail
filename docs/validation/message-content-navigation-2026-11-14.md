# 消息内容与评论定位

日期：2026-11-14。

## 参考与范围

只读参考本机 PiliPlus `217fb54f51f6764176319bbdedab2a7522d75401` 的 `lib/pages/msg_feed_top/{reply_me,like_me,at_me}/view.dart`、`lib/utils/app_scheme.dart`、`lib/utils/reply_scheme_helper.dart`、`lib/http/reply.dart` 和 `lib/pages/video/reply_reply/controller.dart`。借鉴消息点击打开原内容、根评论／二级评论地址、分 P 与播放时间的职责；独立实现 Dart／Riverpod／工作区导航，没有复制 GPLv3 应用代码、生成 schema 或资源，没有修改参考仓库或新增依赖。

本轮覆盖视频与影视的回复、收到的赞、@ 通知及消息中的已有内容链接。动态、专栏与其他不支持的工作区内容沿用原有外链行为。PiliPlus 的 App gRPC 评论详情读取不迁入本项目，继续使用现有 Web Cookie 评论接口。

## 行为与边界

- 点击通知正文或「查看原内容」打开对应内容；「回复」仍使用独立发送弹窗。
- 优先解析有效 `native_uri`，失效时回退 `uri`；AV 转 BV 保留 query／fragment，支持视频、影视、折叠评论通知及视频 H5 评论链接。进入工作区只传递经过校验的 CID、分 P、根／二级评论和播放时间。
- 评论地址使用 `comment_root_id/comment_secondary_id`，必要时从通知 `root_id/source_id` 补齐；通知行 ID 和旧 `target_id` 不作为回复通知的目标。弹幕通知不会被误当作评论。
- 自动展开信息区并选择评论页，按根 ID 读取楼层，按二级 ID 查找并突出显示目标回复。目标回复置于详情顶部，保留原评论和后续分页；返回恢复主评论列表。同一内容再次点击定位通知使用新的导航请求身份，普通设置更新不重放定位。
- 复用 `GET https://api.bilibili.com/x/v2/reply/reply` 的 `oid/type/root/pn/ps` 和 `root` 响应，Web Cookie 可选、无需 WBI／CSRF；只读请求沿用客户端的有界重试。单次定位总期限 15 秒，二级回复最多查找 25 页／500 条，保持现有共享评论容量边界。未找到、删除、不可见或超范围时给出提示，不伪造已找到的评论。
- 账号／epoch／请求代次、取消和释放隔离迟到响应；刷新和新的定位会取消旧定位。无需数据库迁移。
- `start_progress` 按毫秒，`t` 按秒，`dm_progress` 按毫秒提前 3 秒（最低为零）。显式位置优先于续播；已打开的同源会话直接 seek，保留手动暂停意图和原 surface，不增加播放器实例。切换分 P 后不重放旧时间。

## 验证

本轮增加协议、Repository、控制器和 Widget 回归，覆盖精确 ID、折叠／H5／影视链接、分 P／CID／时间、安全参数、通知点击、跨页查找上限、删除、账号变化、刷新和连续定位竞态、长根评论、重复请求、暂停意图与单 surface。

主工作区存在同期推荐、登录及媒体调查改动，部分文件处于修改中；本轮使用 `56df571a` 加本次 25 个文件的隔离检出执行完整 `tool/check.ps1 -SkipPub`，退出码为 0。根应用和四包先离线解析依赖，没有更新锁文件。结果对应隔离快照，不将其描述为同期修改的验证结论。

| 检查 | 结果 |
| --- | --- |
| 根应用测试 | 5510 通过，13 项按现有条件跳过 |
| bili_api | 946 通过 |
| bili_player | 312 通过，3 项按现有条件跳过 |
| bili_danmaku | 161 通过 |
| bili_mux | 5 通过；未配置 `BILI_MUX_LIBRARY`，10 项原生用例跳过，不计为原生集成通过 |
| 格式、静态分析、打包边界脚本 | 完整检查通过；最后新增的回归补跑格式及根静态分析，无问题 |
| 定位交互 | 视频／影视无需手动选择评论页；长根评论前的目标回复可见；重复请求重新定位，普通重建不重放；暂停与同一 surface 保留，均有 Widget 回归 |
| 差异和文档 | 本轮新增链接、源码入口及 `git diff --check` 通过 |

日志保存在主工作区忽略目录 `build/validation/message-navigation-2026-11-14/`：`check-isolated.log`、`analyze-isolated-final.log`、`isolated-smoke.log` 和 `screen-targeted.log`。

按用户范围不构建、不安装、不执行真实账号写操作；Windows／Android／Apple 实机点击与在线账号消息验收由用户后续完成。DTD 未发现运行中的调试应用，无法热重载。离线 fixture 通过不代表在线服务已验收。
