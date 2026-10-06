# 视频 UP 主关注分组

日期：2026-10-06。视频简介中的已关注按钮显示菜单，提供“设置分组”和“取消关注”。设置分组读取当前账号已有分组及该 UP 主的归属，勾选后仅在点击“保存”时提交。默认分组 `0` 与普通分组互斥；未选普通分组时回到默认分组。服务端保留的负数分组不展示为可编辑项，已有归属在提交时保留。

| 能力 | Host / 方法 / Path | 会话、响应与重试 |
| --- | --- | --- |
| 读取已有分组 | `api.bilibili.com` GET `/x/relation/tags` | Web Cookie，JSON `data` 数组，`tagid` 和 `name`；无分页，沿用总 deadline 25 秒及有界只读重试 |
| 读取目标用户所属分组 | `api.bilibili.com` GET `/x/relation/tag/user?fid={mid}` | Web Cookie，JSON `data` 对象，键为分组 ID；无分页，沿用总 deadline 25 秒及有界只读重试 |
| 保存分组 | `api.bilibili.com` POST `/x/relation/tags/addUsers` | Web Cookie 与表单 CSRF，`fids={mid}`、`tagids={逗号分隔 ID}`；空普通分组使用 `0`，单次提交，不自动重放；结果不明先刷新归属 |

接口路径、字段和返回形态参考相邻 `biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/UserDetailAPI.cs` 的 `FollowingsTag`、`FollowingTagUser`、`AddFollowingTagUsers` 及 `ViewModels/User/UserFollowingTagsFlyoutViewModel.cs`，分组列表字段同时参考 `bili-kernel/src/Services/Services.User/Core/Models/RelatedTag.cs`。仅借鉴协议事实，未复制参考项目的代码或资源。参考仓库的 App 签名请求没有被照搬；本项目使用现有 Web Cookie 请求管线。

默认与特殊分组 ID、单次表单参数另核对 [API-collect 的分组协议记录](https://github.com/pskdje/bilibili-API-collect/blob/main/docs/user/relation.md)。协议记录不代表本轮已执行真实账号写入。

本轮按用户要求未运行测试。根应用与三个包的静态分析及 Windows Release 构建通过，日志与入口见 [本轮构建记录](keyboard-feedback-focus.md)。真实登录账号的分组读写及窗口操作由用户验收，Android/macOS 本轮未构建或运行，接口可用性不由参考源码推定。
