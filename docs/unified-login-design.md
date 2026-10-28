# 统一 Web / App 登录

日期：2026-10-28。取代 App 推荐的独立扫码授权，由既有 SessionRepository 统一拥有 Cookie、App token 和登录提交。

## 协议与职责

- 只读参考 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `http/login.dart`、`pages/login/controller.dart` 和账号拦截器，独立实现。HD 扫码成功结果是顶层 token 字段与 `cookie_info.cookies`，兼容有明确 token_info 的响应；不能仅使用之前测试虚构的嵌套结构。
- 普通扫码使用 HD auth_code / poll，一次扫码同时取得 Cookie 和 App token。密码/短信继续复用内嵌官网，在隔离 Cookie/nav 校验后保存 Web 会话，不发起 App 授权、确认或轮询请求。2026-10-28 经真实旧会话探测失败后，按用户要求删除 Cookie 换取 App token 的实现。
- API 包解析 Cookie 的域、path、secure、有效期和数量/长度，允许的 Cookie 只归属 bilibili.com HTTPS；扫码回传 token 时，nav.mid 必须与 token.mid 匹配。App 推荐请求继续不携带 Web Cookie。
- SessionRepository 在既有凭据串行队列内写一份 version=2 的安全快照，再提交内存会话；`app` 字段可选，网页登录不写入虚构 App 凭据。保留 generation、取消、账号清理和失败回滚。version=1 的已有 Web 会话可恢复；新旧 Web 会话都不执行凭据转换，也不提供“更新登录”入口。
- 通过 auth/domain 的纯 Dart 凭据端口供 data 层读取 App token，UI 只获取是否可用的摘要。推荐身份仓储继续管理 buvid 和旧安全槽兼容读取；统一凭据优先，即使失效也不回退旧 token。修改设备标识使对应 token 失效，通过正常流程重新登录。
- 移除推荐设置的独立扫码入口、授权控制器和授权 attempt 接口。App 来源始终可选；没有 App 凭据时使用游客推荐，已有同账号的有效凭据才使用账号推荐。密码/短信取得的 Web 登录不能单独证明账号 App 推荐可用。推荐反馈仍要求有效 App 凭据、显式点击和单次写入。

## 验证

覆盖真实结构的 HD 双凭据响应、Cookie 作用域、nav/token UID 一致、新旧快照恢复、可选 App 凭据的安全保存/回滚、取消/登出/迟到写入、内嵌官网登录不触发 App 授权、Web 登录后的游客 App 推荐及失效隔离。执行定向测试后运行根 check.ps1 -SkipPub。真实账号和设备验收与离线契约分开记录。

## 实施入口

- [扫码客户端](../packages/bili_api/lib/src/clients/app_passport_client.dart)同时解析顶层/嵌套 token，返回有界且校验过的 Cookie 模型；只保留用户扫码所需的生成和轮询接口，移除 `exchangeWebSession` 及 API 客户端的 `confirmAppLogin`。
- [统一会话仓储](../lib/features/auth/data/session_repository.dart)继续拥有唯一登录 generation、Cookie jar、凭据队列和账号提交。两种登录在 nav 验证、安全快照保存及旧账号任务清理后才进入 signedIn；仅扫码回传 token 时校验 UID 一致性和 token 有效期。App token/refresh token、过期时间、buvid 和失效标记只进入系统安全存储。
- [纯 Dart 凭据端口](../lib/features/auth/domain/app_session_credentials.dart)只供数据层使用。[推荐身份仓储](../lib/features/feed/data/app_recommendation_identity_store.dart)继续保存设备标识并按当前账号隔离旧槽；冷启动期间读到的旧 token 在 Web 账号恢复确认前不可用，避免丢失有效旧授权，也不跨账号暴露。统一 token 优先，过期/失效时不回退旧槽或游客。
- [推荐设置](../lib/features/settings/presentation/app_recommendation_identity_settings.dart)显示“当前使用游客推荐。”或“当前使用账号推荐。”；App 凭据失效时提示重新扫码登录，读取失败提供重试。2026-10-28 按用户要求移除设备标识显示、手工编辑和随机生成入口；内部继续自动生成并持久化设备标识，保留已有值。独立授权控制器、attempt 端口和扫码模态已删除；不存在“更新登录”入口。
- [API 回归](../packages/bili_api/test/unified_login_test.dart)保留扫码的 token/Cookie 解析与边界测试，删除兑换相关用例；[统一登录回归](../test/features/auth/unified_login_test.dart)覆盖扫码与仅 Web 登录、持久化恢复及 Web 登录后的游客 App 推荐，[旧槽与设备测试](../test/features/feed/app_recommendation_identity_test.dart)覆盖冷启动恢复、账号隔离、统一凭据优先、设备变更及旧槽删除失败。设置 Widget 验证游客/账号/失效三种提示以及设备入口不外显。

真实账号 HD 扫码、官网密码/短信提交和设备构建/运行验收仍未完成。公开源码和 fixture 证明实现与离线契约；真实旧版 Cookie 交换失败记录见下文，相关实现已删除。

## 初次统一登录检查（2026-10-28，删除兑换逻辑之前）

`tool/check.ps1 -SkipPub` 通过，日志 `build/unified-login-check-commit.log`：根应用 3185、bili_api 495、bili_player 83、bili_danmaku 109、bili_mux 5，共 3877 项测试通过，格式/静态分析及打包边界检查通过。Windows 符号链接 13 项、未配置 `BILI_MUX_LIBRARY` 的原生 mux 10 项跳过，不计为原生通过。数量为检查时整个工作区，含同期其他任务的已有测试，不将其列为本任务新增。

相关 7 份文档的相对链接和 `git diff --check` 通过。提交范围限于统一登录、推荐身份适配、相关 API/测试与文档，窗口、弹幕性能、版本及其他文档改动保留在工作区。

## 真实旧版 Cookie 交换探测（2026-10-28）

按用户明确授权，使用本机 `build/windows/x64/runner/Release/bilisail.exe`（文件版本 `1.2.2+0`）对应的 Windows 安全存储会话测试 Cookie 换取 App token。通过系统 DPAPI 在内存读取已有 `bilisail.web_session.v1` 双槽，不导出凭据、不改写登录或设置；测试使用临时设备标识，返回凭据仅允许驻留内存。探测程序与脱敏日志保存在本机 `build/validation/`，不进入常规 CI，也不提交真实响应或凭据。

- 读到的安全快照为 version=1，未含 App 凭据；`/x/web-interface/nav` 返回 HTTP 200、业务码 0，登录有效，账号与保存的会话一致。
- 发往 passport 确认路径的 Cookie 包含 `SESSDATA`、`bili_jct`、`DedeUserID` 和 `DedeUserID__ckMd5`，只记录这些字段是否存在，不记录值。
- 使用探测时的 `AppPassportClient.exchangeWebSession`：`/x/passport-tv-login/qrcode/auth_code` 返回 HTTP 200、业务码 0；随后 `/x/passport-tv-login/h5/qrcode/confirm` 返回 HTTP 200、业务码 -101，流程在确认阶段失败。该兑换实现现已删除。
- 另生成一次新的 auth_code，在仅用于探测的传输适配器中将确认请求改为 Android App UA、`build=8430300`、`scanning_type=1`；确认阶段仍返回 -101。两次确认均为单次提交，没有重放结果不明的写请求。
- 两次均未取得 App token，未执行后续已登录 App 推荐读取。原安全存储文件前后 SHA-256 相同，没有覆盖或清除旧版登录；不输出 Cookie、二维码 key、token、账号 ID、请求 query 或原始响应正文。

结论仅限于本机这份旧版会话和上述两种请求：Web 会话有效，但 Cookie 换取 App token 未成功。不能据此承诺旧用户可自动补齐 App 凭据，也不能将 -101 推断成所有 Cookie 交换方式均已失效。探测时密码／短信登录依赖同一交换路径，后续清理已移除此依赖；本次没有真实扫码、验证码、账号退出或新登录验收。

探测 Dart 文件定向静态分析通过；生产代码未变更，未重新构建或安装客户端。

## 移除设备标识设置入口（2026-10-28）

按用户要求删除设置中的 buvid 显示、编辑弹窗与随机生成入口，保留推荐来源选择、登录摘要和读取失败重试。内部设备标识的生成、保存和已有值均不变，不触发凭据清理或重新授权。

现有设置 Widget 回归改为验证来源即时保存、设备标识不外显、原设备值不变及登录提示保留，定向运行通过。`tool/check.ps1 -SkipPub` 通过，日志 `build/remove-app-device-setting-check.log`：根应用 3235、bili_api 495、bili_player 83、bili_danmaku 116、bili_mux 5，共 3934 项测试通过；格式、静态分析和打包边界检查通过。Windows 符号链接 13 项、未配置 `BILI_MUX_LIBRARY` 的原生 mux 10 项跳过，不计为原生通过。相关三份文档相对链接和 `git diff --check` 通过；未重新构建、安装或进行设备界面验收。

## 提示简化与兑换路径清理（2026-10-28）

设置仅按实际 App 凭据显示游客、账号或失效状态，移除长段说明和账号 ID 展示。删除 API 的 Cookie 授权确认方法、扫码客户端的 Web 会话兑换方法以及 SessionRepository 中的调用；密码/短信 Web 登录经 nav 验证即可保存，不再申请 App 设备身份或等待 token。version=2 快照允许缺少 `app`，扫码的双凭据校验、安全保存、取消与回滚行为保留。

定向主应用 50 项、API 13 项回归通过，覆盖 Web 登录无 App 授权请求、无 CSRF 时仍可验证登录、新快照恢复及实际推荐仓储使用游客身份读取 App 推荐，同时验证 App 请求不携带 Web Cookie 或伪造 token。原兑换测试和 fake 分支已删除。

最终 `tool/check.ps1 -SkipPub` 通过，日志 `build/recommendation-login-cleanup-check.log`：根应用 3235、bili_api 492、bili_player 83、bili_danmaku 116、bili_mux 5，共 3931 项测试通过。格式、静态分析和打包边界检查通过；Windows 符号链接 13 项、缺少 `BILI_MUX_LIBRARY` 的原生 mux 10 项跳过。相关八份文档相对链接和 `git diff --check` 通过。未重新构建、安装或提交真实密码/短信、扫码登录，在线验收边界仍保留。
