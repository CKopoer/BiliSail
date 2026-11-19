# 互动视频

2026-11-20。只读参考 PiliPlus 提交 `217fb54f51f6764176319bbdedab2a7522d75401` 的 [请求和节点切换](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/video/controller.dart) 与 [完播选项交互](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/video/view.dart)。按协议字段和交互行为独立实现。

## 协议

| GET（`api.bilibili.com`） | 参数与响应 | 鉴权 |
| --- | --- | --- |
| `/x/web-interface/view` | `bvid` → `rights.is_stein_gate=1` 表示互动视频 | Web Cookie 可选 |
| `/x/player/wbi/v2` | `bvid/cid` → `interaction.graph_version` | Web Cookie 可选，WBI 签名 |
| `/x/stein/edgeinfo_v2` | `bvid/graph_version`，根节点省略 `edge_id`；读取首组 `edges.questions[].choices[]` 的 `id/cid/option` | Web Cookie 可选 |

三项均为 JSON 只读请求，无分页、无 CSRF。剧情版本和节点调用分别沿用现有 25 秒截止时间、最多 3 次读尝试，以及页面取消和账号 epoch 隔离。字段非法按协议失败分类。限流、鉴权和超时沿用 Web 请求分类。选项请求失败时当前视频仍可播放，片尾提供重试。

## 播放

剧情版本在当前视频内复用。播放器确认当前片段完播后显示选项，保持等待，直至用户选择、重播或离开。普通窗口、全屏和听视频消费同一节点状态。选中的节点在原播放会话从零开始，按分支 CID 解析 DASH、字幕与弹幕。源身份包含 CID 和节点 ID，分支共用 CID 时仍会重新开始播放。到达分支结局可以回到根节点从头再看。当前范围是 PiliPlus 同样覆盖的首组片尾选项。带变量条件的剧情、定时题目和剧情存档留待后续。

## 验证

- 2026-11-20 使用游客请求核对了 [选择角色，结局由你来定](https://www.bilibili.com/video/BV1vb4y1r7cg/)、[剧情全是伏笔](https://www.bilibili.com/video/BV1wE411i7Ri/) 和 [你能攻略女主选出正确结局吗](https://www.bilibili.com/video/BV17J411w7Ho/)。三个样本的互动标记、WBI 剧情版本、根节点、指定分支节点和分支 DASH 视频／音频轨道均有回包。
- 脱敏 fixture 位于 `packages/bili_api/test/playback_metadata_test.dart`。播放回归位于 `test/features/playback/continuous_playback_test.dart`，覆盖普通／全屏片尾、未就绪状态、同 CID 换节点、分支归零、结局回根及旧请求取消。
- 构建与真机验证由用户后续执行。
