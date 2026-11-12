# 收藏视频移除与收藏夹删除

日期：2026-11-12。Flutter 3.47.6 / Dart 3.13.5，未增加依赖。

“默认收藏夹”和“我创建的收藏夹”内的视频，长按卡片或点击更多按钮可选择“取消收藏”。确认后只从当前收藏夹移除，保留其他收藏夹中的收藏记录。收藏资源的 `id` 在协议边界映射为视频 `aid`，以字符串保留精度；失效视频仍可移除，非视频资源不使用视频类型提交。

“我创建的收藏夹”卡片的长按和更多菜单新增“删除收藏夹”，保留编辑信息入口。确认框说明夹内收藏记录会一并删除且无法恢复。默认收藏夹、订阅收藏夹和 UGC 合集不提供此删除入口。写入前重新读取收藏夹拥有者，只有当前账号自己的收藏夹可操作；确认期间切换账号、会话 epoch 或当前列表时不提交。

操作期间同一条目单飞并禁用菜单。成功后移除目标，保留其他条目，取消迟到分页并从第一页重新协调服务端偏移；失败保留条目。写结果不明时提示刷新核对，同一条目在显式刷新前不能再次提交，不自动重试。默认收藏夹的服务端 ID 与本地快照分页游标分开保存；只使被修改收藏夹的本地快照失效，不清除无关合集的快照。移除视频后刷新父列表数量，删除收藏夹后丢弃该页缓存。

两个端点均为 `api.bilibili.com`、Web profile、HTTPS POST、form-urlencoded、JSON，使用目标 host/path 有效的 `SESSDATA` 和 `bili_jct`。CSRF 由共享提交管线加入正文，无 WBI/App 签名；无分页，每次确认最多一次 POST，沿用共享 deadline 和取消、账号隔离。

| 操作 | Path | 正文（不含共享 csrf） |
| --- | --- | --- |
| 从指定收藏夹移除视频 | `/x/v3/fav/resource/batch-deal` | `resources=<aid>:2`、`add_media_ids=`、`del_media_ids=<folderId>` |
| 删除自建收藏夹 | `/x/v3/fav/folder/del` | `media_ids=<folderId>`、`platform=web` |

只读参考 PiliPlus 固定提交 `cab0114a21ce7fad5b90b9a4d788d35d313d25f9` 的 [fav.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/http/fav.dart)（`favVideo`、`deleteFolder`）和 [api.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/http/api.dart)。PiliPlus 应用为 GPLv3，本次仅核对端点、参数和操作范围，独立实现，没有复制应用源码或资源、修改相邻仓库。

离线测试覆盖协议正文、长 ID、鉴权、取消、deadline、不重放失败、拥有者校验、迟到会话响应、确认/取消、长按/更多按钮、单飞、分页协调、不明结果刷新、默认收藏夹连续移除、失效视频及 320/1920 像素大字体布局。未使用真实账号执行删除；真实 Web 写入和各平台实机操作尚未验证。

本轮收藏相关应用定向测试 56 项、接口定向测试 28 项通过。四包测试分别通过 API 892、播放器 398、弹幕 161、mux 5 项；mux 的 10 项原生用例未配置 `BILI_MUX_LIBRARY`，按既有规则跳过。全仓格式与 `flutter analyze --no-pub` 通过。

`tool/check.ps1 -Stage RootTests -SkipPub` 通过根应用 5216 项测试，另 6 项按平台条件跳过。根应用与四包合计通过 6672 项。当前工作区日志保存在 `build/favorite-management-2026-11-12/`。

`tool/check.ps1 -Stage Lint -EnforceLockfile` 在本次受管 Linux 环境停于既有 `test-macos-release-validation.ps1:320` 的独立父进程清理停滞 worker/child 检查，单独重跑仍复现；脚本及相关代码未修改。其余格式、平台适配器分析和打包边界检查已分别通过，不将该失败记为完整 Lint 通过。
