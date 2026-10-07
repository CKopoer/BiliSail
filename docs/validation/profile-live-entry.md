# UP 主空间直播间入口

日期：2026-10-07。

用户空间的资料下方操作区显示直播间按钮，顺序为关注、直播间、私信；自己主页仅显示有效的直播间入口。已开播显示“正在直播”；已开通房间但未开播（包括轮播状态）显示“直播间”，仍允许查看房间。确认没有开通直播间时隐藏入口。按钮沿用 Material 3 组件和自适应换行，点击通过现有 `/live/:roomId` 工作区路由打开房间；再次进入相同房间复用工作区状态，原用户空间也保留。

## 协议与生命周期

现有 `/x/web-interface/card` 公开资料响应没有直播间字段，因此新增独立读取，不阻塞用户资料或投稿列表，也不由界面发起 HTTP 请求。

| 项目 | 契约 |
| --- | --- |
| Profile / host / method | Web；`api.live.bilibili.com`；GET |
| Path / 参数 | `/room/v1/Room/getRoomInfoOld`；原样 decimal UID 参数 `mid` |
| 鉴权与签名 | 沿用当前 Web 会话，可游客读取；无 WBI / CSRF / App token |
| 响应与分页 | JSON `data`；无分页 |
| 字段 | `roomStatus=0` 表示无房间；`roomStatus=1` 时读取 `roomid` 和 `liveStatus`；`liveStatus=1` 为正在直播，`0` 为未开播，轮播不会显示成正在直播 |
| 重试 / deadline | 沿用 `BiliApiClient` 的单层有限读重试和 `ApiRequests` 每次操作 25 秒 deadline，不增加 feature 重试循环 |

整数或 decimal 字符串房间号进入现有 `RoomId` 值类型；不经过浮点转换，不从 URL 或昵称猜测房间。缺失/非法状态和房间号保留协议失败，不解释为“没有直播间”。查询失败只显示独立直播间错误和重试入口，不清除已经加载的用户资料或列表。

`ProfileController` 的直播查询有独立取消与代次；刷新重新查询，账号 scope / session epoch 变化和关闭空间取消旧请求，迟到响应不能恢复旧房间。成功无房间响应会清除之前的入口。

## 参考来源

只读查看相邻 `biliuwp-lite` 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [UserInfoPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/UserInfoPage.xaml)、[UserInfoPage.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/Pages/UserInfoPage.xaml.cs)、[UserDetailViewModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/User/UserDetailViewModel.cs) 和 [LiveRoomAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/Live/LiveRoomAPI.cs)。借鉴有房间时显示入口、开播文案、按房间号导航的交互职责，以及 UID 查询直播间的 Web 端点；独立实现 Dart / Flutter，没有复制新的上游源码、schema 或资源，没有修改相邻仓库，采用边界沿用 [参考文档](../references.md)。

## 验证

- `flutter test --no-pub test/features/profile`：57 项通过。新增覆盖房间模型映射、真实失败与无房间区分、账号变更取消、独立查询失败、刷新取消/迟到响应、关闭空间取消、无效/无房间隐藏、开播/未开播按钮，以及带按钮的 320 / 375 / 900 宽、1 / 2 倍文字布局。
- `flutter test --no-pub test/app/workspace_router_test.dart --plain-name "profile live entry"`：2 项通过，覆盖 Windows 默认平台下单页和多标签两种导航模式，实际点击入口、房间号传递、返回保留用户空间、重复打开复用房间作用域。
- `dart test test/profile_client_test.dart`（`packages/bili_api`）：24 项通过，包含 integer / 超大 decimal 字符串 ID、有房间与未播/轮播/正在直播、无房间、缺失/非法字段。
- 根应用本次文件及 API 本次文件静态分析通过；格式检查和 `git diff --check` 通过。全仓集成检查由本轮四个直播问题统一执行，结果登记在汇总记录。
- 本机游客、低频只读查询 `mid=2` 和 `672328094` 成功：公开资料接口没有直播间字段，直播查询分别返回房间 `1024` / `22637261`；两者当时 `liveStatus=0`，后者 `roundStatus=1`。另只读样本 `1` / `322892` 的直播查询也成功，均为未开播。仅核对公开字段，没有读取或保存凭据，没有账户写入。

线上样本只覆盖本次游客查询的有房间/未开播及轮播；无房间、正在直播和错误响应使用脱敏 fake 验证。未进行 Windows 原生界面点击、Android / macOS 构建或设备运行；工作区与布局 widget 回归不能替代设备验收。本次未改变原生播放器。

### 2026-10-07：直播间按钮位置调整

直播间入口移至关注与私信按钮之间，三者共用自适应换行的操作区。`tool/check.ps1 -SkipPub` 通过：根应用 1286、`bili_api` 319、`bili_player` 32、`bili_danmaku` 52，共 1689 项测试，四处格式检查和静态分析通过；日志为 `artifacts/profile-live-button-check.log`。本轮按用户要求不执行构建，实机布局与交互由用户后续验收。
