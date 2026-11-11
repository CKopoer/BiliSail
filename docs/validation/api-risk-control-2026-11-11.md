# Web 设备上下文与请求风控

日期：2026-11-11。用户报告每周必看出现请求限制，本轮扩展共享 HTTP 管线，不只修改单期列表。

## 来源与采用范围

只读核对相邻 PiliPlus 提交 `cab0114a21ce7fad5b90b9a4d788d35d313d25f9`：

- `lib/http/video.dart` 的热门精选：WBI、`web_location=333.934`、浏览器 UA、官网 Origin 和页面 Referer。
- `lib/utils/accounts/account.dart`、`lib/http/init.dart`：SPI 的 `b_3/b_4`、设备 Cookie 和设备激活端点。
- `lib/http/search.dart`、`lib/http/validate.dart`、`lib/utils/request_utils.dart`：`v_voucher` 表示需要验证；Gaia 注册、用户完成极验、返回验证 token 是独立流程。当前搜索入口的 `RequestUtils.validate` 调用已注释，实际返回“触发风控”，不能称其自动完成验证。

PiliPlus 应用为 GPLv3；本轮只参考协议字段和职责，独立实现和编写测试，未复制应用代码、随机画布指纹、证书绕过或资源，未修改相邻仓库、Pub 缓存或依赖。

## 请求预防

组合根为共享 `BiliApiClient` 及隔离的扫码／登录候选 client 启用 `prepareWebRequests`，注入同一 `WebDeviceStore` 读取／保存。首次 Web 请求在自己的 deadline 内等待设备上下文，然后发送业务请求。API 包独立调用默认不增加隐式预请求；自定义 transport 可显式开启，供 fixture 和其他集成使用。

设备上下文按当前 Cookie、独立安全存储、服务器 SPI 的顺序复用；缺失完整标识才请求新标识，不每次随机生成。成功激活并安全保存后写入当前 CookieJar，Web 读、表单／JSON／上传写入、WBI、PGC 和直播共享它；直播连接发现先准备同一上下文，避免另起 SPI 生成不同身份。

| 端点 | Profile／参数／响应／重试 |
| --- | --- |
| GET `api.bilibili.com/x/frontend/finger/spi` | Web，无 WBI／CSRF／分页；JSON `data.b_3/b_4`，仅接受可安全写入 Cookie 的有限长度字符串；每个初始化单飞一次，失败不在内部重试 |
| POST `api.bilibili.com/x/internal/gaia-gateway/ExClimbWuzhi` | Web 设备 Cookie，JSON `payload` 字符串；`3064=1`、`39c8=333.1007.fp.risk`、真实 OS `3c43.adca`；仅接受 HTTP 200、业务 `code=0`，每次初始化只发送一次，不伪造画布指纹 |

初始化拥有独立取消信号和最多 client timeout 的期限，各调用者保留自己的 deadline／取消。取消一个等待者不影响其他等待者。账号 epoch／CookieJar 清空或恢复使旧初始化失效，旧响应不能写入新会话，旧清理不能清除新单飞；关闭 client 取消初始化。

独立安全存储槽 `bilisail.web_device.v1` 只存 `buvid3/buvid4/b_nut`，不存账号凭据或验证票据；登出不删除该安装身份。存储失败不回退普通文件或 SQLite。设备 Cookie 保持 `.bilibili.com`、`Path=/`、Secure 作用域，不发送到外域。账号凭据仍沿用原安全会话槽。

普通 Web 请求统一使用浏览器 UA／Origin，保留空间专属 Referer；期数目录、每周单期和入站必刷从普通 GET 改为现有 WBI 管线，并添加对应页面上下文。App／TV 请求保持原 profile，不加入 Web Cookie，不触发 Web 设备初始化。

## 响应与恢复

- HTTP 412／429、业务 `-352/-412/-509/-799` 归为限流／风控；HTML 412 也能识别。小型响应在 HTTP 重试／DTO 解码前检查，避免进入网络或播放内容不可用重试。
- 顶层或 `data/result` 内非空 `v_voucher` 即使伴随 `code=0`，也表示需要验证，不能解析为空列表／成功写入，也不作为 WBI key 失效重新签名。PGC 独立解码路径同步分类。
- `ApiFailure` 保留端点、HTTP 状态、业务码、`retryAfter` 和 `requiresVerification`，不保存／打印 voucher、验证码 token 或服务端原始消息。
- `Retry-After` 支持秒数与 HTTP 日期；无效／缺失时默认 30 秒。冷却按 session epoch、host、path 记录，忽略 query，最多 128 项；过期移除，账号切换清空。再次刷新直接返回剩余时间，不发网络请求。设备激活受限时，也在下一次 SPI 前检查冷却。
- 风控失败停止本次自动重试；点赞、投币、收藏、发布、消息、上传等原有写入仍只发送一次，不因风控自动重放。设备准备失败也不会继续发送业务写请求。
- 界面区分等待冷却与需要安全验证，提示官网检查登录／完成验证后显式重试。取消／旧账号优先于风控，不建立旧账号冷却。

本轮没有新增应用内 Gaia／极验交互或把官网验证 token 转移到应用。设备绑定验证码仍需用户验证，不能保证仅在外部浏览器验证即可解除应用限制；不自动破解或切换账号／网络绕过限制。

## 验证与边界

新增 fake transport／clock／安全存储测试覆盖分类、成功外壳验证码、WBI 不误重签、HTML 412、Retry-After、冷却范围与到期、账号隔离、写入不重放、App Cookie 隔离、设备单飞／取消／超时／关闭／旧响应、稳定身份恢复、非法 Cookie 拒绝及安全存储失败。热门测试更新为验证签名和页面上下文，继续检查单期业务拒绝不重试。

公开游客烟测不导入账号凭据或已有 Cookie，仅获取并激活服务器分配的设备标识，再读取目录和单期，不执行账户写操作。官网浏览工具未取得 SPI 响应，随后普通 HTTPS 取得 SPI／激活 `code=0`，并用实际 Dart `BiliApiClient(prepareWebRequests: true)` 验证完整链路：目录 397 期、最新单期 50 个视频。首次 Dart 抽样发现 `buvid4` 包含 Base64 的 `+`、`/`，已修正校验，并增加 `+ / =` 保留及注入拒绝回归。日志只输出状态／数量／字段形状，不保存真实设备标识。

该抽样只代表本机网络、该时间的游客请求成功，不证明其他账号／网络／端点都不会风控。按用户要求不构建应用安装包、不安装、不做实机或性能验收；登录态和设备 UI 由用户后续构建确认。

原生播放器 CDN、下载字节传输、第三方服务与 WebSocket 消息不具有 Web API JSON／WBI 契约，本轮不强行添加设备激活或自动重放；直播连接参数获取仍经过共享 API 管线。

检查结果：`tool/check.ps1 -SkipPub` 通过，根应用 5142 项通过／13 项跳过，player 372 项、danmaku 161 项通过，mux 5 项通过／10 项跳过（未配置 `BILI_MUX_LIBRARY`，不代表原生通过）。最后补充 Base64 fixture 后，重新执行 API 包全量测试，886 项通过；根静态分析、API 包静态分析、最终文件格式与文档链接检查通过。
