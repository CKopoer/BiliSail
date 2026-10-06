# 排行榜分区参数修正

日期：2026-10-06。

## 原因与来源

排行榜此前与普通分区列表共用 `loadCategories`，把 `/x/web-interface/newlist` 的旧分区 ID（动画 `1`、音乐 `3`、游戏 `4` 等）传入 `/x/web-interface/ranking/v2`。全站 `rid=0` 不受影响。参考 UWP 的请求路径、`type=all` 与 WBI 签名相同，差异在分区目录。

只读查看 `biliuwp-lite` 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [RankAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/RankAPI.cs) 与 [RankViewModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Rank/RankViewModel.cs)，并核对 [官网排行榜](https://www.bilibili.com/v/popular/rank/all) 的 [当前脚本](https://s1.hdslb.com/bfs/static/2233-monorepo/popular/static/js/index.55b42adc.js)：官网从 [配置接口](https://api.bilibili.com/x/kv-frontend/namespace/data?appKey=333.1339&nscode=10) 的 `channel_list.popular_page_sort` 读取目录，UGC 使用 `rid=tid`、`type=all` 请求同一个 ranking/v2 端点。配置本轮游客读取 `code=0`。

仅借鉴协议参数，独立编写 Dart，没有复制 C#、脚本代码、资源或线上响应 fixture；未修改参考仓库。许可边界沿用 [参考文档](../references.md#4-许可与来源记录)。

## 当前目录与实现

排行榜通过独立 Repository 能力与 Provider 动态加载官网配置，普通分区 `/newlist` 仍使用自己的目录。`RankingClient.getRegions` 请求 HTTPS GET `api.bilibili.com/x/kv-frontend/namespace/data`，参数 `appKey=333.1339`、`nscode=10`，Web profile、Cookie 可选、无签名、JSON、无分页。按 `data.data["channel_list.popular_page_sort"]` 中 JSON 字符串的顺序读取各 `channel_list.<key>` 的 JSON 字符串，使用其中 `name` 和 `tid`；仅采用目录实际引用的 UGC 项，跳过全站 `tid=0` 和带 `seasonType` 的 PGC 项，按 ID 去重。不写死分区 ID、名称或允许列表。

首次访问加载目录，当前工作区作用域内保留；排行榜刷新和目录失败重试都会重新请求配置。当前选中分区若被新目录撤下，回到 `rid=0` 全站并取消旧读取；目录失败呈现错误及重试入口，不退回可能已过期的固定分区目录。解码限制排序项 128 个、字符串 64 KiB、名称 128 字符；损坏的已引用配置返回分类协议错误，缺失项按官网方式跳过。

全站使用 `rid=0`；榜单是单份列表，无分页。请求 profile 为 Web，host 为 `api.bilibili.com`，HTTPS GET `/x/web-interface/ranking/v2`，Cookie 可选，WBI 签名，JSON `data.list[]`；配置与榜单均沿用取消、账号 epoch、deadline 和有界只读重试，风控不自动重试、不回退热门。下表仅为本轮配置快照，不是应用固定目录。

| 排行榜分区 | rid | 排行榜分区 | rid |
| --- | --- | --- | --- |
| 动画 | 1005 | 游戏 | 1008 |
| 鬼畜 | 1007 | 音乐 | 1003 |
| 舞蹈 | 1004 | 影视 | 1001 |
| 娱乐 | 1002 | 知识 | 1010 |
| 科技数码 | 1012 | 美食 | 1020 |
| 汽车 | 1013 | 时尚美妆 | 1014 |
| 体育运动 | 1018 | 动物 | 1024 |

这些 ID 与 UWP 新分区一致，名称和范围取自官网当前 UGC 排行目录。官网当前没有旧生活 `160`、国创相关 `168` 的 UGC 榜单入口；页面随配置变化显示可用 UGC 分区。番剧、国创与影视剧集排名需要不同 PGC 端点及内容模型，本次不新增这些入口。

## 验证边界

初次未签名游客直读旧动画 `rid=1` 与新动画 `rid=1005` 均返回业务码 `-352`；项目完整 WBI 全站读取也遇到该风控。接入动态目录后，完整应用链路烟测成功：目录 14 个 UGC 分区、全站榜 100 条、目录首个动画分区 `rid=1005` 榜 100 条，推荐和普通分区均为 20 条。可复现入口为 [feed_smoke.dart](../../packages/bili_api/tool/feed_smoke.dart)，其分区榜读取直接使用目录返回的 ID。

随后通过 [ranking_smoke.dart](../../packages/bili_api/tool/ranking_smoke.dart) 比较 `1005/1008` 与诊断输入旧 ID `1/4` 时，四个榜单请求再次返回 `-352`；目录仍成功。没有在线取得可比较的投稿日期或榜单说明，因此不能声称已实测旧榜单冻结日期或所有分区的新鲜度。此工具只输出公开目录数量、ID、日期范围和脱敏状态；旧 ID 仅为显式诊断输入，不是应用的备用请求。

回归测试覆盖配置请求、JSON 字符串解码、动态名称/新 ID/顺序、PGC/未引用项过滤、重复/损坏/超限数据、账号旧响应、风控单次请求；应用测试覆盖实际榜单请求的 `rid/type/WBI`、单份榜单语义，以及页面点击、频道返回、目录刷新、分区撤下与全站切换。

`tool/check.ps1 -SkipPub` 通过：根应用 774、bili_api 258、bili_player 16、bili_danmaku 32 项测试，总计 1080 项；根应用和三个包格式与静态分析均通过。新增文档相对链接及 `git diff --check` 通过。未进行新的原生构建或 Android/macOS 实机测试；本轮没有修改原生播放器。
