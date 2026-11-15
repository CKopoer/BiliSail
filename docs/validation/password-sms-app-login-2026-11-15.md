# 密码／短信登录取得 App 与 Web 双凭据

日期：2026-11-15。按用户要求，密码／短信入口改为 App Passport 登录，成功后统一保存 Cookie、App access／refresh token；删除推荐设置的来源说明和身份摘要。“官网登录”保留独立 Web 兼容路径；已有 Web 会话不自动转换或退出。

## 来源与依赖

只读对照 PiliPlus `217fb54f51f6764176319bbdedab2a7522d75401`（2.2.1）的 [login.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/http/login.dart)和[登录控制器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/login/controller.dart)。仅核对协议字段、顺序和分支，独立实现；未复制 GPLv3 应用代码、资源或控件，未修改相邻仓库。

RSA 使用项目已有的纯 Dart `pointycastle 4.0.0`（MIT），bili_api 增加同版本直接依赖及锁文件，无新原生库。密码拼接服务端 hash 后以 RSA PKCS#1 v1.5 加密；不保存原始密码。`dt` 和 `from_url` 按该 Passport profile 预编码，再对实际字段签名和执行表单编码，不把这一字段约定推广到其他 API。

验证码使用已有 webview_all 的独立临时会话，按 PiliPlus 当前 fullpage 流程获取极验配置并启动验证；初始化加载 `fullpage.0.0.0.js` 和 `gettype.php`，JSONP 使用极验支持的 `geetest_<数字>` 回调名。页面只接收 gt／challenge，桥接结果限制长度并校验 challenge／validate／seccode；不接收账号密码、App token 或主应用 Cookie。资源使用 HTTPS，阻止外部主页面导航。初版通用 gt.js／embed 实现已在本次反馈中替换，具体证据见文末修正记录。

## 端点登记

固定 host 为 `passport.bilibili.com`，JSON，无分页，不携带主账号 Cookie／旧 access_key。沿用 App HD UA、buvid、build=2001100、android_hd profile。GET 在单次 25 秒 deadline 内最多 3 次只读尝试；所有 POST 单次提交，结果不明不重放。整个登录尝试有效期 10 分钟。

| method / path | 鉴权／签名及结果 |
| --- | --- |
| GET `/x/passport-login/web/key` | 无签名，取得 hash／RSA PEM |
| POST `/x/passport-login/oauth2/login` | App MD5 签名、RSA 密码；双凭据／-105 验证码／status=2 手机验证 |
| POST `/x/passport-login/sms/send` | App 签名、cid／tel／login_session_id，可带验证 proof；captcha_key 或 recaptcha_url |
| POST `/x/passport-login/login/sms` | App 签名、cid／tel／code／captcha_key、设备 profile；双凭据 |
| GET `/x/safecenter/user/info` | 无签名、tmp_code；脱敏手机号和 tel_verify 能力 |
| POST `/x/safecenter/captcha/pre` | 无签名、无 Cookie 的 Web 注册；不带 App buvid／profile 请求头，校验 recaptcha_type；短信挑战缺字段时也从这里取得注册 |
| POST `/x/safecenter/common/sms/send` | App 签名、tmp_code／loginTelCheck／proof、官方验证 Referer；captcha_key |
| POST `/x/safecenter/login/tel/verify` | App 签名、tmp_code／request_id／source／captcha_key／code；一次性授权码 |
| POST `/x/passport-login/oauth2/access_token` | App 签名、authorization_code grant；双凭据 |

安全中心验证 URI 仅接受官方 Passport HTTPS host、标准端口、固定风险验证路径和完整参数。人机验证 URL 仅提取注册字段，接受当前服务端的 `www.bilibili.com` 和 Passport HTTPS host，不将地址作为导航／请求目标。原始响应、URL query 和 native 异常不进入界面错误文本。

## 实现与状态边界

- [协议客户端](../../packages/bili_api/lib/src/clients/password_sms_login_client.dart)处理密码加密、参数及验证分支；复用[扫码客户端](../../packages/bili_api/lib/src/clients/app_passport_client.dart)的 token/Cookie 严格解析。
- [会话仓储](../../lib/features/auth/data/session_repository.dart)持有 generation、隔离登录客户端、取消范围、SMS key、验证 URI 和凭据队列。页面通过[控制器](../../lib/features/auth/application/auth_controller.dart)与[领域端口](../../lib/features/auth/domain/password_sms_auth_repository.dart)操作，不请求网络或解析 DTO。
- 双凭据成功后，沿用隔离 Cookie jar 的 nav 校验、token UID 一致性、单份 version=2 安全快照及提交／回滚流程。账号不匹配、安全写失败、关闭／登出或迟到响应都不能遗留半套登录。旧 version=1 和可选 App 字段的 version=2 快照继续兼容，无 SQLite 迁移。
- [表单](../../lib/features/auth/presentation/password_sms_login_dialog.dart)只在点击时发短信，成功后 60 秒冷却；等待验证码允许后台查看短信。提交中进入系统后台取消本次尝试；关闭即刻使结果失效。成功或销毁时清空密码／验证码。
- 密码／短信按钮使用 App 流程，官网登录保留显式 Web 路径，扫码不变。推荐[设置](../../lib/features/settings/presentation/recommendation_settings_section.dart)保留来源选择与过滤，不再显示来源说明、游客／账号／失效摘要和身份重试入口。

## 验证

离线回归覆盖 RSA 解密校验、profile／签名、短信注册与验证码续接、绑定手机验证／授权码交换、发送不重放、URI／响应边界、取消及迟到响应、UID 不一致、安全写失败／取消回滚、双凭据立即用于 App 推荐与重启恢复。Widget 覆盖实际入口、验证码续接、显式短信发送／冷却、后台读短信、关闭后迟到结果、小屏／键盘／双倍字体；桥接测试覆盖缺字段、超量、换行与脚本注入。

公开只读在线检查：`GET /x/passport-login/web/key` 返回业务码 0，具有非空 hash 和 PUBLIC KEY PEM；极验 `gt.js` 返回 HTTP 200。未输出公钥响应正文／hash，不读取或修改用户会话；可达性不代表真实账号登录通过。

`tool/check.ps1 -EnforceLockfile` 通过：五份锁文件可复现解析、格式、静态分析及打包边界检查通过；根应用 5550、bili_api 984、bili_player 333、bili_danmaku 161、bili_mux 5，共 7033 项离线测试通过。根应用 13 项、播放器 3 项按环境条件跳过，另 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生验证。补充收尾的 dt 字符集对齐后，协议文件分析与 12 项密码／短信 API 回归、格式检查通过；全量包测试也包含此改动。文档相对链接及 `git diff --check` 通过。完整日志为 `build/password-sms-app-check.log`。

真实密码提交、短信发送、账号风控验证码及各平台设备验收未执行；离线通过不能证明线上账号登录已验收。当前没有运行中的 DTD／调试应用，热重载工具返回无可连接应用。未构建或安装应用。

## 后续反馈：人机验证被误判及 fullpage 修正

同日用户反馈密码／短信提示“服务返回了暂不支持的数据”。本次在原未提交工作区继续修正，保留此前所有改动。

### 已复现的原因

- 使用无效的 `example.invalid` 测试账号发起隔离密码请求，服务端返回 HTTP 200、业务码 `-105`、`data.status=1`，并提供 `https://www.bilibili.com/h5/project-msg-auth/verify` 注册 URL。初版复用了只接受 Passport host 的安全中心 URL 校验，导致正常验证码响应被抛成 protocol 错误。未提交用户凭据，未尝试真实账号登录，未调用发送短信端点。
- 该密码注册的 `gettype.php` 在默认、Web 和 iOS 查询下均返回 success／fullpage。独立 `captcha/pre` 注册能解析出三字段，但其极验配置返回 `error_34`；“接口返回字段完整”并不能证明配置仍可使用。
- 只确认 gt.js 可下载不足以验证验证码兼容。对照 PiliPlus [fullpage 初始化](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/login/geetest/geetest_webview_dialog.dart)后，改为加载服务端配置、合并 HTTPS／bind 参数并在 ready 时调用 verify。独立 Edge 浏览器进一步验证发现，使用非兼容的自定义 JSONP 回调时浏览器报告 ORB 并终止加载；改为 `geetest_<毫秒时间戳>` 后真实滑块界面正常出现。

### 修正与边界

- 密码 `-105` 和成功包中的 `status=1` 作为验证码状态；兼容 url／recaptcha_url／完整注册字段，未知密码注册明确报告暂不可用，不用无关的 pre 注册替换其 token。
- 短信 `-105` 的 data 为 null、缺少／不完整注册字段时才使用 pre。已取得有效 captcha_key 且未要求验证时继续短信流程。短信登录和安全中心短信发送也保留验证码续接，不丢弃用户完成的 proof。
- 新增有类型的 success／cancelled／configurationUnavailable／loadFailed 桥接事件；不将正常验证、取消或配置失效混成“不支持的数据”，也不回显供应商原始错误／请求 query。
- 只有短信发送或绑定手机号验证允许配置失效后更新注册，整个 gt／challenge／token 一起替换，每次操作最多一次；刷新后仍不可用时明确提示重新登录／扫码。密码注册和短信登录提交不会混用新 token。取消后不能继续刷新或提交；网络错误不重放写入。
- [纯 Dart 页面生成与桥接解析](../../lib/core/platform/passport_captcha_page.dart)独立于[WebView 生命周期](../../lib/core/platform/passport_captcha.dart)。showPassportCaptcha 等待关闭动画、初始化和私有环境释放完成后才返回，避免 Android 共享 WebView store 尚未释放时自动打开下一次验证；等待有 10 秒上限。

### 本轮验证

浏览器插件连接超时后，使用 Playwright 的独立 Edge 会话加载本项目实际生成的 HTML，通过仅驻留内存的注册显示真实滑块；关闭验证返回 cancelled。加载失效的 pre 注册返回 configuration_unavailable。没有代填／完成人机验证，没有取得或保存真实账号凭据；这属于独立浏览器端验证，不等于 Flutter 原生视图／手机实机或最终登录成功验收。验证浏览器和本机临时 HTTP 服务均已关闭，日志只保留状态码、字段类型、host／path 与参数名，不保留注册值、Cookie、token 或完整 URL query。

定向 58 项离线回归通过，覆盖真实 www 响应形状、status=1、短信缺字段回退、密码注册不串用、短信 proof 续接、一次刷新／仍失效／取消、JSONP 回调协议、原生环境释放屏障与错误回传。

本轮 `tool/check.ps1 -SkipPub` 通过：格式、静态分析及打包边界检查通过；根应用 5561、bili_api 994、bili_player 333、bili_danmaku 161、bili_mux 5，共 7054 项离线测试通过。根应用 13 项 Windows 符号链接、播放器 3 项原生 EDL／倍速及 mux 10 项原生用例按环境条件跳过，后两类分别未配置 BILI_TEST_NATIVE_MPV／BILI_TEST_MEDIA_DIR 和 BILI_MUX_LIBRARY，不计为原生通过。文档相对链接及 `git diff --check` 通过，完整日志为 `build/password-captcha-fix-check.log`。

尚未构建安装、使用真实账号登录、发送短信或进行手机实机验收。无运行中的 DTD／Flutter 调试应用，热重载工具返回无可连接应用。

## 后续反馈：密码登录后的安全中心短信配置失效

用户已能通过密码登录的人机验证，但进入绑定手机号验证后，点击获取短信验证码提示配置失效。本轮继续保留此前未提交的登录与 WebView 修正。

### 原因与来源

重新核对 PiliPlus `217fb54f51f6764176319bbdedab2a7522d75401` 的 [preCapture／safeCenterSmsCode](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/http/login.dart)、[手机号验证流程](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/login/controller.dart)及通用请求默认头。PiliPlus 单独请求未签名的 Web captcha/pre，再把该注册的 token 与验证结果用于带签名的安全中心短信请求。本项目虽然已对 pre 取消签名，却仍统一附加 App buvid 和整套 profile 请求头。

无账号、无 Cookie 的在线对照确认：完整 App 请求头及仅含 App buvid 的请求均返回 `recaptcha_type=geetest4`，把该 ID 交给第三代 gettype.php 得到 `error_34`；移除 App 请求头后返回 `recaptcha_type=geetest`，配置为 `success/fullpage`。仅保留 App UA 或 app-key 的对照也返回第三代配置，说明本次差异由 buvid 请求头触发。第四代注册并非第三代配置过期；向同一来源反复申请不能解决协议不匹配。

同日读取 B 站[官方风险验证入口](https://passport.bilibili.com/h5-app/passport/risk/verify)所加载的 [9448.67a8703e.js](https://s1.hdslb.com/bfs/static/2233-monorepo/passport-h5/static/js/async/9448.67a8703e.js)，确认其按 recaptcha_type 分开处理 geetest／geetest4，并使用不同的 SDK、proof 字段。只借鉴公开请求契约及流程，独立实现；未复制 GPLv3 应用代码或官方脚本，未修改相邻仓库、依赖或 Pub 缓存。

### 修正

- captcha/pre 改用独立 Web 请求头，不带 App buvid／profile，不带 Cookie，不签名；实际短信发送、手机号确认及授权码交换仍使用原 App profile 和签名。
- 解析 pre 时检查 recaptcha_type，保留缺少该字段的旧响应兼容。显式返回 geetest4 或其他类型时报告验证类型不可用，不把 ID 送入第三代渲染器或误报为配置过期。
- 手机号验证仍在用户点击获取短信后才申请注册；完成这次独立人机验证后，才以匹配的 token／proof 和当前 tmp_code 发短信。密码阶段注册不复用；刷新仍最多一次，网络写入不自动重放。

### 验证边界

修正后的实际 PasswordSmsLoginClient 在线申请注册，再查询极验配置，确认字段完整、HTTP 200、status=success、type=fullpage。注册值仅驻留内存，结果日志只记录上述状态；没有真实账号凭据、短信发送或人机验证代填。

新增离线回归覆盖 Web 注册请求头／无签名、第四代及未知类型拦截，密码验证码通过后进入手机号验证、显式短信注册、整套注册刷新、proof／tmp_code／Referer 绑定、一次短信发送、授权码交换及双凭据保存。Widget 覆盖用户依次点击密码登录、获取短信、验证并登录的完整状态切换。

本轮 `tool/check.ps1 -SkipPub` 通过：格式、静态分析及打包边界检查通过；根应用 5568、bili_api 997、bili_player 333、bili_danmaku 161、bili_mux 5，共 7064 项离线测试通过。根应用 13 项 Windows 符号链接、播放器 3 项原生 EDL／倍速及 mux 10 项原生用例按环境条件跳过；后两类分别未配置 BILI_TEST_NATIVE_MPV／BILI_TEST_MEDIA_DIR 和 BILI_MUX_LIBRARY，不计为原生通过。文档相对链接及 `git diff --check` 通过，完整日志为 `build/safecenter-captcha-check.log`。

未重新构建安装或执行真实账号的最终短信登录验收；没有可连接的 DTD 调试应用，热重载工具返回无可连接应用。
