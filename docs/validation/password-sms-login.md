# 内嵌密码／短信登录与 Android 登录窗口

日期：2026-10-06。Flutter 3.47.6 / Dart 3.13.5，Windows x64 开发主机。真实账号与设备运行需要独立验收。

## 最终实现

- 原生扫码入口保留；“密码 / 短信登录”打开应用内的 [官网登录页](https://passport.bilibili.com/login)。密码、短信发送／倒计时、极验和额外安全认证由网站处理。按用户的精简要求，移除自维护的 RSA、短信 key 和验证码表单协议及 PointyCastle 依赖。
- WebView 使用隐私模式，不注入主应用 Cookie，禁用密码保存、自动填充、检查入口和插件事件日志。主 frame 只允许 Bilibili HTTPS 页面；验证码子 frame 由官网加载。没有自动填表、发送短信或跳系统浏览器。
- 只读取适用于 `https://api.bilibili.com/` 的 Cookie，保留 domain/path/secure/expiry。取得非空 SESSDATA 后进入隔离 Cookie jar，由 nav 校验账号，再写系统安全存储、清理旧账号任务、升级主会话。应用不接收网页中的密码／手机号／短信 code。
- Cookie 数量／长度受限，换行、NUL、分号注入、错误域／路径、过期会话被拒绝。安全写入、清理与升级在一个凭据队列操作中完成；取消时先回滚旧凭据，再允许新登录保存，避免旧回滚删除新账号。
- 网页等待最多 10 分钟，账号验证 deadline 为 25 秒。允许切到短信应用；后台期间不提取 Cookie，返回后恢复。关闭／销毁／登出使旧 attempt 失效；账号提交和 QR 轮询期间进入后台取消请求。验证失败保留可重试提示。
- Android 登录窗口由固定宽度、不可滚动的 AlertDialog 内容改为 Dialog + Flexible + SingleChildScrollView，受路由可用宽高约束；二维码最大 220，随内容宽度缩小。标题／关闭按钮独立于滚动区，内容随键盘避让，小屏、横屏和放大文字下可滚动到操作按钮。

## 协议边界

| 所属 | Host / Method / Path | 鉴权、重试与边界 |
| --- | --- | --- |
| 官方网页 | `passport.bilibili.com` HTTPS `/login` | 网站负责密码、短信、极验及额外认证；表单 POST 不由 bili_api 实现或自动重放 |
| 应用账号校验 | `api.bilibili.com` GET `/x/web-interface/nav` | 隔离 Web Cookie；无签名、JSON、无分页；复用有界读重试和 cancellation；有效账号且安全落盘后才启用会话 |
| 原生扫码 | `passport.bilibili.com` GET `/x/passport-login/web/qrcode/generate`、`/poll` | 保留原实现，共用安全提交；取消、过期和迟到结果受 generation 约束 |

不增加 App／TV token，不把 Cookie 写入普通 JSON、日志、测试 fixture 或设置导出。测试中的会话均为假的 fixture 值。

## 参考来源

- bili-kernel 提交 `e26f6dbd071e20d4220806fcff7bd675f3c29fc5`：[BiliApis](../../../bili-kernel/src/BiliKernel.Abstractions/Bili/BiliApis.cs) 有密码公钥和 App OAuth 常量，没有完整密码／短信客户端调用；[TVAuthorizeClient](../../../bili-kernel/src/Authorizers/Authorizers.Tv/Core/TvAuthorizeClient.cs) 提供 TV 扫码实现。
- biliuwp-lite 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0`：[AccountApi](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/AccountApi.cs)、[LoginVM](../../../biliuwp-lite/src/BiliLite.UWP/Modules/User/LoginVM.cs)、[LoginDialog](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Dialogs/LoginDialog.xaml)、[bili_gt.html](../../../biliuwp-lite/src/BiliLite.UWP/Assets/GeeTest/bili_gt.html) 包含密码／短信／极验的 App 协议和交互。只读参考职责，不迁入 App token 链，不复制源码、22/33 图或 gt.js。
- dart_simple_live dev 提交 `bccd2ba2e77bc34b3e3a0897f1cb5e0b402afd2b`：[web_login_page.dart](https://github.com/xiaoyaocz/dart_simple_live/blob/bccd2ba2e77bc34b3e3a0897f1cb5e0b402afd2b/simple_live_app/lib/modules/mine/account/bilibili/web_login_page.dart)、[web_login_controller.dart](https://github.com/xiaoyaocz/dart_simple_live/blob/bccd2ba2e77bc34b3e3a0897f1cb5e0b402afd2b/simple_live_app/lib/modules/mine/account/bilibili/web_login_controller.dart)、[account_controller.dart](https://github.com/xiaoyaocz/dart_simple_live/blob/bccd2ba2e77bc34b3e3a0897f1cb5e0b402afd2b/simple_live_app/lib/modules/mine/account/account_controller.dart)。同样用 flutter_inappwebview 承载官网并读取 Cookie，但入口只对 Android/iOS 开放，桌面提供扫码／手动 Cookie。本工程独立编写适配和安全提交，不复制 GPL-3.0 源码，也不采用参考中的明文 Cookie 保存与日志。

## 原生依赖

固定 [flutter_inappwebview 6.2.0-beta.3](https://pub.dev/packages/flutter_inappwebview/versions/6.2.0-beta.3)，Apache-2.0。稳定版 6.1.5 的旧 ProGuard 配置无法通过本工程 AGP 9.1.0；[维护方 beta.3 更新记录](https://pub.dev/packages/flutter_inappwebview/versions/6.2.0-beta.3/changelog)包含 AGP 9 修正。实际解析版本提交到根锁文件。

- Android 使用系统 WebView，要求支持 `GET_COOKIE_INFO`，以读取完整 Cookie 元数据；不支持时提示更新系统 WebView 或改用扫码，不能凭空扩大 Cookie 作用域。
- macOS 使用 WKWebView；本轮未在 macOS 构建或运行。
- Windows 使用 WebView2 Runtime，缺失时显示安装／扫码提示。保留 Loader 是内嵌网页所需的原生加载依赖，不因把极验交给官网而消失。
- Windows 构建使用 NuGet；本机把官方 NuGet CLI 6.14.0 加入构建进程临时 PATH，没有修改全局 PATH。插件固定 WebView2 SDK `1.0.3650.58`、WIL `1.0.250325.1`、CppWinRT `2.0.250303.1` 和 nlohmann.json `3.12.0`。
- 工程显式安装插件导入的 WebView2Loader.dll，补齐此 beta 包遗漏的 bundled-libraries 声明。WebView2 Microsoft BSD 类许可、WIL／CppWinRT 的 MIT 和 WIL notices 从对应 NuGet 包随产物复制；nlohmann.json 的 MIT 来源见 [第三方声明](../../THIRD_PARTY_NOTICES.md)。它们位于 Windows 产物 `data/licenses/webview`，不能用插件 Apache-2.0 替代。
- 固定 Windows 平台包 `0.7.0-beta.3` 的 CookieManager 直接返回 CDP 的秒级 expires，应用适配器将它转换为毫秒；Android／WKWebView 保留原毫秒语义。升级插件时需要重新核对该边界，[平台测试](../../test/core/platform/passport_web_login_test.dart)覆盖两种单位、会话 Cookie 和元数据缺失。

## 验证

- [会话测试](../../test/features/auth/web_login_test.dart) 覆盖 Cookie 作用域与有效期、伪造／过期 attempt、迟到 nav、账号拒绝、安全存储部分写入、登出时落盘回滚，以及清理旧账号时取消后再登录。保留 [原扫码与恢复测试](../../test/features/auth/session_repository_test.dart)。
- Widget 测试验证网页登录结果进入安全提交、关闭后迟到结果被丢弃、查看短信后返回、失败提示保留，以及 `320×568` / `640×360`、两倍文字、0／220 像素键盘占位下按钮可滚动到达。它们不执行真实网页表单。
- `tool/check.ps1 -SkipPub` 通过：根应用 781 项、bili_api 249 项、bili_player 16 项、bili_danmaku 32 项，共 1078 项；四处格式检查和静态分析通过。最后增加超时后拒绝迟到 Cookie 的保护后，登录与平台相关 40 项测试及局部静态分析再次通过。总数包含工作区其他同期改动的测试。
- 使用工程字体／主题渲染查看 `320×568` 的入口与二维码、`640×360` 两倍文字横屏，关闭按钮可见，横屏内容可滚动；这属于 Widget 渲染，不替代设备验收。8 份修改文档的相对文件链接和 `git diff --check` 通过。
- `flutter build apk --release --target-platform android-arm64 --split-per-abi` 通过，`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` 为 77,858,620 字节；ZIP 的 native library 目录仅含 arm64-v8a。保留现有 CupertinoIcons 字体提示，不影响本次构建成功。
- Windows x64 Release 通过。默认 EXE 被正在运行的应用占用，未关闭它；临时 CMake runtime/install 路径将新产物置于 `build/qa/auth-windows-release`，随后恢复默认生成配置。该目录核对 EXE、网页插件、WebView2Loader、Flutter／Dart 产物、资产与五份原生许可齐全。Flutter 成功消息仍显示默认路径，实际新产物以独立目录为准。上游 CMake 警告仍存在，构建成功不代表网页／验证码已实测。
- 本机没有连接 Android 设备。真实扫码／密码／短信登录、Windows 官方网页与验证码交互、Android 真机软键盘／WebView／安全存储、macOS 构建和运行均未验收。官网为具体账号展示何种额外验证，由网站行为决定，不能由 fixture 或构建成功推断。
