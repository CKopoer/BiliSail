# 关注分组

## 查看关注分组（2026-11-06）

查看自己的关注列表时，关注栏目下显示“全部关注”、默认分组及服务端返回的自定义／特殊分组。分组栏复用 `ContentSectionTabs`，与应用已有内容子标签的字体、选中颜色、悬停及横向滚轮行为一致，并随栏目导航固定在顶部。查看其他用户时仍使用其公开关注列表，不读取当前账号的私有分组；粉丝列表保持原有行为。

点击分组后从第一页加载该分组成员，切换分组取消旧请求并以查询代次隔离迟到结果；切到其他栏目再返回保留当前分组和已加载列表。账号变化／页面关闭取消分组目录与成员读取。目录失败时仍可使用全部关注并显式重试，刷新后当前分组已不存在则回到全部关注。目录最多接收 100 个服务端分组，列表沿用主页 500 条上限及连续空页停止规则，不落盘私有分组。

| 能力 | Host / 方法 / Path | 会话、响应与重试 |
| --- | --- | --- |
| 分组目录 | `api.bilibili.com` GET `/x/relation/tags` | 当前账号 Web Cookie，JSON `data` 数组；浏览保留负数特殊分组，设置分组菜单仍过滤它们；缺失 `0` 时补默认分组 |
| 分组成员 | `api.bilibili.com` GET `/x/relation/tag?mid={当前账号mid}&tagid={分组id}&pn={page}&ps=30` | 当前账号 Web Cookie，JSON `data` 数组，`null`／空数组为空组；无总数，满页继续、短页停止；ID 保留十进制字符串 |

两项读取使用既有 `ApiRequests` scope／epoch、取消、25 秒总 deadline 和最多额外两次只读重试。分组成员复用公开关注列表的用户映射；格式错误保持协议错误，不伪装为空组。没有增加关注或分组写操作。

只读参考 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/pages/follow/controller.dart`、`lib/pages/follow/view.dart`、`lib/pages/follow/child/child_controller.dart`、`lib/http/member.dart`、`lib/http/api.dart` 和 `lib/models/member/tags.dart`。仅借鉴自己的关注显示分组、全部／分组的协议分流和数组分页语义；Flutter 界面及状态逻辑独立编写，未复制 GPLv3 应用源码／资源，未修改相邻仓库或引入依赖。

离线回归覆盖默认／特殊分组、精确 ID、数组分页及坏响应，仓储的本人／访客权限，快速切换、刷新删组、账号与关闭取消、目录失败重试和空组，以及 320 像素／2 倍字体与 900 像素下共享 Tab 滚动选择。真实账号在线接口及 Android／macOS 设备操作仍待验收；离线 fixture 不代表在线接口已经验证。

### 本轮验证结果

- 仅包含本次代码改动、基于 `f49c692` 的独立检出运行 `tool/check.ps1 -EnforceLockfile` 全部通过：根应用 4,380 项、`bili_api` 659 项、`bili_player` 148 项、`bili_danmaku` 161 项、`bili_mux` 5 项，共 5,353 项通过。五份锁文件复现解析、格式、静态分析及打包边界检查均通过。
- 跳过 23 项：13 项需要 Windows 符号链接权限，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过；不算作原生封装覆盖。
- 共享工作区的主页／关注及作者控制器定向回归 266 项通过，四包测试和 Lint 阶段通过。首次共享根应用全量运行有两项同期设置测试失败：`default_dynamic_tab_test.dart:78` 的字段数预期 37、实际 38，以及 `settings_screen_test.dart` 的播放器内清晰度选项不可见。未改动这些设置／播放器文件来完成本任务；隔离检出完整通过。
- Windows Debug 模拟数据界面成功启动，热重载／热重启通过；Flutter Driver 实际点击“音乐”与“全部关注”均切换到对应列表，未发现运行时错误。测试后普通 `lib/main.dart` 入口的 Windows Debug 构建通过，模拟界面已关闭。

本机检查日志保留在 `.dart_tool/follow-groups-isolated-check-2026-11-06.log`；Windows 构建日志为 `.dart_tool/follow-groups-windows-debug-2026-11-06.log`。未使用真实账号执行在线分组读写，未进行 Android／macOS 实机或性能验收。

## 设置 UP 主分组（2026-10-06）

日期：2026-10-06。视频简介中的已关注按钮显示菜单，提供“设置分组”和“取消关注”。设置分组读取当前账号已有分组及该 UP 主的归属，勾选后仅在点击“保存”时提交。默认分组 `0` 与普通分组互斥；未选普通分组时回到默认分组。服务端保留的负数分组不展示为可编辑项，已有归属在提交时保留。

| 能力 | Host / 方法 / Path | 会话、响应与重试 |
| --- | --- | --- |
| 读取已有分组 | `api.bilibili.com` GET `/x/relation/tags` | Web Cookie，JSON `data` 数组，`tagid` 和 `name`；无分页，沿用总 deadline 25 秒及有界只读重试 |
| 读取目标用户所属分组 | `api.bilibili.com` GET `/x/relation/tag/user?fid={mid}` | Web Cookie，JSON `data` 对象，键为分组 ID；无分页，沿用总 deadline 25 秒及有界只读重试 |
| 保存分组 | `api.bilibili.com` POST `/x/relation/tags/addUsers` | Web Cookie 与表单 CSRF，`fids={mid}`、`tagids={逗号分隔 ID}`；空普通分组使用 `0`，单次提交，不自动重放；结果不明先刷新归属 |

接口路径、字段和返回形态参考相邻 `biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/UserDetailAPI.cs` 的 `FollowingsTag`、`FollowingTagUser`、`AddFollowingTagUsers` 及 `ViewModels/User/UserFollowingTagsFlyoutViewModel.cs`，分组列表字段同时参考 `bili-kernel/src/Services/Services.User/Core/Models/RelatedTag.cs`。仅借鉴协议事实，未复制参考项目的代码或资源。参考仓库的 App 签名请求没有被照搬；本项目使用现有 Web Cookie 请求管线。

默认与特殊分组 ID、单次表单参数另核对 [API-collect 的分组协议记录](https://github.com/pskdje/bilibili-API-collect/blob/main/docs/user/relation.md)。协议记录不代表本轮已执行真实账号写入。

本轮按用户要求未运行测试。根应用与三个包的静态分析及 Windows Release 构建通过，日志与入口见 [本轮构建记录](keyboard-feedback-focus.md)。真实登录账号的分组读写及窗口操作由用户验收，Android/macOS 本轮未构建或运行，接口可用性不由参考源码推定。
