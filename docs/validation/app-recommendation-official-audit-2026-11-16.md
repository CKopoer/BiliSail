# App 推荐与官方 Android 9.19.0 对照

日期：2026-11-16。针对“App 推荐不够个性化”进行源码、GitHub 和官方 APK 静态分析，并执行无账号的只读协议抽样。本轮只增加调查记录，不修改推荐、登录或上报实现。

本文保留修复前的调查结果；同日后续实现、进一步确认的首卡锚点语义及实际验证边界见[请求与归因修正](app-recommendation-alignment-2026-11-16.md)。

## 基线与结论

工作区从 `codex/fix-macos-foreground-startup` 切到 `master`，快进至 `b6cf1f31f788c5191d59c798b0aae57d9b7a1fa3`（1.3.0，提交时间 2026-11-16 00:16:05 +08:00）。开始与拉取完成时工作区均干净，原分支保留。

**当前调用的是正确的 App 首页端点，但完整请求及反馈上下文没有与官网当前 Android 安装包同步。** 与最新 PiliPlus 的 App feed 基本一致，只能证明第三方实现之间一致。

本轮新增两项具有官方静态证据的协议问题：

1. **加载场景丢失：** `flush` 始终为 `8`，首屏、手动刷新和加载更多均被标为官方 `PULL_UP`。官方有独立的 `NORMAL=0`、`TAB_CLICK=5`、`PULL_DOWN=6`、刷新按钮等枚举。
2. **服务端游标丢失：** 把 `idx` 当作 `page-1`，并把 `nextCursor` 构造成 `page+1`；官方使用卡片提供的 `getIdx()`。本项目 DTO 和应用层分页结果均没有保留 App feed 的真实游标。

此外，账号身份、混合客户端 profile、固定会话占位符和缺少推荐来源归因，均可解释为什么不能期待复现官方推荐体验；**尚未用用户真实账号证明这些因素各自对推荐质量的影响**，不能将某一项定为本次个性化不足的唯一根因。

## 核对材料

| 材料 | 固定版本／来源 |
| --- | --- |
| BiliSail | `b6cf1f31f788c5191d59c798b0aae57d9b7a1fa3` |
| PiliPlus | [`217fb54f51f6764176319bbdedab2a7522d75401`](https://github.com/bggRGjQaUbCoE/PiliPlus/tree/217fb54f51f6764176319bbdedab2a7522d75401)；feed 文件最近一次提交为 2026-11-07 |
| BiliPai | [`aaeab945784a145859b0e73675832973d0431bda`](https://github.com/jay3-yy/BiliPai/tree/aaeab945784a145859b0e73675832973d0431bda)；请求策略最近调整为 2026-11-14 |
| 官方 Android APK | [官网下载中心](https://app.bilibili.com/)的 [Android 64 位下载](https://dl.hdslb.com/mobile/latest/android64/iBiliPlayer-bili.apk)，本次下载的包为 `tv.danmaku.bili`，`versionName=9.19.0`，`versionCode=9190400` |
| APK 摘要 | SHA-256 `c3ea50c7773267f252e441b5c1aebf7574492223b2bb1568d7a7093d1f8eb59c`；241376892 字节；CDN Last-Modified 为 2026-11-11，不将其等同于发布日期 |
| 工具 | 临时 Maven runtime 运行 JADX 1.5.6；只解出相关 DEX 并定向反编译，没有安装或运行 APK |

下载 URL 中的 `latest` 会变化，版本结论只对应上面的摘要。相关方法存在 JADX 类型推断警告；本文依据清晰的接口注解、枚举、参数赋值及请求调用，不把重建出的整个类当作可编译源码。

官方包、工具及中间文件位于 `/tmp/bilisail-app-audit-20261116/`。小型证据副本、探测脚本及统计保存在本机 `build/app-recommendation-audit-20261116/`；APK、工具 JAR 和反编译源码不提交 Git。仓库仅保留本文及[脱敏抽样摘要](data/app-recommendation-official-audit-2026-11-16.json)。

## 当前实际请求

调用链是 [FeedController](../../lib/features/feed/application/feed_controller.dart) → [ApiFeedRepository](../../lib/features/feed/data/api_feed_repository.dart) → [AppRecommendationClient.load](../../packages/bili_api/lib/src/clients/app_recommendation_client.dart) → [BiliApiClient.requestAppJson](../../packages/bili_api/lib/src/api_client.dart)。

`GET https://app.bilibili.com/x/v2/feed/index`，JSON 的 `data.items`。来源选择为 App 时，没有失败后改请求 Web 的降级分支。

| 参数组 | 当前固定值／规则 |
| --- | --- |
| 构建与产品 | `build=8430300`、`mobi_app=android_i`、`platform=android`、`channel=master` |
| 设备与布局 | `device=phone`、`device_name=android`、`device_type=0`、`column=2`、`network=wifi` |
| 推荐与分页 | `disable_rcmd=0`、`recsys_mode=0`、`flush=8`、`idx=page-1`、`pull=(page==1)`、`guidance=1`、`splash_id=''` |
| 媒体能力 | `fnval=976`、`fnver=0`、`force_host=2`、`fourk=1`、`https_url_req=1`、`player_net=1`、`qn=32`、`voice_balance=0` |
| 语言 | `c_locale=s_locale=zh_CN` |
| statistics | `appId=1`、`platform=3`、`version=8.43.0`、空 `abtest` |
| query 签名 | HD `appkey=dfca71928277209b`、秒级 `ts`，对排序编码后的字段生成 MD5；有效同账号 token 才加 `access_key` |
| UA | HD `BiliDroid/2.0.1`、`mobi_app/android_hd`、`build/2001100` |
| 最终 header | `app-key=android64`、稳定的本应用 buvid、`env=prod`、固定指纹／session／trace、`bili-http-engine=cronet`、Bilibili referer；有效 token 时增加其账号的 mid／aurora eid |

[AppProfile](../../packages/bili_api/lib/src/app_profile.dart) 的 query `appkey` 与 HTTP header `app-key` 是不同字段。`bili-http-engine=cronet` 只是声明，实际传输是 [DioApiTransport](../../packages/bili_api/lib/src/transport.dart)，不会因此切换为 Cronet。App 推荐不携带 Web Cookie。

空参数 `splash_id=` 的签名已于 11 月 10 日修复，本次基线不是旧的裸 key 签名，不能重复作为新问题。当前广告／`can_play` 排除规则与 PiliPlus 一致，也已接纳非 av 身份，不再存在历史上的统一 `card_goto=av` 门槛。

## 官方 APK 中的对应实现

### 首页端点仍然存在

`classes14.dex` 的 `ir8.getIndexList` 仍声明 `@GET("/x/v2/feed/index")`，base URL 是 `https://app.bilibili.com`；`com.bilibili.pegasus.request.a` 实际调用它。没有证据表明普通首页已统一迁移成另一个 gRPC 接口。

接口显式参数包括 `idx/pull/login_event/open_event/banner_hash/interest_result/flush/interest_id/splash_id/splash_ids/splash_creative_id/interest_pos_ids/cny_info/clipboard_video_id/clipboard_unique_k/window_size_type/raw_window_size_type`。这些参数有各自状态与可选条件，缺少某个可选字段本身不能认定请求无效，也不建议为“对齐”采集剪贴板或硬件标识。

### 确认问题一：flush 不是固定开关

`com.bilibili.pegasus.data.request.PegasusFlush` 明确定义：

| 官方枚举 | 值 | 本项目现状 |
| --- | --- | --- |
| `NORMAL` | 0 | 没有表达 |
| `TAB_CLICK` | 5 | 没有表达 |
| `PULL_DOWN` | 6 | 手动刷新仍发 8 |
| `TOP_REFRESH_BUTTON_CLICK` | 7 | 没有独立表达 |
| `PULL_UP` | 8 | 所有请求都用它 |
| `LOGIN_CHANGE` | 21 | 账号变化后的重载仍发 8 |

官方初始 `RequestParam` 默认 `idx=0,pull=true,flush=NORMAL`，不能把“官方首屏一律 flush=5”写成定论。`TAB_CLICK=5` 是一个实际入口场景；刷新按钮和下拉也有区别。

本项目 [load](../../packages/bili_api/lib/src/clients/app_recommendation_client.dart) 和[领域接口](../../lib/features/feed/domain/feed_repository.dart)只接收 `page`，调用方无法传递加载原因。修正需要把加载场景从控制器一路传给协议层，而非只改一个常量。

### 确认问题二：idx 是响应上下文

`com.bilibili.pegasus.vm.PegasusViewModel.m1` 从当前状态卡片调用 `getIdx()`，没有卡片才用 `0`，再构造请求。该版本的代码取状态列表 `firstOrNull()`；不能未经核对内部列表顺序就一概解释为“原始响应最后一张”。预加载下拉刷新也读取卡片 `idx`。

本项目收到服务端 `items[].idx` 后没有解析或保存，`nextCursor` 又设为 `page+1`；仓储返回的 [PageResult](../../lib/domain/page_result.dart)只含 items／hasMore，控制器只能递增 `_page`，每次刷新重新发送 `idx=0`。当前测试还把这些取值固定为“与 PiliPlus 一致”，未验证官方游标语义。

建议为 App 推荐单独保留可验证的响应游标与请求场景，按官方实际列表顺序核对取值；在广告／不可播放卡片和用户过滤之前提取所需上下文，避免过滤后丢失游标。失败重试复用同一请求上下文，成功后才推进；来源或账号变化仍需取消并清空对应状态。

### profile 和运行状态也没有同步

官方 `DefaultRequestInterceptor` 从 `BiliConfig` 取得构建、mobi_app、appkey、access_key、UA、buvid、指纹及 session；它还允许公共参数工厂接管，因此静态分析不能替代抓取最终出站请求。

首页的 `lbt0 → aje → ntz0 → DefaultRequestInterceptor` 链会根据实际状态设置 column、network、device_name、首次启动标记、推荐模式、自动播放、自动刷新、video_mode、宽屏参数，并委托播放器工具生成预加载能力参数。本项目的 phone query／HD UA 与签名／android64 header 是第三方兼容组合，不是本次国内 Android 9.19.0 安装包的完整运行身份。

`session_id=11111111`、固定 trace 和 64 个 `1` 的指纹只是占位；它们不等于官方设备会话。不过，本次没有服务器排序／实验命中证据，不能断言占位字段必然导致降级、风控或个性化关闭。profile 的后续对照须与当前 token 的颁发端兼容，保持账号与设备稳定；单独改成新 build 不能证明同步。

## 与“个性化不足”有关的另外两条链路

### App 来源不保证已携带账号

[身份仓储](../../lib/features/feed/data/app_recommendation_identity_store.dart)仅在同账号且 token 未过期、未失效、buvid 匹配时返回 `accessToken/accountMid`；没有 token 时仍正常请求游客 App feed。已有 token 过期则报认证错误，不静默降级游客。

11 月 15 日的最新实现中，扫码、密码及短信正常登录成功均保存 App/Web 双凭据。**“密码／短信必定是游客”已不适用于当前 master。** 显式官网登录和旧的仅 Web 安全快照仍可能没有 App token，升级不会自动兑换；这应通过当前请求的鉴权布尔状态验证，而非靠已登录头像判断。

用户此前要求删除推荐设置的身份／来源说明，本轮保持该决定，没有重新加 UI。后续诊断只需输出 `has_access_key`、`mid_matches`、`token_expired`、`buvid_matches` 等本地布尔摘要，不记录 token、Cookie、真实 buvid 或完整请求 URL。本次未读取用户安全存储，故不能判定用户当前安装的实际身份。

### 推荐来源归因没有贯穿播放

官方 `BasePegasusData` 保留 `trackId`，`PlayerParamsBuilderKt.addBasicPlayerParams` 会从推荐 URI 取 `trackid` 写入播放参数。本项目 [App DTO](../../packages/bili_api/lib/src/models/app_recommendation_models.dart)没有 App track 字段，普通 av 点击[只导航到 BV 路径](../../lib/features/feed/presentation/feed_video_grid.dart)，没有把推荐曝光／来源上下文传给播放会话。

本项目已经有 [Web 播放心跳](../../packages/bili_api/lib/src/clients/playback_history_client.dart)，携带 BV、cid、进度、时长和 UGC/PGC 类型；不能说“完全没有行为反馈”。但它不携带 App feed 的 trackid、来源位置或设备 session，不能视为官方 App 推荐曝光／点击／播放归因的等价实现。跨端观看历史如何进入服务端推荐特征、缺失归因影响多大，本轮没有证据。

后续若评估补齐反馈，应先明确事件和产品边界、保留账号隔离及有界去重；本轮没有增加自动遥测、发送反馈、点赞或播放上报。

## GitHub 最新实现的意义与局限

- [PiliPlus feed](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/http/video.dart)、[常量](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/common/constants.dart)及[账号拦截器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/utils/accounts/account_manager/account_mgr.dart)仍采用同一混合 profile、固定 flush=8 和计数式 freshIdx。继续与它逐字段对齐，不能发现本轮两个官方协议偏差。
- [BiliPai 请求策略](https://github.com/jay3-yy/BiliPai/blob/aaeab945784a145859b0e73675832973d0431bda/app/src/main/java/com/android/purebilibili/data/repository/HomeFeedRequestPolicy.kt)已区分 5／6／8，按授权类型区分手机和 HD profile；[HD 请求](https://github.com/jay3-yy/BiliPai/blob/aaeab945784a145859b0e73675832973d0431bda/app/src/main/java/com/android/purebilibili/data/repository/VideoRepository.kt)使用 HD build／mobi_app／statistics。其“首次进入=5”是该客户端自己的映射，官方还有 NORMAL 等分支；不机械照搬。
- 仅参考这些仓库的协议和行为，没有复制 GPL 应用代码、增加依赖或修改相邻仓库。

## 只读在线抽样

使用临时 Python 脚本读取当前源码中的 feed query，以标准库实现相同签名和公开 headers。每次实验使用同一个临时生成 buvid，不读取用户 Cookie、App token 或已保存设备。它是协议探测，不等同于运行 Flutter/Dio 实现的集成测试。

| 请求 | HTTP／业务码 | 原始／可播放非广告卡 | 服务端 idx 摘要 |
| --- | --- | --- | --- |
| 当前首屏：idx=0, pull=true, flush=8 | 200／0 | 12／12 | 首项 1794819840，末项 1794819829 |
| 当前翻页：idx=1, pull=false, flush=8 | 200／0 | 12／11 | 首项无 idx，末项 -11 |
| 带回响应 idx=1794819840，pull=false, flush=8 | 200／0 | 10／9 | 首项 1794819839，末项 1794819830 |
| 同一响应 idx，pull=true, flush=6 | 200／0 | 10／10 | 首项 1794819850，末项 1794819841 |

该样本直接说明 `idx=1` 与延续响应上下文不同。四个样本的 `(card_goto,param)` 没有交集，未复现重复推荐；不能根据本次随机的游客样本评价账号推荐效果、证明游标修复提升兴趣匹配，也不能据此推导服务端的精确排序／去重算法。

## 处理顺序与验收

1. 在用户问题复现时，确认实际请求是否携带同账号有效 App token。当前 master 已支持三种 App 登录，旧会话仍需单独判断；本轮不要求用户退出或修改凭据。
2. 优先修正 App feed 的加载场景和服务端游标，增加覆盖首屏、手动刷新、翻页、过滤后空页、失败重试和账号切换的行为回归。现有“固定完整 query 等于 PiliPlus”的测试不足以证明官方同步。
3. 在 token 兼容的前提下做完整 profile 对照，保持同账号、稳定 buvid、交替采样多轮；分别统计服务端原始卡片、协议过滤和用户过滤。HD 推荐与手机官方推荐本来可能走不同策略，不能保证逐条一致。
4. 最后评估推荐来源贯穿播放及真实用户动作反馈；它涉及产品行为，单独设计和验收，不混入本轮只读调查。

本轮完成：master 快进、源码核对、GitHub 对照、官方 APK 版本与 SHA 校验、相关类 JADX 分析、4 次无账号只读请求，以及文档链接和 diff 检查。未修改业务代码，未运行 Flutter／Dart 全套检查、构建、安装、实机抓包、账号个性化对照或性能测量；本机 PATH 未提供 Flutter／Dart。游客接口成功不等于账号个性化或修复通过。
