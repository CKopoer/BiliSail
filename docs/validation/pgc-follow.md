# 番剧、国创与放映厅追番

日期：2026-11-12。

## 范围与来源

在共用 PGC 播放页的简介区增加追番／取消追番。番剧、国创显示“追番／已追番”，电影、电视剧、纪录片、综艺显示“追剧／已追剧”；已追按钮的提示为“取消追番／取消追剧”。按钮复用应用 ColorScheme、圆角和紧凑操作样式，适配明暗主题、窄窗和大字号。游客点击打开既有账号登录弹窗；操作不重建播放器或改变当前选集。

只读参考 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus/tree/cab0114a21ce7fad5b90b9a4d788d35d313d25f9)，核对 `lib/http/api.dart`、`lib/http/video.dart` 的 `pgcAdd`／`pgcDel`，以及 `lib/http/pgc.dart` 的 `seasonStatus`，并核对该提交的 `pubspec.yaml`／`pubspec.lock`。仅采用端点、请求参数和响应字段，自行实现本项目分层、状态和 UI，未复制其 GPLv3 应用源码或资源，未引入依赖。

## 协议与状态

| Profile | Host／方法／路径 | 鉴权与字段 | 响应／重试 |
| --- | --- | --- | --- |
| Web Cookie | `api.bilibili.com` GET `/pgc/view/web/season/user/status` | 已登录账号，`season_id` 为十进制字符串，无 WBI／App 签名 | JSON `result.follow`，接受明确的布尔或 0／1；缺失或非法值报协议错误，不当作未追番。无分页，沿用公共有界读重试 |
| Web Cookie／CSRF | 同 host POST `/pgc/web/follow/add`、`/pgc/web/follow/del` | 表单 `season_id`，公共提交管线加入 Cookie 和 `csrf` | JSON 业务 `code=0` 才确认成功，单次发送，不重试写入 |

`ApiRequests` 提供取消与 25 秒总 deadline，底层 HTTP 保留自身超时。Repository 检查账号 scope／session epoch，控制器额外隔离请求代次和状态读取所属账号。控制器按实际详情返回的季编号共享，season 和 episode 入口操作同一作品，不将集编号当作季编号。

首次状态加载和提交期间禁用按钮。明确失败保留原状态并显示错误；网络、超时、HTTP 或协议异常导致写入结果不明时，显示“刷新状态”，完成读取前禁止再次写入。登出、账号切换或页面释放取消旧请求，迟到结果不能覆盖新状态。刷新影视详情同时刷新追番状态，不取消正在提交的写入。

## 验证

测试覆盖协议字段、长季编号、CSRF／Cookie、非法状态、单次写入、账号与取消隔离、重复点击、失败及结果不明后的核对，另覆盖六类作品文案、登录入口、窄窗大字号与明暗主题。episode 入口的页面测试确认操作使用实际季编号且不重建播放器。

Flutter 3.47.6／Dart 3.13.5 下的检查：

- 相关根应用回归 82 项通过，接口专项 19 项通过；补齐现有已登录评论导航夹具的追番仓储注入后，评论导航与 PGC 页面 40 项复验通过，覆盖详情刷新重新读取追番状态。
- `1f5b314a` 基线上最终根应用全量测试 `flutter test --no-pub --concurrency 6`：5224 项通过，6 项按既有平台条件跳过。
- 合入远端 `7488f8af` 收藏管理改动后，PGC、收藏、评论导航与播放评论滚动集成回归 190 项通过，接口包全套 911 项通过；重新检查全仓格式与静态分析通过。
- 四个独立包全套测试通过：`bili_api` 911、`bili_player` 398、`bili_danmaku` 161、`bili_mux` 5；mux 另有 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生通过。
- 根应用、四个包及 Linux 本地适配器的格式和静态分析通过，五份锁文件严格解析通过，未变更依赖或锁文件。
- `tool/check.ps1 -EnforceLockfile` 在既有 `tool/test-macos-release-validation.ps1:320` 中断：本轮 Linux 容器未通过“独立父进程终止挂起 worker 及其子进程”的断言。保留该脚本，后续打包边界脚本、Python 测试、格式与分析按原命令补跑通过；不宣称完整检查脚本一次通过。

本轮只使用离线 fake transport／repository，没有使用真实账号执行追番写入，未进行 Android／Windows／macOS 实机验收。
