# 视频合集订阅按钮

日期：2026-10-06。

## 行为

视频合集标题和播放量右侧显示紧凑粉色描边“订阅合集”按钮。游客点击调用现有登录入口。登录后先读取该合集对当前账号的订阅态，显示“订阅合集”或“已订阅”；点击后可订阅或取消订阅，成功时更新按钮并显示提示。读取失败以及写入结果不明时只显示“刷新状态”，需要重新读取后才能再次操作。请求按账号 scope、session epoch 和页面代次隔离；离开页面或切换账号时取消旧请求。

## 端点与来源

| 能力 | Host／方法／Path | 参数与协议 |
| --- | --- | --- |
| 订阅状态 | `api.bilibili.com` GET `/x/v3/fav/folder/collected/list` | Web Cookie，当前账号 `up_mid`、`pn`、`ps=20`、`platform=web`；分页扫描 JSON `data.list`，其中 `type=21` 且 `id` 等于合集 ID 即已订阅；读完全部页仍无匹配才判未订阅，有界只读重试与 25 秒总 deadline |
| 订阅 | `api.bilibili.com` POST `/x/v3/fav/season/fav` | Web Cookie／正文 CSRF，`season_id`、`platform=web`；表单 JSON，单次提交、不自动重放 |
| 取消订阅 | `api.bilibili.com` POST `/x/v3/fav/season/unfav` | 同上；与“我的收藏与订阅”已有取消端点一致 |

账号已收藏列表沿用现有 `HomeClient` 的 Web 端点及 `type=21` 合集识别；取消订阅对应本地 [FavoriteAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FavoriteAPI.cs)。订阅／取消表单另参考 PiliPlus 的 [合集操作](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/fav.dart) 与 [路径定义](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/api.dart)。这些来源仅用于核对协议事实，Dart／Flutter 代码独立编写，未复制参考仓库源码、schema 或资源，未修改相邻仓库。

2026-10-06 使用公开样本作无 Cookie 的只读核对：GET `/x/space/fav/season/list` 返回 `data.info` 的 `id/season_type/title/cover/upper/cnt_info/media_count/intro/enable_vt`，`info.id` 与请求的合集 ID 相同，既没有 `fid` 也没有 `fav_state`。因此此前读取 `info.fav_state` 会把正常响应判为协议错误；`info.id` 校验并非此次错误。GET `/x/v3/fav/folder/collected/list` 返回 `data.count/list/has_more`，公开样本首批 20 项中存在 `type=21` 合集，列表项 `id` 与对应合集详情 `info.id` 相同，`fid` 与其不同。诊断只输出了字段名、类型、计数和 ID 比较布尔值，没有读取或打印账号凭据。

## 验证边界

按本轮用户要求不运行或新增测试；前一版根应用与三个包的静态分析及 Windows Release 构建通过，见 [本轮构建记录](keyboard-feedback-focus.md)。本次修正后的构建由主任务统一处理。真实登录账号的订阅／取消写入由用户验收，Android／macOS 本轮未构建或运行。最多扫描 100 页；列表不完整、分页停滞或超出读取期限时不推断未订阅，界面保留刷新入口。
