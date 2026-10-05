# 收藏与订阅取消操作

日期：2026-10-06。Flutter 3.47.6 / Dart 3.13.5；沿用现有依赖。

## 页面与状态

“我的收藏 → 我的收藏与订阅”的收藏夹/合集卡片保留叠层封面、内容数、类型和播放数，标题右侧增加三点菜单，菜单样式参考用户截图。选择“取消订阅”后弹出确认框，显示目标名称；只有点击“确认取消”才提交，点击“取消”、关闭弹窗或确认期间切换账号均不提交。此菜单不用于默认收藏夹、自己创建的收藏夹或夹内视频。

提交期间禁用同一卡片菜单并显示进度；同一类型/ID 的操作单飞，不混淆相同数字 ID 的收藏夹与合集。服务端成功后移除对应卡片，保留其他卡片和当前滚动位置；失败保留内容。网络/超时等结果不明时提示刷新列表确认，不自动重放写请求。请求取消不提示通用错误。

取消成功使服务端分页位置移动：取消正在进行的列表读取、递增 generation，随后从第一页重读并对保留卡片去重，避免漏掉移动到前一页的内容；已经保留的分页允许重复项，超过已读页后恢复原有无新内容保护。移除记录最多保留 500 个类型/ID，显式刷新重新信任服务端快照。写操作拥有独立取消信号，关闭查询时释放；Repository 使用账号 scope 与 ApiRequests session epoch 阻止旧响应更改新账号状态。确认弹窗返回后再次检查页面、账号和操作对象。

## 端点与来源

两个端点均为 `api.bilibili.com`、Web profile、HTTPS POST、`application/x-www-form-urlencoded`、JSON 响应。要求当前目标 host/path 有效的 `SESSDATA` 与 `bili_jct`，CSRF 由共享提交管线加入正文，使用已有系统安全存储会话；无 WBI/App 签名、无分页。每次明确确认只提交一次，不重试网络、5xx 或业务失败；沿用总 deadline 25 秒与单次请求最多 12 秒的较小值。

| 对象 | Path | 正文 |
| --- | --- | --- |
| 收藏的普通收藏夹 | `/x/v3/fav/folder/unfav` | `media_id`、`csrf` |
| 订阅的 UGC 合集 | `/x/v3/fav/season/unfav` | `season_id`、`platform=web`、`csrf` |

视觉来自用户截图。本地只读核对 [FavoriteAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FavoriteAPI.cs) 和 [CollectedPage.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/Pages/User/CollectedPage.xaml.cs)，快照与许可限制沿用 [参考文档](../references.md)。Web 表单参数另核对 PiliPlus 的 [fav.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/fav.dart) 中 `cancelSub` 和 [api.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/api.dart) 路径常量。仅参考协议与交互，独立编写 Dart/Flutter，未复制源码/schema/资源，未修改相邻仓库。来源代码存在不代表真实账号写接口已在线验证。

## 验证边界

离线协议测试覆盖两类目标/长 ID、Cookie/CSRF 与目标作用域、HTTP/业务错误不重试、结果不明不重放、取消/deadline/账号 epoch；应用行为测试覆盖用户确认与两种关闭方式、确认期间换账号、成功移除、失败保留、重复点击、并发移除、迟到分页/刷新、页码移动、长列表重读及查询关闭。320/1920 像素双倍文字检查菜单与确认框，并保留卡片进入/返回语义。

本轮不使用真实账号执行取消订阅；普通 CI 仍只使用 fake transport/repository。真实 Web 写入及 Android/macOS 窗口操作尚未实测，未修改原生播放。

`tool/check.ps1 -SkipPub` 通过根应用和三个包的格式、静态分析及测试：根应用 586、API 包 206、播放器包 16、弹幕包 19 项，共 827 项（本轮共享工作区快照，包含其他已有改动）。日志为 `build/favorites-unsubscribe-check.log`。另外使用现有主题与字体完成 800/320 像素离线渲染视检，菜单与确认框快照为 `build/favorites-preview/unsubscribe-{menu,confirm}-{800,320}.png`，封面为占位样本，未读取私有收藏内容。

`flutter build windows --release --no-pub` 成功；产物为 `build/windows/x64/runner/Release/bili_lite.exe` 及配套目录，日志为 `build/favorites-unsubscribe-windows.log`。构建不代表真实窗口操作或三端验收；未启动或关闭用户已有客户端进程。
