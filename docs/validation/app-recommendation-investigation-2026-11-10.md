# App 推荐有效性与第三方实现对照

日期：2026-11-10。关联 [issue #107](https://github.com/CKopoer/BiliSail/issues/107)：Android、originOS 7、`1.2.8+5`，反馈切到 App 来源后仍像 Web 推荐；issue 没有可用截图、日志、登录方式或 App 身份状态。

调查阶段仅核对和验证；随后按用户要求同步 PiliPlus 的空参数签名修复，实施结果见文末。未修改登录流程、设置、凭据或依赖，未提交 issue 评论。工作区基线 `b78f7b809548b86eec1f840b64047e86f91dd48f`，开始时干净。发布标签 `v1.2.8+5` 指向 `5703519f5aefb62282604f8106767982ee50d188`；来源设置、推荐控制器、推荐仓储、身份仓储、统一登录、App profile 和 App 推荐客户端与该修复前基线没有差异。通用 `api_client.dart` 另有评论等无关更新，本次涉及的 App 请求及首页推荐方法未变。

## 结论与证据强度

1. **App 推荐接口目前可用，来源切换在代码和定向离线测试中有效。** 本机使用当前 API 实现的游客只读请求，实际到达 `app.bilibili.com/x/v2/feed/index`，首屏、翻页、再次刷新均为 HTTP 200、业务码 0。本次与 Web 的两页样本没有 BV 重合；这是单次样本，不能推导所有账号、设备和时间都不重复。
2. **发现并同步修复了空参数签名兼容问题。** 修复前空字符串参数在本应用签名原文中写成裸 key，当前 PiliPlus 写成 `key=`。推荐请求固定包含 `splash_id=''`，因此差异不是仅存在于理论输入。本应用此前沿用了 PiliPlus 2026-11-03 修复之前的规则，原测试也固定了旧行为。但游客接口连故意无效的签名都接受，不能以游客成功证明账号签名正确，也不能认定该差异已经造成 #107。
3. **发现一个确定的说明与实际身份不一致。** 设置写“正常登录后自动使用账号推荐”，实际只有取得有效、同账号 App token 的登录才使用账号 App 推荐。密码、短信及仅含 Cookie 的旧会话继续用游客 App 推荐。设计允许这种行为，但现有说明容易让已登录用户误认为 App 推荐也已个性化。
4. **尚未复现 issue 所述的“选择 App 实际仍请求 Web”。** 没有发现 App 失败后降级调用 Web 的路径；来源变化会取消旧请求并清空推荐索引，不跨来源拼接保留内容。未在反馈者手机或真实账号上抓取运行请求，因此不能直接关闭 issue，也不能把登录方式假设当作根因。

## 本应用完整请求路径

来源设置经 [推荐设置组件](../../lib/features/settings/presentation/recommendation_settings_section.dart)、`SettingsController`、[推荐偏好 Provider](../../lib/shared/application/recommendation_filter_provider.dart) 进入 [查询身份 Provider](../../lib/features/feed/application/app_recommendation_identity.dart)。

[FeedController](../../lib/features/feed/application/feed_controller.dart) 监听 `(source, identityRevision)`：变化时清空推荐索引、反馈及页码，取消旧请求；在推荐频道立即刷新，在其他频道只使推荐缓存失效。`_loadPage` 在 `source=app` 时调用 `AppRecommendationFeedRepository.loadAppRecommendations`，不满足能力或请求失败时报告错误，没有 Web fallback。首次来源切换不会把 Web 旧卡片作为 App 刷新保留内容。

[组合根](../../lib/app/dependencies.dart) 实际注入带 `appRecommendationIdentity` 的 [ApiFeedRepository](../../lib/features/feed/data/api_feed_repository.dart)。仓储取身份后调用 [AppRecommendationClient](../../packages/bili_api/lib/src/clients/app_recommendation_client.dart)，最终走 [BiliApiClient.requestAppJson](../../packages/bili_api/lib/src/api_client.dart)：

| 来源 | 实际 host / path | 身份 | 响应列表 |
| --- | --- | --- | --- |
| Web | `api.bilibili.com/x/web-interface/index/top/feed/rcmd` | Web Cookie、WBI | `data.item` |
| App | `app.bilibili.com/x/v2/feed/index` | 独立 buvid、App 签名、可选 `access_key`；不带 Web Cookie | `data.items` |

两种来源继续使用同一套 Flutter 卡片 UI。卡片外观、发布时间或内容题材不能作为请求来源的可靠判据；切换 App 来源也不承诺与官方 App 在另一设备上的同一账号得到逐条相同的列表。

## 与当前 PiliPlus 的具体差异

本机只读参考快照 `4fce4bb5a35c425aee759ef9263352316a29e355`；同时核对 GitHub 当前源码 `cab0114a21ce7fad5b90b9a4d788d35d313d25f9`。只比较协议、数据流及行为，没有复制 GPLv3 应用代码或资源，也没有修改相邻仓库或 Pub 缓存。

### 请求及卡片接纳基本一致

[PiliPlus 首页请求](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/http/video.dart#L137) 与本项目均使用 `build=8430300`、`mobi_app=android_i`、`platform=android`、`device=phone`、`column=2`、`flush=8`、`disable_rcmd=0`、`recsys_mode=0`、相同 statistics，以及 `idx=0/pull=true` 起始请求。PiliPlus [控制器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/pages/rcmd/controller.dart) 同样在刷新时归零；本项目的 `page - 1` 没有引入相对它的页码偏移。

[PiliPlus profile](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/common/constants.dart) 同样组合 Android HD UA 与上述 feed 参数，不应仅凭 UA / `mobi_app` 名称不同就认定本项目用了错误 profile。核对 [账号拦截器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/utils/accounts/account_manager/account_mgr.dart#L44) 后，最终 `app-key=android64`、`x-bili-aurora-zone=sh001`、referer、有效 token 的 `access_key` 注入和签名时机也基本一致。

本项目 buvid 首次生成后持久化，格式与 PiliPlus `XY` 加校验字符及 32 位十六进制主体一致；没有每次刷新随机设备标识。广告、`ad_info` 和 `can_play!=1` 的排除规则与当前 PiliPlus 相同。本项目已接纳有有效身份的非 av 卡片，并保留原始类型与导航目标，不再仅靠 `card_goto=av` 限定整个 App 推荐列表。

### 调查发现：空参数签名未跟进上游

[AppProfile.sign](../../packages/bili_api/lib/src/app_profile.dart) 修复前的排序编码逻辑使空参数成为：

```text
本项目修复前：...&splash_id&statistics=...&ts=...
PiliPlus 当前：...&splash_id=&statistics=...&ts=...
```

不同原文会生成不同 MD5。PiliPlus 的 [ca6161e「fix AppSign」](https://github.com/bggRGjQaUbCoE/PiliPlus/commit/ca6161ecaa88d9a84e480a2a7622dafdd7414c29) 于 2026-11-03 明确移除了空字符串的特殊分支；[当前签名器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/utils/app_sign.dart) 对空字符串也保留等号。本项目原 [签名测试](../../packages/bili_api/test/app_recommendation_client_test.dart) 反而把 `empty` 的裸 key 固定进预期摘要，因此当时测试通过不能消除这一问题。

此次随后同步修复签名规则，并为含空字符串的实际 feed query 加入独立期望；继续覆盖中文、空格、百分号及单次编码。保持已固定的 appkey / token 来源，不通过更换 appkey、随机 buvid 或混入 Web Cookie 掩盖问题。账号请求的实际表现仍需验证。

### App 接口来源与账号个性化是两个维度

[SessionRepository](../../lib/features/auth/data/session_repository.dart) 的正常扫码从 HD auth_code / poll 取得 Cookie 和 App token，并验证两者 UID 一致。密码 / 短信的 `completeWebLogin` 仅提交 Web Cookie，不取得 App token；旧版仅 Web 安全快照恢复也不会自动兑换。

[身份仓储](../../lib/features/feed/data/app_recommendation_identity_store.dart) 只有同账号有效 token 才返回 `accessToken` / `accountMid`。没有 token 时仍请求 App 接口，但身份为游客；已有 token 过期或被拒绝时报告重新登录，不静默回退游客或旧 token。

| 登录情况 | Web 推荐 | App 推荐 |
| --- | --- | --- |
| 游客 | 游客 | 游客 App feed |
| 密码 / 短信 Web 登录、仅 Cookie 的旧会话 | 当前账号 | 游客 App feed |
| 正常 HD 扫码且同账号 App token 有效 | 当前账号 | 当前账号 App feed |
| App token 已过期 / 失效 | 取决于 Web Cookie 是否仍有效 | 认证错误，提示重新登录 |

设置组件的“正常登录后自动使用账号推荐”没有表达上述差别。[身份摘要](../../lib/features/settings/presentation/app_recommendation_identity_settings.dart) 虽会显示游客 / 账号，但没有解释为何已登录仍是游客。建议明确“扫码登录取得 App 凭据后使用账号推荐；密码 / 短信及旧 Web 会话可能仍使用游客推荐”，并以摘要说明当前身份。

保持既有[统一登录约定](../unified-login-design.md)：本次没有重新引入推荐专属扫码、更新登录入口或 Cookie 换 token。当前 `signIn` 对已登录会话直接返回；在现有流程下，只有 Web 会话的用户若要取得 App 凭据，需要退出后重新使用正常扫码登录，不能仅以“已登录”判断已完成 App 授权。

## 其他客户端的公开实现

以下是核对到的公开源码快照，不代表所有第三方客户端，也不以公开源码推断最新安装包行为；PiliPala、BiliYou 的源码明显较旧，主要作为不同接入方式的对照。未对这些客户端进行真实账号在线验收。

| 客户端与快照 | 推荐实现 | 凭据与参数特点 |
| --- | --- | --- |
| [PiliPlus `cab0114`](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/http/video.dart#L137)，2026-11-10 | 可选 App / Web / desktop；App 为 `/x/v2/feed/index` JSON | 推荐用途账号、buvid、可选 App token；拦截器注入 `access_key` 并签名；phone / 两列 profile |
| [PiliPala `06f23f6`](https://github.com/guozhigq/pilipala/blob/06f23f67ca61f22db42ebabd9b979b2c2f4fa808/lib/http/video.dart#L77)，2025-05-14 | 独立 Web 和 App 推荐函数，App 同样为 feed/index | App 函数读取本地 `accessKey`，`loginStatus=false` 可不带账号；pad / 四列、`flush=5`，使用其 [TV appkey](https://github.com/guozhigq/pilipala/blob/06f23f67ca61f22db42ebabd9b979b2c2f4fa808/lib/common/constants.dart) |
| [bilimiao2 `c77c78a`](https://github.com/10miaomiao/bilimiao2/blob/c77c78a276b1d992db85064c39d61ccaff0db0dd/bilimiao-comm/src/commonMain/kotlin/com/a10miaomiao/bilimiao/comm/apis/HomeApi.kt)，2026-11-09 | 首页调用 App feed/index；也保留 Web 推荐入口 | [ApiHelper](https://github.com/10miaomiao/bilimiao2/blob/c77c78a276b1d992db85064c39d61ccaff0db0dd/bilimiao-comm/src/commonMain/kotlin/com/a10miaomiao/bilimiao/comm/network/ApiHelper.kt) 默认 HD appkey/profile，注入 token / mid 并签名；pad / 四列 |
| [BiliYou `ea34e1a`](https://github.com/lucinhu/bili_you/blob/ea34e1a06b6947e62473a107454d0f273a391498/lib/common/api/home_api.dart)，2023-08-26 | 所核首页实现为 Web WBI 推荐 | [API 常量](https://github.com/lucinhu/bili_you/blob/ea34e1a06b6947e62473a107454d0f273a391498/lib/common/api/api_constants.dart#L30) 指向 `/x/web-interface/wbi/index/top/feed/rcmd`，`feed_version=V3`；HTTP 层 CookieManager 管理 Web 会话 |
| [wiliwili `88e5876`](https://github.com/xfangfang/wiliwili/blob/88e5876bea9502d06f46a8656e3530684d3aaf7d/wiliwili/source/api/home_api.cpp)，2026-04-25 | 所核首页实现为 Web / 桌面参数推荐 | [Recommend 常量](https://github.com/xfangfang/wiliwili/blob/88e5876bea9502d06f46a8656e3530684d3aaf7d/wiliwili/include/api/bilibili/api.h#L124) 为 Web WBI feed；`plat=1`、`feed_version=V1` / `CLIENT_SELECTED`、布局参数等 |

bilimiao2 的[首页调用方](https://github.com/10miaomiao/bilimiao2/blob/c77c78a276b1d992db85064c39d61ccaff0db0dd/bilimiao-compose/src/commonMain/kotlin/cn/a10miaomiao/bilimiao/compose/pages/home/content/HomeRecommendContent.kt#L78) 用最后一张卡片的服务端 `idx` 继续请求，本项目与 PiliPlus 用递增计数。此处属于不同分页策略；当前对照中本项目翻页和刷新均取得新样本，没有证据表明计数策略会把 App 来源变成 Web 来源。

这些实现说明：没有统一的“第三方 App 推荐算法”，主要是在 B 站服务端接口、客户端 profile、账号 token、设备标识和本地过滤之间选择组合；客户端运行在 Android 上并不代表首页一定使用 App feed。没有依据要求本项目改为 gRPC 或整套换成另一客户端的参数才能取得 App 推荐。

## 本次实际验证

### 游客只读在线对照

本节保留修复前的调查结果，不能作为修复后的账号验收。

临时探针和脱敏结果分别位于本机 `build/issue-107/recommendation_probe.dart`、`build/issue-107/guest-probe.jsonl`，均在 Git 忽略目录。探针使用本次新生成且只驻留内存的设备标识，不读取应用数据库、系统安全存储、真实账号、原设备设置或相邻客户端数据；只发 GET，不执行扫码、推荐反馈、观看上报或其他账号写操作。日志仅含 host / path、数量、状态及身份字段是否存在，不输出 query、token、Cookie、buvid、标题、原始响应或播放 URL。

| 请求 | HTTP / 业务码 | 原始卡片数 | 本项目接纳数 | 结果 |
| --- | --- | ---: | ---: | --- |
| 当前实现 App 首屏：`idx=0,pull=true` | 200 / 0 | 12 | 11 | App host，未附加 Cookie 或 access_key |
| 当前实现 App 翻页：`idx=1,pull=false` | 200 / 0 | 10 | 10 | 与首屏无 BV 重合 |
| 当前实现 App 再次刷新：`idx=0,pull=true` | 200 / 0 | 10 | 10 | 与前两次均无 BV 重合 |
| 对照：空值按 `key=` 签名及编码，App 首屏 / 翻页 | 均 200 / 0 | 各 10 | 各 10 | 可读，但游客成功不能证明账号效果 |
| 对照：故意无效的全零签名，App 首屏 | 200 / 0 | 10 | 10 | 本次游客端点没有以该签名拒绝请求 |
| 当前实现 Web 第一 / 二页 | 均 200 / 0 | 各 20 | 各 20 | Web host，与上述 App 样本均无 BV 重合 |

当前首屏 12 张原始卡片均标记 `av`，其中 11 张被接纳；探针没有输出剩余卡片的拒绝细项，不能进一步将其归因于某一字段。Web 为获取 WBI key 而读取 nav 返回业务码 -101，这是无账号探针的预期状态，不代表 App 接口失败。

此对照验证本机网络上的 API 可达性、列表解析和分页行为，不验证反馈者 Android 安装包的实际请求、不验证真实账号 App token 是否有效，也不衡量推荐质量或与官方 App 的账号兴趣一致程度。刻意错误签名的样本只用于确认本次成功的证明边界，不用于生产回退。

### 离线行为验证

调查阶段在修复前工作区执行并通过 52 项现有定向测试：

```powershell
# packages/bili_api：22 项
dart test test/app_recommendation_client_test.dart test/read_retry_timeout_test.dart -r expanded

# 根应用：30 项
flutter test --no-pub test/features/feed/app_recommendation_source_test.dart test/features/feed/app_recommendation_identity_test.dart test/features/feed/api_app_recommendation_cards_test.dart test/features/settings/app_recommendation_settings_test.dart test/features/auth/unified_login_test.dart test/features/feed/api_feed_repository_test.dart -r expanded
```

覆盖来源切换及旧响应取消、隐藏频道、身份变化、游客隔离、同账号 token 的请求传递、密码 / 短信仅 Web 会话、失效不回退、App 卡片映射、签名当时契约及有限重试。当时签名测试仍验证旧空参数规则，其通过不代表已跟进上游修复。

调查阶段没有运行全量检查或构建、安装、Android UI 实测、真实扫码 / 账号个性化、反馈 / 撤销及性能测量；签名修复后的检查记录见文末，没有把游客结果、离线 fixture 或既往发布验收替代设备与账号验收。

## 后续处理建议

1. 空参数签名规则和对应回归已同步，仍须验证真正带同账号 App token 的请求；游客响应不能替代这项验收。
2. 校正设置说明，明确接口来源和推荐身份两个状态，保留既有统一登录边界。
3. 复现 #107 时先核对登录方式、设置中的“当前使用游客 / 账号推荐”、推荐过滤及刷新保留状态，再核实运行时实际请求的来源、身份字段是否存在、HTTP / 业务码、原始 / 接纳卡片数。只记录这些脱敏状态，不索取或输出凭据。
4. 若反馈者确为有效扫码账号仍异常，再以同一账号、相近时间对照 PiliPlus 的有效请求；在取得证据前，不以内容相似、共享卡片 UI 或本机游客成功判定 issue 已修复。

## 同步空参数签名修复

按用户后续要求，在本项目独立实现 PiliPlus `ca6161ecaa88d9a84e480a2a7622dafdd7414c29` 的同等修复：`AppProfile.sign` 对每个参数均编码 `key=value`，空字符串也保留等号。修改只影响包含空值参数的签名原文，不改变推荐端点、凭据来源、Cookie 隔离、设备标识、分页或反馈重试规则。

- 先把原签名用例的 `empty` 期望改为 `empty=`，在旧实现上观察到预期失败，再修改签名器；修复后该用例通过。
- 实际首页请求回归增加首屏及翻页的固定签名向量，覆盖 `splash_id=''`、同账号 fixture token、固定时间戳和完整 query。向量由独立编码输入计算，不通过被测签名器生成期望。
- 修复后 `dart test test/app_recommendation_client_test.dart -r expanded` 的 14 项通过，格式检查及修改文件的 `dart analyze` 通过。
- 修复后另做两次游客只读在线烟测，首屏 / 翻页均为 HTTP 200、业务码 0，接纳 12 / 11 条；探针确认两次实际请求均为 App host，签名与保留空值等号的独立计算一致，没有 access_key 或 Cookie。临时探针和脱敏输出为本机 `build/issue-107/post_fix_smoke.dart`、`build/issue-107/post-fix-smoke.jsonl`；仍不读取已有账号或设备数据，也不能替代账号验证。
- 根 `tool/check.ps1 -SkipPub` 全部检查通过：根应用 5012、bili_api 835、bili_player 367、bili_danmaku 161、bili_mux 5，共 6380 项 Dart / Flutter 测试通过，格式、全量静态分析和打包边界脚本通过。根应用 13 项 Windows 符号链接用例受权限条件限制跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，工具脚本另有 2 项因缺少 `make` 跳过；不将跳过计为原生验证通过。完整日志保留在本机 `build/issue-107/signature-check.log`。
- 文档相对链接、源码路径和 `git diff --check` 通过，未更改依赖或锁文件。
- DTD 探测无运行中的调试应用，热重载调用也返回未连接，未完成热重载。未进行构建、安装或真实账号 / Android 设备验收，不能据本次协议修复声称 #107 已在设备上解决。
