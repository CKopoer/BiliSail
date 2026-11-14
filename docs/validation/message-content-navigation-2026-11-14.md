# 消息内容与评论定位

日期：2026-11-14。

## 参考与范围

只读参考本机 PiliPlus `217fb54f51f6764176319bbdedab2a7522d75401` 的 `lib/pages/msg_feed_top/{reply_me,like_me,at_me}/view.dart`、`lib/utils/app_scheme.dart`、`lib/utils/reply_scheme_helper.dart`、`lib/http/reply.dart` 和 `lib/pages/video/reply_reply/controller.dart`。借鉴消息点击打开原内容、根评论／二级评论地址、分 P 与播放时间的职责；独立实现 Dart／Riverpod／工作区导航，没有复制 GPLv3 应用代码、生成 schema 或资源，没有修改参考仓库或新增依赖。

本轮覆盖视频与影视的回复、收到的赞、@ 通知及消息中的已有内容链接。动态、专栏与其他不支持的工作区内容沿用原有外链行为。PiliPlus 使用 `lib/grpc/reply.dart` 的 `DetailList(root, rpid)` 直接定位；本项目采用 Web 按评论 ID 跳转接口实现相同行为，继续使用现有 Cookie 会话，没有迁入 App gRPC 或假定存在 App token。

Web `/x/v2/reply/jump` 的 `oid/type/rpid` 另只读核对 [XiaoMiku01/check-awl](https://github.com/XiaoMiku01/check-awl) 的 0.1.6 脚本（MIT）所登记端点，并直接访问 Bilibili 官方 API 验证响应。只借鉴端点／字段，独立实现，不复制脚本源码、不采用其删除评论行为。

## 行为与边界

- 点击通知正文或「查看原内容」打开对应内容；「回复」仍使用独立发送弹窗。
- 优先解析有效 `native_uri`，失效时回退 `uri`；AV 转 BV 保留 query／fragment，支持视频、影视、折叠评论通知及视频 H5 评论链接。进入工作区只传递经过校验的 CID、分 P、根／二级评论和播放时间。
- 评论地址使用 `comment_root_id/comment_secondary_id`，必要时从通知 `root_id/source_id` 补齐；通知行 ID 和旧 `target_id` 不作为回复通知的目标。弹幕通知不会被误当作评论。
- 自动展开信息区并选择评论页，按根 ID 读取楼层，按二级 ID 查找并突出显示目标回复。目标回复置于详情顶部，保留原评论和后续分页；返回恢复主评论列表。同一内容再次点击定位通知使用新的导航请求身份，普通设置更新不重放定位。
- 先调用 `GET https://api.bilibili.com/x/v2/reply/jump?oid=…&type=…&rpid=…`，按 ID 取得根评论及目标的 `page.rt_num`；再直接读取 `/x/v2/reply/reply` 的目标页。正常成功为两次逻辑读取，不扫描中间页，不设 25 页／500 条定位限制。已有共享列表最多保留 500 条显示记录的容量策略继续生效，目标位于该范围之外也可直接打开。
- Web jump 的 `rt_num` 使用每页 10 条楼中楼，响应 `page.size` 则描述主评论页，不能据此换算。现有共享回复每页 20 条，因此读取 `(rt_num - 1) ~/ 2 + 1` 页；后续分页沿用该 20 条页码，避免跳页或重复目标请求。根评论定位直接读取回复首页。
- 两个端点均为 Web Cookie 可选的只读 GET，无需 WBI／CSRF，沿用客户端的有界重试和同一取消／deadline。定位总期限仍为 15 秒。找不到目标、删除或不可见时给出提示，不扫描兜底、不伪造评论；核对根评论的 oid／type 及目标回复的 root，拒绝错主体／错楼层。
- 账号／epoch／请求代次、取消和释放隔离迟到响应；刷新和新的定位会取消旧定位。无需数据库迁移。
- `start_progress` 按毫秒，`t` 按秒，`dm_progress` 按毫秒提前 3 秒（最低为零）。显式位置优先于续播；已打开的同源会话直接 seek，保留手动暂停意图和原 surface，不增加播放器实例。切换分 P 后不重放旧时间。

## 验证

本轮增加协议、Repository、控制器和 Widget 回归，覆盖精确 ID、折叠／H5／影视链接、分 P／CID／时间、安全参数、通知点击、直接读取远端页、删除、账号变化、刷新和连续定位竞态、长根评论、重复请求、暂停意图与单 surface。

下表保留 `71ec0b6d` 首轮消息导航的检查结果，基线为 `56df571a` 加当时 25 个文件的隔离检出，完整 `tool/check.ps1 -SkipPub` 退出码为 0。根应用和四包先离线解析依赖，没有更新锁文件。结果对应该快照，不将其描述为同期修改或本次按 ID 定位的验证结论。

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

## 按评论 ID 直接定位的补充验证

2026-11-14 按用户要求移除逐页查找。新增 24 项 API 回归及更新后的 8 项评论定位回归均通过，覆盖大整数 ID、奇偶页边界、第 50002 个回复页、根评论、缺失／错误页码、主体和根身份、删除／不可见、两次读取共享期限及取消／账号竞态。找不到目标时断言不再扫描其他页。

使用无凭据、只读的官方 API 验证公开视频 `av170001`：根评论 `669376635` 共 571 条回复，目标 `309991906049` 返回 `rt_num=58`，直接读取每页 20 条的第 29 页确认包含目标。随后使用本次 Dart API 方法再次读取同一目标，结果一致。该证据只说明本次游客公开样本成功，不代表所有账号／类型／平台均已实测。元信息存于忽略目录 `build/validation/comment-id-navigation-2026-11-14/` 的 `public-probe.json` 和 `api-public-probe.json`，不保存评论正文或凭据。

本次在 `d341ef79` 加本次 6 个文件的隔离检出中，离线解析依赖后，分阶段执行根 `tool/check.ps1 -SkipPub -Stage Lint / RootTests / PackageTests`，三个阶段均退出 0；锁文件未变化。结果不包含主工作区仍在修改的推荐等同期内容。

| 本次检查 | 结果 |
| --- | --- |
| 根应用测试 | 5524 通过，13 项按现有条件跳过 |
| bili_api | 972 通过 |
| bili_player | 318 通过，3 项按现有条件跳过 |
| bili_danmaku | 161 通过 |
| bili_mux | 5 通过；10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过 |
| 格式、静态分析、打包边界脚本 | 全部通过 |

日志为上述忽略目录中的 `check-Lint.log`、`check-RootTests.log`、`check-PackageTests.log`。本轮 `git diff --check` 及文档链接核对通过。仍不构建、不安装、不执行真实账号写操作；未发现可热重载的调试应用，平台实机验收留给用户后续完成。
