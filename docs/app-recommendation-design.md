# App 推荐接入设计

日期：2026-10-27。承接[推荐流设置](recommendation-settings-design.md)，本轮接入 App 来源、独立 buvid、可选 App 授权和服务端反馈，保留原 Web 来源及已保存设置。

2026-10-28 后续调整：App 凭据已并入正常扫码登录，推荐设置不再提供独立扫码或更新登录入口。密码/短信继续保存 Web 会话，已删除 Cookie 换 token 流程；所有登录方式都可选择 App 来源，无 App 凭据时使用游客推荐，有效同账号凭据才使用账号推荐。设置只显示当前推荐身份摘要，并移除设备标识显示、手工编辑和随机生成入口；设备标识继续由内部自动生成并持久化，保留已有值。当前职责与验证见[统一登录设计](unified-login-design.md)。下文初次接入的独立授权方案及验证保留为历史记录。

2026-10-31 请求身份对齐：继续只读参考下述 PiliPlus 精确提交的 `lib/common/constants.dart`、`lib/http/video.dart`、`lib/utils/login_utils.dart`，并核对 `lib/utils/accounts/account.dart`、`lib/utils/accounts/account_manager/account_mgr.dart` 和 `lib/utils/id_utils.dart` 对请求头的最终覆盖，只采用协议字段与设备标识格式，独立实现，不复制 GPLv3 应用代码或资源。App profile 使用相同的完整 Android HD UA；仅首页 App feed 补齐 `fp_local`、`fp_remote`、`session_id`、`x-bili-trace-id`、`x-bili-aurora-eid/zone`、`bili-http-engine`、`referer` 请求头，以及空 `splash_id` 参数。按拦截器处理后的最终值使用 `app-key=android64`、`x-bili-aurora-zone=sh001`；有有效同账号 App token 时，使用该 token 所属 mid 生成 `x-bili-mid` 和相应 aurora eid，游客不附带账号头。固定指纹/trace 占位字段与参考请求一致，不采集设备硬件指纹，也不改变实际 HTTP 传输实现。

新设备 buvid 使用安全随机 16 字节转成 32 位大写十六进制，在 `XY` 后依次放入该字符串零基下标 2、12、22 的字符，再拼接整个字符串，共 37 字符。首次生成后持久化；并发读取和重启复用同一值。已有合法 buvid 原样保留，不因本次对齐触发 token 失效；两应用各自持有设备标识，不读取或共用 PiliPlus 本地数据。Cookie 隔离、同账号 token、取消/epoch、重试和反馈单次写入边界保持原有约束。

2026-10-31 响应接纳范围对齐：只读核对 GitHub PiliPlus `c741279080fa90571d59ff9558640beb88861492` 的 `lib/http/video.dart`、`lib/models/home/rcmd/result.dart` 与 `lib/common/widgets/video_card/video_card_v.dart`，仅参考协议与行为，独立实现，不复制 GPLv3 应用代码。首页 query 与最终请求头已一致，本次保留现有取值，并增加完整 query、首请求与翻页的回归测试。响应取消仅接纳 `card_goto=av` 的限制；与参考一致排除 `ad_av`、`ad_web_s`、有 `ad_info` 及 `can_play!=1` 的卡片，继续校验字段类型、数字身份、标题及响应容量，应用层仍使用用户已有过滤偏好。

API 卡片保留原始 `card_goto`、`param` 和可解析 URI。普通 av 继续用 player_args.aid／param 转换 BV；非 av 不将 param 冒充 aid 或转换 BV。主应用为非 av 使用 `app:<type>:<param>` 列表标识，不作为有效 VideoId 传入视频操作：番剧按 param 打开既有剧集页面；已识别的原生视频／影视／直播 URI 使用既有路由，动态映射到公开网页，允许的 Bilibili HTTPS 内容链接交由既有外链端口；未知或非法跳转仍保留卡片并提示暂不支持。非 av 不显示普通视频稍后再看菜单、不启动 AV 悬停预览。App 反馈及撤销携带原始 param 与 goto，不再固定为 av；服务端原因、同账号 token、epoch、单次写入与未知结果不重放规则不变。没有接入 Story 推荐或改变封面比例。

本轮验证结果见文末“响应接纳范围对齐验证”；前面的请求身份对齐验证记录为同日较早一轮。

本次验证：36 项定向测试通过，覆盖实际请求头/签名、账号 mid 传递、游客隔离、非法账号头拒绝、新设备生成/并发读取/重新加载和旧设备/凭据保留。`tool/check.ps1 -SkipPub` 全部检查通过，日志 `build/app-recommendation-profile-check-2026-10-31.log`：根应用 3749、bili_api 499、bili_player 105、bili_danmaku 145、bili_mux 5，共 4503 项通过；根应用 13 项 Windows 符号链接用例及未设置 `BILI_MUX_LIBRARY` 的 10 项 mux 原生用例跳过，不计为原生验证。文档相对链接与 `git diff --check` 通过。

使用本次 API 实现做显式启用的游客只读在线烟测，返回 12 条可播放 App 推荐；脱敏日志 `build/app-recommendation-profile-smoke-2026-10-31.log` 仅含数量/分页状态，不读取已有账号、设备配置或安全存储。未构建/安装应用，未做真实账号个性化、反馈或三端实机验收；没有运行中的调试应用/DTD，热重载未能执行。游客读取成功不代表真实账号推荐效果一致。

## 参考核对与采用边界

只读参考本机 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441`：

- `lib/http/video.dart`：App feed 参数、广告/可播放卡片过滤、App 反馈与撤销。
- `lib/utils/accounts/account_manager/account_mgr.dart`、`lib/utils/app_sign.dart`、`lib/common/constants.dart`：请求 profile、排序编码签名、可选 access_key。签名发生在拦截器，不能只移植请求函数。
- `lib/models/home/rcmd/result.dart`、`lib/utils/id_utils.dart`、`lib/utils/num_utils.dart`：aid 本地转换、统计缩写、cid/时长、关注理由和 three_point_v2。
- `lib/pages/rcmd/controller.dart`、`lib/common/widgets/video_popup_menu.dart`：刷新/翻页索引与服务端反馈原因。
- `lib/http/login.dart`、`lib/utils/login_utils.dart`、`lib/utils/storage_pref.dart`：TV/HD 二维码授权及独立设备标识。此快照声明了 Cookie 转 token 端点，但未发现实际调用；本轮不假设 Web Cookie 已具有 App access_key。

只借鉴协议与行为，独立实现 Dart，不复制 GPLv3 应用源码/资源、不增加相邻运行时依赖，不采用其全局服务、宽泛错误日志或无限重试。

核对参考 `pubspec.yaml` 与 `pubspec.lock`：crypto 约束 `^3.0.6`、实际锁定 3.0.7，dio 约束 `^5.9.1`、实际锁定 5.11.1。media-kit 原生 Git overrides 仍锁在 core `73771ec38176be2d984a3049c28177bce23b54a0`、video `fd8421d21eade4d6d12de137fa7df902fec20292`，本任务不采用这些依赖；BiliSail 复用既有 crypto、Dio、qr_flutter 和安全存储，不改依赖/锁文件。

## 模块职责

1. `bili_api` 增加 App 签名/profile、App 推荐客户端及小型 DTO；`BiliApiClient` 增加严格端点白名单的 App 传输入口。App 请求不附带 Web Cookie，不接收重定向，不把 App host 加入通用 Web 白名单。查询只编码一次；读请求共用已有 deadline/最多三次传输预算，反馈即使使用 GET 也只尝试一次。响应 2 MiB、最多 100 张卡片；解析跳过广告、不可播放或无有效身份的卡片，接纳非 av 并保留其真实类型与导航身份。
2. API 内本地转换 aid/bvid，不按卡片查询详情；解析可信字段，缺失点赞保持未知，不从含糊推荐理由提取点赞数。Web 关注状态继续只认明确字段；App 对精确“已关注/新关注”理由提供与 PiliPlus 一致的豁免语义。保留反馈原因的类型和 ID，不臆造 reason_id。
3. `RecommendationSettings` 增加 `source=web/app`，缺失/非法值及恢复默认统一为 Web，保留现有用户行为。设备 buvid 由独立身份仓储保存为本机设备偏好，不作为 Web Cookie，不跟随过滤恢复默认随机改变。
4. `AppRecommendationIdentityRepository` 为纯 Dart 端口；data 实现负责设备标识、安全凭据和授权 attempt。buvid 首次使用生成并持久化，支持手工修改和随机；修改成功后清除与旧设备绑定的 App 授权并发出身份版本更新。账号凭据仅在独立 `CredentialStore` 加密槽保存，不进入 AppSettings、普通数据库、日志、fixture 或导出；对外状态只提供 buvid、授权账号/期限和版本。
5. App 授权通过设置中的明确扫码动作启动。复用已有 qr_flutter/Material 模态样式，通过 PiliPlus 同类 TV/HD auth_code -> poll 取得 token；不自动确认二维码、不调用未验证的 Cookie 授权写接口。必须与当前 Web 用户 mid 相同才保存，避免推荐账号与稍后再看/播放账号混淆；游客可直接使用 App 游客推荐。授权取消、超时、账号变更或新 attempt 均使旧结果失效。有效期到期/认证失效给出重新授权状态，不悄悄将已授权请求重放成游客请求。
6. `ApiFeedRepository` 作为适配层映射 App DTO；用可选能力接口扩展 FeedRepository，不破坏其他列表或现有 fake。领域反馈上下文显式区分 Web/App，App 由服务端原因列表选择，再提交给原反馈控制器并保留精确撤销上下文。
7. `FeedController` 继续拥有推荐索引、分页、过滤和旧内容保留。来源或 App 身份版本变化时取消推荐读写、清空该来源的推荐/反馈上下文与页码；正在展示推荐时刷新，隐藏推荐仅标记待加载，不触发隐藏网络任务。新旧来源不拼接旧内容。其他频道和滚动状态保留。
8. 设置新增来源选择、设备标识编辑和 App 授权状态；推荐卡继续使用现有菜单、Sliver 和局部反馈订阅。App 反馈弹出当前卡片服务端返回的原因，不复用 Web reason_id；未知写入结果继续禁止自动重放。

## 生命周期和性能约束

- 默认 Web 不增加 App 网络请求；只有首次访问 App 身份/设置或 App 推荐时读取设备/凭据，本地读取单飞。签名与映射仅每页执行，不增加每帧工作、全列表 Widget 缓存或逐视频补请求。
- UI 授权轮询由模态拥有，二维码有效两分钟、最多 60 次轮询、单次传输一次尝试；进入后台暂停并取消在途轮询，回到前台后检查有效期再继续，离开模态立即取消。没有常驻计时器。账号变化立即隔离旧 token 和请求，凭据操作串行，迟到持久化不得恢复已登出账号。
- 继续使用既有双空页预算、稳定 ID 去重和分块索引；服务端有卡但全部是广告/过滤项时保留分页机会，最终由已有无新增预算阻止自动无限翻页。
- 过滤、buvid、来源、授权状态分开订阅；无关设置不刷新推荐。授权/设备/来源变化不重建播放器或其他首页频道。

## 验证与交付

API fixture 覆盖签名编码、无 Cookie/重定向、deadline/取消/epoch、写请求单次、aid 转换、统计/身份/广告边界、反馈原因与二维码结果。主应用测试覆盖安全保存失败、错误账号、取消/登出/迟到结果、设备切换、来源切换（含隐藏频道及在途请求）、过滤/分页/反馈兼容。复用既有卡片重建/虚拟化测试，执行根 `tool/check.ps1 -SkipPub`。

在线仅进行不带真实账号的 App 推荐只读烟测；测试不自动扫码、提交推荐反馈或操作真实账号。真实扫码授权、个性化、反馈成功和三端帧耗时分别列为现场验收，不能用游客读取与 fixture 通过替代。

## 实施入口与当前验证

- [App profile](../packages/bili_api/lib/src/app_profile.dart)、[推荐协议](../packages/bili_api/lib/src/clients/app_recommendation_client.dart)、[扫码协议](../packages/bili_api/lib/src/clients/app_passport_client.dart)、[ID 转换](../packages/bili_api/lib/src/video_identifiers.dart)保持纯 Dart，公共入口显式导出。
- [身份端口](../lib/features/feed/domain/app_recommendation_identity_repository.dart)、[身份仓储](../lib/features/feed/data/app_recommendation_identity_store.dart)、[统一会话仓储](../lib/features/auth/data/session_repository.dart)、[设置组件](../lib/features/settings/presentation/app_recommendation_identity_settings.dart)分别负责领域契约、持久化/会话、模态轮询、界面交互；通过 `lib/app/dependencies.dart` 组合，未增加全局 service locator。
- 设置快照 schemaVersion 为 30，SQLite schema 为 3。设备标识在 `app-recommendation-device.v1`；普通 DB 的 `app-recommendation-authorization-revoked.v1` 仅为撤销标记。加密槽前缀 `bilisail.app_recommendation.v1`；先写撤销标记，再写凭据，最后提交有效标记。取消、账号变化或存储失败时清理新凭据；即使删除失败，重启也不能恢复已撤销槽。
- 新增 [API 测试](../packages/bili_api/test/app_recommendation_client_test.dart)、[身份/反馈测试](../test/features/feed/app_recommendation_identity_test.dart)、[来源/取消测试](../test/features/feed/app_recommendation_source_test.dart)、[设置界面测试](../test/features/settings/app_recommendation_settings_test.dart)，覆盖安全保存/删除失败、错误账号、重启恢复、过期/失效授权、在途取消/登出、设备变化、隐藏频道和单次反馈等边界。
- 2026-10-27 使用当前 API 包执行不带账号凭据的只读烟测：12 条可播放 App 推荐、60 个服务端反馈原因，12 个 aid/bvid 本地转换一致；单条公开 Web 详情交叉核对通过。交叉核对只用于烟测，生产列表不补查详情。输出仅为数量/布尔状态，日志 `build/app-recommendation-online-smoke.log` 不含请求 query、设备标识、二维码 key 或凭据。
- 尚未进行真实账号扫码、个性化结果及反馈/撤销在线验收，也未运行三端 Profile/Release 帧耗时测量；不把游客 smoke、fixture 或卡片局部更新测试当作这些项目通过。

## 初次接入自动检查（统一登录之前）

`tool/check.ps1 -SkipPub` 通过，日志 `build/app-recommendation-check-final.log`：格式、静态分析与打包边界检查通过；根应用 3180、bili_api 487、bili_player 83、bili_danmaku 93、bili_mux 5，共 3848 项测试通过。根应用 13 项 Windows 符号链接用例、mux 10 项缺少 `BILI_MUX_LIBRARY` 的原生用例跳过，不能算作原生通过。

本轮新增 API 8 项、主应用 21 项行为测试；含设置来源即时保存、设备编辑校验/取消/随机、二维码模态取消与前后台暂停恢复。既有推荐追加零重建、同 ID 更新、反馈/撤销、分页触底和保留页面回归通过。7 份相关文档的相对链接及 `git diff --check` 通过。未构建/安装 Flutter 应用；工作区已有及同期修改按任务范围保留。

## 响应接纳范围对齐验证（2026-10-31）

- 33 项定向测试通过：API profile／签名／广告与非 av 接纳／反馈 12 项，仓储内容身份与 URI 映射 2 项，卡片导航 5 项，来源隔离与已有反馈回归 14 项。新增用例验证完整首页 query、同数字身份不同卡片类型不互相覆盖、番剧 param 与 player_args.aid 分离、原始 goto／param 反馈及撤销、未知卡片保留、非法链接不转成 AV 请求。
- `tool/check.ps1 -SkipPub` 全量通过，日志 `build/app-recommendation-acceptance-check-2026-10-31.log`：格式、静态分析与打包边界脚本通过；根应用 3836、bili_api 536、bili_player 105、bili_danmaku 145、bili_mux 5，共 4627 项 Dart／Flutter 测试通过。根应用 13 项 Windows 符号链接用例及未设置 `BILI_MUX_LIBRARY` 的 10 项 mux 原生用例跳过，不计为原生通过。
- 未构建／安装应用、未使用真实账号请求推荐或提交反馈，未测竖屏比例、三端运行与性能。DTD 探测未发现调试应用，热重载调用返回无连接，未完成热重载验证。
- 文档相对链接与 `git diff --check` 通过；依赖、锁文件、设备标识和安全凭据未更改。
