# App 推荐与竖屏内容：GitHub 源码对照

调研日期：2026-10-31。使用 Exa 的三轮检索取得 22 条候选结果，再通过 GitHub 连接器读取实现、调用方、签名与模型。本文为源码调研，不是推荐效果实测；未读取本机账号凭据，未请求真实账号推荐，未修改业务代码。

## 结论

1. PiliPlus、BiliPai、Bilibili-Gate、bilimiao、PiliPala 都实现了 App 首页推荐，核心端点相同：`GET https://app.bilibili.com/x/v2/feed/index`。值得比较的是完整请求身份与响应处理，而不是只换 URL。
2. BiliSail 的首页请求参数和本机 PiliPlus 快照基本一致；GitHub 当前 PiliPlus 也保留相同参数。两者都使用 `mobi_app=android_i / build=8430300 / device=phone`，同时使用 Android HD 的签名 key 和 UA。这是源码确认的组合，不能等同于完整复现官方 Android 手机客户端。
3. BiliSail 比 PiliPlus 更严格地要求 `card_goto=av`；但竖屏视频也能作为普通 `av` 返回，因此不能据此断言竖屏少的根因已经找到。
4. BiliSail 没有按视频宽高过滤竖屏，却未保留 feed URI 中的尺寸等方向信息；卡片封面固定 16:9，且会隐藏“竖屏”推荐理由。这可能降低列表中竖屏内容的辨识度，并不等于服务端实际返回得少。
5. 点击视频后的连续短视频流还存在独立的 `/x/v2/feed/index/story`。它与首页混排推荐应分别分析；不能把引入该接口当作首页竖屏比例问题的已证实修复。

## 核对版本

| 项目 | 核对快照 |
| --- | --- |
| 本机 BiliSail | HEAD `c8094f9b3e8884f7bb5578a36d8dffc9050f8707`，同时读取当前工作区；原有 API 重试相关修改保留 |
| 本机 PiliPlus | `936072449e82e3d90c28c728c0087bf5136fa441` |
| GitHub PiliPlus | [`c741279080fa90571d59ff9558640beb88861492`](https://github.com/bggRGjQaUbCoE/PiliPlus/commit/c741279080fa90571d59ff9558640beb88861492) |
| BiliPai | [`885a0c052e0d0da473dbda08ea79016b057e0123`](https://github.com/jay3-yy/BiliPai/commit/885a0c052e0d0da473dbda08ea79016b057e0123) |
| Bilibili-Gate | [`7edc62a55b19032f5225e89a3955d487ec31df33`](https://github.com/magicdawn/Bilibili-Gate/commit/7edc62a55b19032f5225e89a3955d487ec31df33) |
| bilimiao | [`eff134d715c3fd13202ebd029261d1fbc33d2171`](https://github.com/10miaomiao/bilimiao2/commit/eff134d715c3fd13202ebd029261d1fbc33d2171) |
| PiliPala | GitHub `main` 的实现，作为历史对照；不将其实现视为当前在线可用性证明 |

## 接口与关键参数

以下均为上述相同 App feed 端点。`appkey` 是参与签名的 query 参数，`app-key` 是 HTTP header；名称相近，但不能混为一项。

| 实现 | 客户端参数 | 刷新、翻页与其他差异 |
| --- | --- | --- |
| BiliSail / PiliPlus | `mobi_app=android_i`、`platform=android`、`build=8430300`、`device=phone`、`column=2`、`flush=8` | `idx=0,1,2…`；首请求 `pull=true`，之后 `false`；HD query key `dfca71928277209b`；UA 为 HD 2.0.1 / build 2001100 |
| BiliPai 手机分支 | `mobi_app=android`、`device=android`、`build=8130300`、`column=4`、`flush=5` | `pull=1/0`、`autoplay_card=11`、`ps=refreshCount`；根据凭证使用 Android key `1d8b6e7d45233436` 或 TV key `4409e2ce8ffd12b8` |
| BiliPai HD 分支 | `mobi_app=android_hd`、`device=pad`、`build=2001100`、`column=4`、`flush=5` | `pull=true/false`；HD key `dfca71928277209b`；`statistics.appId=5 / version=2.0.1`；`guidance=0`、`https_url_req=0` |
| Bilibili-Gate | `platform=ios`、`mobi_app=iphone`、`device=pad`、`build=90300100`、`c_locale=s_locale=zh-Hans_CN` | `actionKey=appkey`；`idx=当前秒数 + 100×递增偏移`；请求拦截器使用 TV key `4409e2ce8ffd12b8` 与可选 token；未设置上述 `column/flush` |
| bilimiao | `mobi_app=android_hd`、`platform=android`、`build=1450000`、`channel=bili`、`device=pad`、`column=4`、`flush=5` | `idx=0` 为刷新；HD key `dfca71928277209b`；公共参数构建器附加 token、mid、statistics、ts 与签名；调用方使用这些默认值 |
| PiliPala | `device=pad`、`device_name=vivo`、`column=4`、`flush=5` | 显式发送 `idx`、`pull=true/false`、`device_type=0`、TV key `4409e2ce8ffd12b8` 和可选 token；该函数未显式声明 `mobi_app/build` |

参数来源：[PiliPlus feed](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/c741279080fa90571d59ff9558640beb88861492/lib/http/video.dart#L116)、[PiliPlus constants](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/c741279080fa90571d59ff9558640beb88861492/lib/common/constants.dart#L7)、[BiliPai 手机参数](https://github.com/jay3-yy/BiliPai/blob/885a0c052e0d0da473dbda08ea79016b057e0123/app/src/main/java/com/android/purebilibili/data/repository/HomeFeedRequestPolicy.kt#L29)、[BiliPai HD 分支](https://github.com/jay3-yy/BiliPai/blob/885a0c052e0d0da473dbda08ea79016b057e0123/app/src/main/java/com/android/purebilibili/data/repository/VideoRepository.kt#L809)、[Gate feed](https://github.com/magicdawn/Bilibili-Gate/blob/7edc62a55b19032f5225e89a3955d487ec31df33/src/modules/rec-services/app.tsx)、[Gate 签名拦截器](https://github.com/magicdawn/Bilibili-Gate/blob/7edc62a55b19032f5225e89a3955d487ec31df33/src/request.tsx#L140)、[bilimiao feed](https://github.com/10miaomiao/bilimiao2/blob/eff134d715c3fd13202ebd029261d1fbc33d2171/bilimiao-comm/src/commonMain/kotlin/com/a10miaomiao/bilimiao/comm/apis/HomeApi.kt#L13)、[bilimiao 公共参数](https://github.com/10miaomiao/bilimiao2/blob/eff134d715c3fd13202ebd029261d1fbc33d2171/bilimiao-comm/src/commonMain/kotlin/com/a10miaomiao/bilimiao/comm/network/ApiHelper.kt#L138)、[PiliPala feed](https://github.com/guozhigq/pilipala/blob/main/lib/http/video.dart#L83)。

这些取值不能直接解释成“竖屏开关”。本轮没有找到可保证首页竖屏比例的参数，也没有对 `flush/column/guidance` 等字段进行控制变量实测。

## BiliSail 与 PiliPlus 的具体差异

### 请求身份基本对齐

本项目当前请求见 [AppRecommendationClient](../packages/bili_api/lib/src/clients/app_recommendation_client.dart)、[AppProfile](../packages/bili_api/lib/src/app_profile.dart) 与 [requestAppJson](../packages/bili_api/lib/src/api_client.dart)。

- feed 的 query、签名 key、HD UA、`statistics={appId:1, platform:3, version:8.43.0, abtest:""}` 与对照的 PiliPlus 实现一致。
- 经过 PiliPlus 账号拦截器覆盖后，最终 header 使用 `app-key=android64`、`x-bili-aurora-zone=sh001`。不能只看请求函数中先写入的 `app-key=android_hd`；本项目已经按最终结果对齐。
- 两者均有 `buvid`，并使用固定占位的 `fp_local/fp_remote/session_id/trace` 字段；本项目在有效同账号 token 存在时添加账号 header。字段存在不等于复现了官方运行时指纹或会话。
- GitHub 当前 PiliPlus 从 `Accounts.get(.recommend).buvid` 取得设备标识，并在账号对象中保存 buvid；本机旧快照仍从 `LoginHttp.buvid` 取得。本项目是内部持久化的独立设备标识，token 还需匹配当前账号和设备。真实标识值没有、也不应与其他应用共用。[当前 PiliPlus buvid 与账号](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/c741279080fa90571d59ff9558640beb88861492/lib/utils/accounts/account.dart#L64)

因此，继续只补同一套 PiliPlus 固定请求头，尚无证据能解决本次推荐分布差异。BiliPai 按凭证类型选择请求配置，比单独替换 UA 或 `mobi_app` 更有参考价值；但其实现仍需在线验证，不能直接推导为本项目换用即可成功。

### 响应接纳范围不同

| 实现 | 源码中的主要接纳／过滤规则 |
| --- | --- |
| BiliSail | 仅接收 `card_goto=av`、无 `ad_info`、`can_play=1`，随后验证内容身份与标题 |
| PiliPlus | 排除 `ad_av/ad_web_s`、有 `ad_info`、`can_play!=1`，以及黑名单和用户设置；没有统一要求 `card_goto=av` |
| BiliPai | 支持 `av/bangumi/picture`，排除广告；模型未以 `can_play=1` 为统一门槛 |
| Bilibili-Gate | 排除广告、banner、live 和缺少 `player_args` 的普通 av；没有以 `card_goto=av` 作为唯一入口 |

来源：[本项目解析](../packages/bili_api/lib/src/clients/app_recommendation_client.dart)、[PiliPlus 过滤](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/c741279080fa90571d59ff9558640beb88861492/lib/http/video.dart#L94)、[BiliPai 模型](https://github.com/jay3-yy/BiliPai/blob/885a0c052e0d0da473dbda08ea79016b057e0123/core-data/src/main/java/com/android/purebilibili/data/model/response/ListModels.kt#L721)、[Gate 过滤](https://github.com/magicdawn/Bilibili-Gate/blob/7edc62a55b19032f5225e89a3955d487ec31df33/src/modules/rec-services/app.tsx)。

严格过滤可以解释“支持的内容类型更少”。要解释“竖屏更少”，还必须查看原始响应：竖屏也可能是普通 `av`，不能把视频方向与 `card_goto` 类型直接等同。没有原始分布统计时，不应直接放开所有可播放卡片；番剧、图文和特殊卡片各有不同导航身份。

### 方向信息与显示方式

BiliPai 会从 feed `uri` 中的 `player_width/player_height` 等信息计算 `isVertical`，并保留到列表模型；本项目当前映射没有保留这些字段。[BiliPai 方向映射](https://github.com/jay3-yy/BiliPai/blob/885a0c052e0d0da473dbda08ea79016b057e0123/core-data/src/main/java/com/android/purebilibili/data/model/response/ListModels.kt#L819)

本项目 [VideoCard](../lib/shared/ui/video_card.dart) 固定封面 `aspectRatio=16/9`。此外，`recommendationReason` 为“竖屏”时仅清除文案，不删除视频；PiliPlus 也清除此文案。这些行为影响表现和识别，不能作为服务端竖屏比例低的证据。

本项目[过滤设置](../lib/domain/recommendation_settings.dart)默认最短时长为 0，也没有方向屏蔽规则。若用户保存了最短时长，短内容可能被过滤；本轮未检查实际保存值，不能假定已启用。

### App 来源不等于 App 账号推荐

本项目[身份仓储](../lib/features/feed/data/app_recommendation_identity_store.dart)只有在有效 App token 属于当前 Web 账号时，才附加 `access_key`；没有 App token 时使用游客推荐。密码／短信得到 Web Cookie，不自动产生 App token，相关边界见[统一登录设计](../docs/unified-login-design.md)。

本次没有读取用户安全存储，因此无法判断当前安装实际是账号推荐还是游客推荐。这是与官方 App 比较前需要确认的条件，不能用“Web 已登录”代替检查。

## 首页与 Story 连续短视频流

[API-collect 的原始提交](https://github.com/SocialSisterYi/bilibili-API-collect/blob/23617955e249e81f7285b3f3afa9d98f6cd192cc/docs/video/recommend.md#L1146)记录了 `GET https://app.bilibili.com/x/v2/feed/index/story`，其用途是点击视频后的短视频播放列表，入口上下文含 `aid/bvid`，分页使用 `display_id`；文档还列出 `spmid/from_spmid/story_param/video_mode` 等字段，其中多项语义仍标为未知。响应模型含 `dimension/owner/stat`，文档示例类型包括 `goto=vertical_av`。

该记录来自历史协议文档，本轮没有在线测试。不能把文档中的未知字段解释为已确认的竖屏比例控制项。本项目和核对的 PiliPlus 首页函数均调用普通 feed；PiliPlus 另有空间 story cursor 端点，它也不是这个首页点击后的 Story 端点。

如果体验差异指的是“首页就缺少竖屏视频”，先检查普通 feed 的原始数量、解析丢弃量与账号身份。如果指的是“点击后上下刷短视频”，则涉及另一个推荐流程。

## 建议的后续验证顺序

1. 确认当前 App 推荐身份是否确有有效、同账号 App token；只记录布尔状态，不导出凭据。
2. 在一次明确的只读抽样中，统计服务端原始卡片类型、可播放标记、可信尺寸或 URI 方向线索，以及各解析／用户过滤步骤丢弃的数量。先判断内容是服务端未返回、解析丢弃，还是显示时难以辨认。
3. 如果服务端返回分布就是不同，再在凭证兼容的前提下比较完整客户端配置；保持账号与设备标识稳定，交替抽取多页，记录去重前后数量。不要把 HD token 随意搭配另一套手机签名 key，也不要从单页随机推荐作结论。
4. 根据统计决定是补充已知视频卡适配、保留方向元数据，还是调整请求配置。若要连续短视频体验，独立设计 Story 流，不自动将其混入首页。

本轮交付为源码比较与调查路径；没有修改推荐策略，没有新增自动遥测，没有执行账号反馈或播放上报，也没有进行 Flutter 构建、设备运行或竖屏比例测量。
