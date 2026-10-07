# 用户主页

日期：2026-10-05。参考本机哔哩哔哩 UWP 4.8.18.0 的个人中心、关注列表和 UP 主空间，以及相邻仓库的 `UserDetailAPI.cs`、`UserInfoPage.xaml`、`UserDetailViewModel.cs`。只借鉴协议字段与交互职责，自行编写 Dart/Flutter；没有复制新的代码或视觉资源，没有修改相邻仓库。

## 页面与入口

自己与其他用户共用 `/user/:mid` 用户空间；从已登录账号弹窗的个人主页入口、视频 UP 主头像/姓名、评论作者头像/姓名进入。根评论、楼中楼及回复预览保留用户身份。没有合法 MID 的作者不按昵称猜测身份。

主页提供资料、投稿视频、动态、收藏夹、关注、粉丝；投稿支持最新发布、最多播放、最多收藏和关键词搜索，收藏夹可继续打开其中视频，关注/粉丝可打开另一个用户空间。专栏、独立合集管理、私信与空间编辑不在本次实现范围。隐私、风控和登录要求遵守 Web 端点响应。

用户 ID 以字符串值类型传递。空间打开独立工作区标签，同一 UID 复用标签，关闭才释放请求；切离视频沿用现有单播放器的暂停和恢复规则。每个标签有独立控制器，账号变化释放旧页面请求，刷新、排序、搜索和分页使用代次隔离。

## 接口与生命周期

`ProfileClient` 使用 `BiliApiClient` 的 HTTPS、Cookie、取消、会话 epoch、超时和有限重试流程；投稿复用单飞 WBI 签名。`ApiProfileRepository` 映射协议模型，界面只消费领域状态与应用控制器。资料加载与内容列表分开失败，列表分页去重且限制容量。

| 内容 | Web GET 端点 | 身份与签名 | 分页 |
| --- | --- | --- | --- |
| 公开资料 | `api.bilibili.com/x/web-interface/card` | 可携当前 Web Cookie，无 WBI | 无 |
| 视频投稿 | `api.bilibili.com/x/space/wbi/arc/search` | 当前 Web Cookie、WBI；权限以服务端为准 | `pn` / `ps`，`order` / `keyword` |
| 空间动态 | `api.bilibili.com/x/polymer/web-dynamic/v1/feed/space` | 当前 Web Cookie，无 WBI | 原样传递 `offset` 游标 |
| 创建的收藏夹 | `api.bilibili.com/x/v3/fav/folder/created/list` | 当前 Web Cookie，无 WBI | `pn` / `ps` |
| 夹内视频 | `api.bilibili.com/x/v3/fav/resource/list` | 当前 Web Cookie，无 WBI | `pn` / `ps` |
| 关系列表隐私 | `api.bilibili.com/x/space/setting` | 游客可读、可携当前 Web Cookie，无 WBI；参数 `mid` | 无 |
| 关注、粉丝 | `api.bilibili.com/x/relation/followings`、`/x/relation/followers` | 当前 Web Cookie，无 WBI | `pn` / `ps` |

响应均为 JSON；使用既有单层读重试与每次操作 25 秒 deadline，不在 feature 再套重试循环。被服务端拒绝时保留明确失败，不改走 App token 或其他身份通道。不新增账户写操作，不读取或复制 UWP 的凭据。

## 验证

环境：Windows x64、Flutter 3.47.6、Dart 3.13.5，沿用既有锁定依赖，没有新增第三方依赖。

- `tool/check.ps1` 通过：根应用 188 项、`bili_api` 65 项、`bili_player` 16 项、`bili_danmaku` 5 项测试；根与三个包的格式和静态分析均通过。根分析排除已被 Git 忽略的 `artifacts/` 构建快照，避免将历史源码副本当作当前应用分析。
- 新增验证涵盖：超大字符串 UID、整数/字符串作者 MID、缺失身份不导航、WBI 参数只编码一次、动态游标不前进、失效收藏、取消/错误分类、资料与列表分别失败、刷新/筛选/账号切换后的迟到响应、关闭标签取消请求、分页去重与 500 条上限。布局覆盖宽屏多列、375 宽窗口及文字放大。
- `flutter build windows --release` 通过，运行目录为 `build/windows/x64/runner/Release/`。本轮没有更改原生播放器实现，未重复原生媒体受控测试。
- `packages/bili_api/tool/profile_smoke.dart` 以游客对公开样本 `mid=2` 低频只读验证：资料成功、收藏夹空列表成功；投稿与动态 HTTP 412、关注业务码 -101（需要登录）、粉丝业务码 -352（风控）。没有提取凭据或更换身份绕过限制，游客受限项不能记为成功。
- Windows 发布版使用应用已有登录会话，实际从账号弹窗进入自己的主页，显示资料、投稿、动态、收藏夹及夹内视频、关注、粉丝。通过关注列表进入 UP 主主页，非空投稿成功；打开投稿视频后点击 UP 主头像复用原主页标签，返回视频继续显示原播放页。点击根评论头像进入对应评论用户主页，投稿列表“加载更多”成功追加下一页。

线上读取仅代表本次已有会话和少量样本；其他账号/隐私设置、游客受限接口的成功读取、所有排序/关键词组合、动态与关系列表的完整翻页尚未逐项线上验收。楼中楼/预览用户名入口通过 widget 测试，本轮未单独做原生界面点击。Android/macOS 构建和设备运行未测；没有执行关注、点赞、投币、发送、收藏修改或任何账户写入。没有将本机账号资料、Cookie 或令牌保存为 fixture。

## 2026-10-07：投稿工具条与未公开关系列表

投稿排序和搜索保持同一行：排序按文字自然宽度布局，搜索在右侧使用剩余宽度、最大 260 逻辑像素；窗口缩窄或文字放大时搜索收缩，不再按固定 560 宽阈值拆行。

查看其他用户的关注/粉丝时，先读取空间设置的 `privacy.disable_following` / `privacy.disable_show_fans`；`1` 分别表示关闭展示对应列表。确认隐藏后返回独立领域状态，显示“该用户未公开关注列表”或“该用户未公开粉丝列表”，清除此前分页内容、停止分页，不展示网络错误和重试按钮。页面刷新可重新读取最新隐私设置。当前账号查看自己的列表直接沿用原关系端点，与官网的 owner 判断一致。隐私字段缺失或格式异常仍为协议失败，公开列表的登录、风控及其他真实失败继续保留；两步读取共用取消、session epoch 和 25 秒 deadline。

协议依据为本次官网空间的 [主脚本](https://s1.hdslb.com/bfs/static/shanks/fresh-space/assets/index-77e2048f.js)、[关注页](https://s1.hdslb.com/bfs/static/shanks/fresh-space/assets/Follow-090ef5fa.js) 和 [粉丝页](https://s1.hdslb.com/bfs/static/shanks/fresh-space/assets/Fans-435f578b.js) 的隐私字段与 owner 判断；只借鉴协议语义，自行实现 Dart/Flutter，没有复制代码或资源。测试 UID `3546913901120156` 的游客只读设置返回两个隐藏标志均为 `1`；直接关系端点在游客下分别返回 `-101` 和 `-352`，因此不以这些限制码猜测隐私或声称读取了隐藏列表。

- 用户主页 47 项回归通过，覆盖 320/375/500 宽及两倍文字下的单行布局、搜索与排序操作、两个隐私标志独立映射、owner/空列表/真实失败区分、隐藏后清空旧分页与停止加载、刷新恢复公开内容，以及取消/账号变更/迟到响应隔离。
- `tool/check.ps1 -SkipPub` 通过：根应用 1158、`bili_api` 307、`bili_player` 22、`bili_danmaku` 52，共 1539 项；四处格式和静态分析均通过。日志为 `artifacts/profile-relations-check.log`；复用锁定依赖，没有新增依赖。
- 新 Dart 解析器游客只读烟测确认测试 UID 的两个隐藏标志均为 `true`，日志为 `artifacts/profile-relations-smoke.log`。本轮未使用真实登录账号读取公开关系列表，也未执行账户写入。
- `flutter build windows --release --no-pub -t lib/main.dart` 通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `artifacts/profile-relations-build-windows.log`。本次改动只涉及用户主页，未重复原生播放测试。
- 文档相对链接和本次差异空白检查通过。本轮桌面原生界面的窗口拖动/输入交互未实测，Android/macOS 构建未执行、设备运行未实测；不能由 widget 布局回归推导为设备验收通过。
