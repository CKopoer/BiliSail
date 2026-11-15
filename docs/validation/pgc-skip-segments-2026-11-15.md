# PGC 空降助手与官方片头／片尾

日期：2026-11-15。

## 原因与修改

番剧、国创、剧集共用 PGC 播放链路，原先有两处普通视频限制：

- `PlaybackSession.open` 仅在 `target == null` 时加载空降数据，即使 PGC 已传入真实 bvid/cid 也不会查询。
- 普通菜单与窄屏更多菜单将所有 `contentTarget != null` 页面排除在“空降助手”入口之外。

现将在线 PGC 纳入共享加载与入口，使用组合根提供的当前剧集真实 bvid/cid，继续排除直播、离线。共用原有 `SponsorRepository`、独立无凭据第三方 transport、最多 512 个社区片段及取消／source generation；没有给第三方传入 B站凭据。

现有 Web PGC playurl 已返回官方 `clip_info_list`，本次沿用端点与鉴权，不增加网络请求。`bili_api` 将 `CLIP_TYPE_OP/CLIP_TYPE_ED` 和秒区间解析为类型化模型，仓储选流映射到带官方来源标记的领域区间；换音质保留元数据。忽略未知类型、非有限数值、倒序／空区间、越过源时长等非法项，最多解析 64 项；整个可选字段非法也不影响有效 DASH 音视频。试看不采用整集跳过数据。

## 设置与优先级

全局“设置 → 播放”和播放器“播放配置 → 播放”均增加“自动跳过官方片头／片尾”。沿用 `AppSettings`、控制器和 `preferences.v1` JSON 持久化，立即应用、失败回滚；不改 SQLite 表。旧快照缺失／非法值、恢复默认均为关闭，保留已有有效空降设置。

| 设置／数据 | 行为 |
| --- | --- |
| 官方自动跳过开启 | 有效官方 OP/ED 自动跳过，不依赖空降模式、类别或第三方服务成功 |
| 空降自动模式、已选片头／片尾 | 对应类别有有效官方区间时优先使用官方区间，即使独立官方开关关闭 |
| 对应类别没有有效官方区间 | 按原空降模式／类别使用社区数据；片头、片尾分别回退 |
| 空降手动模式、已选片头／片尾 | 有官方区间时使用官方区间显示原共享跳过按钮，独立官方开关关闭时不自动跳 |
| 空降关闭且官方开关关闭 | 不查询第三方、不展示或自动执行片段跳过 |
| 广告／自我推广等其他类别 | 保持空降模式与类别选择，不因官方 OP/ED 而整体关闭 |

存在有效官方片头时，整类社区片头不参与跳转；片尾同理，避免较早的社区起点先触发，或跳到官方终点后再次被社区较长区间跳走。仅替换类别，不把“存在一个官方片段”理解为放弃所有空降数据。

官方数据在媒体准备后即可应用，无须等待第三方查询结束；社区晚返回时也检查当前确认进度。两者共用现有 seek 和弹幕重建，同一源每个片段只自动跳一次，手动回退观看不会反复被拉走。延后执行前重查播放意图、playing／buffering／seeking、播放许可、source generation、账号 scope／epoch 及开关，防止切集、暂停或账号变化后执行旧跳转。按实际区间终点 seek，不将片尾直接解释成“播放下一集”，保留片尾之后的内容和既有播放模式。

## 来源与许可

仅参考协议与行为，独立实现，没有复制 GPL 应用代码、控件或资源，也没有修改相邻仓库。

- 相邻 PiliPlus 固定快照 `217fb54f51f6764176319bbdedab2a7522d75401`，应用许可 GPLv3。对照 [播放响应解析](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/models/video/play/url.dart)、[片段协议模型](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/models_new/sponsor_block/segment_item.dart)、[跳过策略](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/sponsor_block/block_mixin.dart) 与 [独立 PGC 设置](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/setting/models/extra_settings.dart)。
- PiliPlus 使用 `/pgc/player/web/v2/playurl` 的 `video_info`；游客实际核对 B站两个版本响应后，确认项目已有 `/pgc/player/web/playurl` 的 `result` 中同样包含这份字段，因此继续使用原接口。
- 独立开关与空降模式共存、按类别官方优先是本项目规则；没有同步或写入 B站账号的服务端播放器偏好。

## 验证

自动回归包括 PGC 真实身份查询与手动／自动跳过、官方 OP/ED 优先、缺失与非法官方区间的社区回退、类别取消选择、独立开关与关闭／手动／自动空降模式组合、零秒片头、第三方失败、设置即时生效及手动回退、暂停／缓冲／seek／切源／账号与 epoch 竞态。API 覆盖秒到毫秒、容量、可选非法数据及试看；选流覆盖换音质元数据保留；设置覆盖默认／落盘／重新加载／失败回滚／恢复默认。组件回归覆盖两处开关与桌面／窄屏 PGC 更多菜单。

游客只读在线烟测：使用本次 `PgcClient` 获取公开 `ep317925`，季类型 1、真实 bvid/cid 存在，非试看；取得视频 6 轨、音频 3 轨、时长 1506000 ms，解析出片头 0–16000 ms、片尾 1415000–1505000 ms。直接核对两版官方响应也返回同区间。此结果仅证明该公开样本的协议与解析，不代表全部片源都有区间或账号／大会员权益验收。

根检查脚本分阶段完成，均通过：

```powershell
.\tool\check.ps1 -SkipPub -Stage Lint
.\tool\check.ps1 -SkipPub -Stage RootTests
.\tool\check.ps1 -SkipPub -Stage PackageTests
```

| 范围 | 结果 |
| --- | --- |
| 格式、全仓静态分析与打包边界脚本 | 通过；`git diff --check` 与本次文档相对链接检查也通过 |
| 根应用 | 5664 通过、13 跳过 |
| bili_api | 1007 通过 |
| bili_player | 391 通过、3 跳过 |
| bili_danmaku | 161 通过 |
| bili_mux | 5 通过、10 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能算原生通过 |

新增设置改变列表位置后，已有滑动控制开关测试改为将目标滚到视口中部并等待布局完成再点击；该文件全部 62 项与最终根应用全量复跑通过。

没有打包或原生设备跳过验收，也没有 Android／Apple 实机或性能测量；未发现运行中的 debug／DTD 应用，未执行热重载。
