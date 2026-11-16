# App 推荐请求与播放归因修正

日期：2026-11-16。承接[官方 APK 对照](app-recommendation-official-audit-2026-11-16.md)，在 `b6cf1f31` 基线上实施；官方 APK、JADX 版本和摘要沿用调查记录。

## flush 与服务端索引

[AppRecommendationRequest](../../lib/features/feed/domain/app_recommendation_request.dart)显式传递加载原因和服务端索引。映射为 initial=0、tabClick=5、pullDown=6、refreshButton=7、loadMore=8、identityChanged=21，只有加载更多使用 pull=false。App 协议不再接收页码。

`items[].idx` 在广告、内容类型、可播放及用户过滤之前提取，按有符号 64 位整数校验，以十进制字符串传输。本次官方 9.19.0 的 `PegasusViewModel.m1` 从当前状态首卡读取 getIdx；补读 `LoadMoreAction` 的 simple 模式确认它直接使用该请求，加载完成将新卡追加到旧列表。因此本轮刷新成功后更新首卡锚点，加载更多沿用锚点，不机械改成末卡索引。

刷新失败保留原场景与锚点供显式重试；加载更多失败不推进状态。来源／身份变化归零并取消旧请求，迟到结果不能更新新状态。普通频道切换保留推荐锚点，现有无新增页预算不变。

## 参数、签名和 UA 的来源

| 信息 | Android | 非 Android |
| --- | --- | --- |
| 型号、系统 | Build.MODEL、Build.VERSION.RELEASE | 固定 HD 参考 android_hd／15 |
| 网络 | ConnectivityManager WIFI／CELLULAR capability；未知保持未知 | 固定参考 wifi |
| build、版本、mobi_app、appkey | 取决于凭据所属客户端，不能从硬件或 BiliSail 版本推导 | 同一规则 |
| 签名 | 参数排序、单次 percent encoding、保留空值等号，拼接对应 appsec 后 MD5，每次增加 ts | 同一纯 Dart 实现 |
| UA | 客户端版本部分固定，填入公开设备事实 | 固定 HD 参考 |
| buvid | 沿用本应用已有持久化标识 | 同一规则 |
| session／trace | 当前 API client 的随机 session、逐请求随机 trace | 同一规则 |

Android 通过[原生 Handler](../../android/app/src/main/kotlin/dev/bilisail/bilisail/AppRequestDeviceHandler.kt)和[平台桥](../../lib/core/platform/app_request_device.dart)读取公开事实，只增加普通权限 ACCESS_NETWORK_STATE，无新 Pub 依赖；原生调用有 2 秒上限。Feed 的 query 和 UA 共用一次设备快照，沿用总 deadline、取消及 session epoch 校验。密码／短信的设备名称和系统字段也使用这一入口。

**现有扫码、密码及短信登录颁发 HD 凭据，因此本次统一完整 HD profile。** query 使用 build=2001100、mobi_app=android_hd、device=pad 和 HD statistics；签名继续使用 HD appkey dfca71928277209b，UA 为 HD 2.0.1，header app-key=android_hd。参考 [BiliPai HD 请求](https://github.com/jay3-yy/BiliPai/blob/aaeab945784a145859b0e73675832973d0431bda/app/src/main/java/com/android/purebilibili/data/repository/VideoRepository.kt)和[凭据匹配的签名约定](https://github.com/jay3-yy/BiliPai/blob/aaeab945784a145859b0e73675832973d0431bda/core-data/src/main/java/com/android/purebilibili/core/network/AppSignUtils.kt)，仅借鉴协议并独立实现。

这修正了手机 8.43.0 query／HD 签名与 UA／android64 header 的混用，没有把 HD token 变成手机 9.19.0 的凭据。将来接入手机凭据时，需记录颁发 profile，并一起选择相应的 build、mobi_app、UA 和签名 key。

官方 BiliConfig／公共参数工厂提供客户端 profile 和 SDK 指纹，设备公开 API 拿不到这些值。项目不读取官方 App 私有数据、不采集硬件标识；删除全 1 的 fp 占位及虚假 Cronet 声明，保留现有 buvid 和安全凭据。新 session／trace 是本进程请求标识，不宣称是官方指纹。

## trackid 到实际播放

官方 `PlayerParamsBuilderKt` 从推荐 URI 的 trackid 读取来源，Android `HeartbeatParams` 输出字段 track_id。进一步读取[官方 Web 播放器 core.js](https://s1.hdslb.com/bfs/static/player/main/core.js)，确认现有 `/x/click-interface/web/heartbeat` 同样将 trackId 写为 track_id，并支持 from_spmid。因此沿用现有心跳，无新增上报端点。

1. [协议解析](../../packages/bili_api/lib/src/clients/app_recommendation_client.dart)优先取 URI trackid，只解码一次，缺失时接受顶层 track_id；拒绝控制字符、超长值和重复 URI 参数产生的歧义。
2. [仓储](../../lib/features/feed/data/api_feed_repository.dart)映射为[内存上下文](../../lib/domain/recommendation_playback_context.dart)，绑定普通视频或已识别剧集、account epoch，以及来源 tm.recommend.0.0。
3. 点击后，[有界注册表](../../lib/features/playback/application/recommendation_playback_registry.dart)生成临时导航引用。URL 不包含原始 track ID；[路由](../../lib/app/router.dart)校验目标与 epoch，再经共享 Scope 交给播放器。最多 64 项，重启、淘汰或账号切换后的引用不能恢复旧归因。
4. [PlaybackSession](../../lib/features/playback/application/playback_session.dart)和内存返回快照持有上下文；换清晰度、恢复和同视频换 P 保留来源，同一视频再次点击推荐卡更新来源而不重开媒体。切到无关视频／剧集、停止或账号变化清除。普通／全屏共用原会话。
5. 真实播放沿用现有 [Reporter](../../lib/features/playback/application/playback_history_reporter.dart)，[仓储适配](../../lib/features/playback/data/api_playback_history_repository.dart)再次校验目标和 epoch，[心跳客户端](../../packages/bili_api/lib/src/clients/playback_history_client.dart)附带 track_id／from_spmid。无归因的普通播放、离线、直播及游客沿用原边界。

原始 track ID 不进入页面 URL、SQLite、续播快照或设置；没有新增曝光轮询、心跳数量、自动点赞或推荐反馈。服务端是否将这些字段用于何种特征及兴趣排序，仍需真实账号对照。

## 验证

- API 包全量 1011 项测试通过，包含各场景、过滤前锚点、有符号索引、设备快照、HD 固定签名、URI 单次解码、track_id 心跳和取消／epoch 隔离。
- 使用本次 Dart 实现做游客只读烟测：initial／loadMore／pullDown 的 flush 分别为 0／8／6，每次取得 19 条可播放推荐及服务端锚点。未读取用户凭据或已保存设备，未发送真实账号心跳／反馈。
- Flutter 3.47.6／Dart 3.13.5：应用定向 364 项通过，覆盖 feed 控制器、卡片映射和点击、登录、播放会话、归因注册表及设备桥；根应用静态分析无问题。
- `tool/check.ps1 -Stage PackageTests -EnforceLockfile` 通过：bili_api 1011、bili_player 373、bili_danmaku 161、bili_mux 5，共 1550 项。player 的 3 项原生媒体测试及 mux 的 10 项原生测试因未配置原生组件跳过，不能计为原生通过。五份锁文件无变化。
- `tool/check.ps1 -EnforceLockfile` 在原有 `tool/test-macos-release-validation.ps1:339` 清理非空临时目录时失败（PowerShell 7.7.0／macOS，Remove-Item 触发确认并报 Object reference）。未为本次任务修改打包脚本。
- 补跑被上述错误挡住的检查：iOS 打包布局 14 项、macOS Python 15 项、SQLite 17 项、Linux WebView 3 项通过；`test_ios_*.py` 有两处 setUpClass 错误，现有 Swift 测试桩的 CGSize 缺少 zero 及比较运算支持。未修改相关测试桩或媒体依赖，不计为 iOS 原生通过。
- 其余媒体边界检查：Apple texture 1 项及 Apple libs 7 项通过；Windows media assets 受本机缺少 cmake，以及两个原生 fixture 运行超过 10 秒上限阻塞。全部包与根应用格式检查通过。上述媒体文件及锁定依赖均无本次改动。
- 单独执行 RootTests：8 分 29 秒时 4350 项通过、1249 项失败、5 项跳过，余下用例挂起后中止，未取得全量通过。失败包含窗口几何预期、窗口焦点及其 2 秒遗留计时器。在完全未修改的 `b6cf1f31` 独立 worktree 复验 `window_service_test.dart` 与 `predictive_back_test.dart`，得到 17 通过／114 失败／4 跳过，复现相同的 saveGeometry／captureGeometry 差异与 WindowInputFocus 计时器堆栈。这只确认代表失败存在于基线，未逐项证明全量失败原因。
- 在线脱敏摘要和本地验证日志位于忽略的 `build/app-recommendation-audit-20261116/` 及临时审计目录；原始 APK／反编译材料不入库。未配置 Android SDK／设备，本次没有 Android 原生构建、安装或实机验证，也未做三端播放验收。
- 未用真实账号验证登录后的出站请求、播放心跳及兴趣排序。游客读取成功不代表账号个性化验收；本次修正协议和归因缺口，个性化改善幅度尚未测量。
