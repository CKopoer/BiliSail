# 联合投稿视频动态去重（#67）

日期：2026-11-05。对应 [issue #67](https://github.com/CKopoer/BiliSail/issues/67)。

## 协议与 PiliPlus 对照

只读核对相邻 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/http/dynamics.dart`、`lib/http/api.dart`、`lib/common/constants.dart`、`lib/models/dynamics/result.dart`、`lib/pages/dynamics_tab/controller.dart` 和 `lib/pages/common/common_list_controller.dart`。

| 项目 | BiliSail | PiliPlus |
| --- | --- | --- |
| 端点 | `GET https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all` | 相同 |
| 视频筛选与分页 | `type=video`、`offset`，另传 `page` | `type=video`、`offset` |
| features | `itemOpusStyle` | 包含 `itemOpusStyle`、`cardsEnhance`、`eva3CardVideo` 等的完整列表 |
| 联合投稿去重 | 修复前按 `(kind, 动态 ID)` 合并 | 所查路径直接接纳列表、分页追加，未见按 BVID 合并的专用逻辑 |

两者没有使用不同的 Web/App 动态端点。features 确有差异，但未做真实账号的在线 A/B，不能据此断言某个 feature 会让服务端自动去重，也不将 PiliPlus 线上一定不重复当作已证实行为。本轮不扩大请求参数或更换接口。

[Bilibili 联合投稿说明](https://www.bilibili.com/blackboard/activity-hezuogongyue.html)说明合作稿件会出现在创作成员的视频动态中。同一视频可以对应不同作者的动态 ID，而本项目原合并键没有使用 BVID，因而无法合并此类条目。离线回归以不同动态 ID、同一 BVID 的响应模型复现此问题。

只参考协议字段和职责，独立实现应用层合并；未复制 PiliPlus GPLv3 应用源码、资源或 schema，未修改相邻仓库、引入依赖或改变既有许可范围。

## 合并规则与边界

- 首页“视频动态”和“动态·视频”对合法 BVID 的直接视频卡按 BVID 合并，跨分页沿用同一规则。完整动态仍保留原动态 ID，不用视频 ID 替换点赞、分享等操作身份。
- 已返回记录中，`module_author.pub_action`（现有 `DynamicPost.actionText`）明确为“投稿了视频”的记录优先；主投稿记录后到时只替换原位置的整条记录，作者、头像、动态和互动身份一起切换。只选当前关注流已经返回的记录，不额外查询或构造未关注作者的动态。
- 多个合作成员之间保留服务器顺序最先出现的一条。动作字段缺失或未知时不猜测主投身份；同一动态 ID 的重复响应仍允许更新元数据。主投没有返回时继续保留现有合作成员，刷新清空本轮选择。
- “动态·全部”、图文、空间动态、收藏及转发附言不按视频合并；空或非法 BVID 回退到动态 ID。两个视频的标题、封面相同也不视为同一内容。
- 保留 200 条上限、游标前进校验、连续无新增页的有限扫描、取消和账号隔离；重复投稿不消耗额外卡片名额，达到容量时仍允许同页主投稿替换已有代表。

## 验证

- 新增控制器行为测试先在原实现复现重复，再验证同页两种先后顺序、跨页替换、合作成员稳定顺序、同动态更新、刷新、不同 BVID、转发／其他列表隔离及容量边界。
- API 与共享映射测试验证现有发布动作字段完整传到应用模型，不新增协议解析或网络调用。
- 共享工作区有同期其他任务修改，首次全量检查遇到其格式／接口编译错误，未修改这些文件；随后在基于 `7b4ff030ccb9558ac26019d1fc99c964c53079eb`、只应用本任务变更的独立 worktree 执行 `tool/check.ps1 -EnforceLockfile`，退出码 0。五份锁文件解析、打包边界、格式和静态分析通过。
- 共享目录追加定向验证在启动前因 `build/native_assets/windows/sqlite3.dll` 被占用而中断；未终止其他任务或用户进程，也未将此运行计为测试通过。提交前校验四份代码／测试文件与独立验证快照完全一致。
- 独立验证中根应用 4,121 项、`bili_api` 586 项、`bili_player` 148 项、`bili_danmaku` 161 项、`bili_mux` 5 项通过。根应用另有 13 项因 Windows 符号链接权限跳过；mux 原生 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不作为原生集成通过。
- Windows Debug 使用不读取账号的模拟页面构建并启动成功：四条记录合并为两个不同 BVID 的视频，第一条为主投作者；热重载成功，运行时错误检查为空。该验证只覆盖实际控制器的模拟运行，不代替真实关注流或正式应用完整 UI 验收。
- 本轮不涉及原生播放或性能调整；真实关注账号的联合投稿列表及 Android/macOS 实机尚未验收。日志保留在本机忽略目录 `artifacts/issue67-check.log`、`artifacts/issue67-runtime.log`。
