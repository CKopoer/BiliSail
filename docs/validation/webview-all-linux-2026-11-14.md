# 全平台 WebView 迁移与 Linux 登录

日期：2026-11-14。

## 来源与范围

参考 [PiliPlus PR #3423](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3423)（合并提交 `0fa4323cbc9ac44b74df498d18c748c1ecfc8b5d`）选择 WebKitGTK 路线。该 PR 只迁移 Linux，本项目按用户要求将 Android、iOS、macOS、Windows 和 Linux 统一改为精确版本 [webview_all 1.5.0](https://pub.dev/packages/webview_all/versions/1.5.0)。未复制 GPLv3 的 PiliPlus 应用代码；使用插件的公开 API 独立实现，`webview_all` 为 MIT，各平台派生实现另保留 Flutter 上游 BSD 通知。完整依赖摘要在根锁文件，四个独立包的依赖未变。

删除旧 `flutter_inappwebview` 及其 Linux 占位插件。Apple 的 UA 标记、原生 Cookie channel 和对应 XCTest 已由会话 Cookie API 替代；移除两处 Xcode 引用。Windows 移除旧插件的 coroutine/PCH 兼容配置及已不用的 CppWinRT/json 许可安装，保留新插件实际使用的 WebView2 Loader、SDK 和 WIL 许可。

## 登录与数据边界

- [登录窗口](../../lib/core/platform/passport_web_login.dart)使用统一 `WebViewWidget`，Linux 开放与其他平台相同的密码／短信官网入口。主框架导航只允许 HTTPS 的 Bilibili 域，保留系统 TLS 验证，不添加 JavaScript 登录桥。
- [会话所有者](../../lib/core/platform/passport_webview_environment.dart)在 Windows／Apple／Linux 请求 `isolatedIncognito`，不支持时明确失败并可继续扫码。插件自行管理原生私有存储和控制器；移除原 Windows 独立目录管理。
- Android 系统 WebView 的 incognito 仅限制缓存／表单，存储仍共享。登录前后清理本应用 WebView 的 Cookie、缓存、localStorage 和 IndexedDB；清理失败不加载官网。共享存储从创建到清理完毕独占，旧登录关闭不会清理新登录。应用会话凭据仍只进入既有安全存储，不向网页注入。
- [Cookie 读取器](../../lib/core/platform/passport_web_cookies.dart)只通过该会话的 CookieManager 读取 API 根地址，包含 HttpOnly；先检查元数据能力，拒绝缺失作用域、安全属性、会话／过期时间或超量结果。插件统一返回 `DateTime`，映射为 UTC，不再按平台猜测秒／毫秒。
- 保留 10 秒读取期限、10 分钟总期限、后台停止读取／返回继续、单飞、关闭取消和迟到结果隔离。Windows／Linux 原生网页取得焦点导致 Flutter inactive 时继续轮询，真正隐藏／暂停时停止。GTK 原生网页位于 Flutter 绘制之上，加载错误时用 Offstage 隐藏原生区域，保留会话后显示重试；重试只 GET 初始地址。
- 原生控件移除并完成已有读取后关闭会话；账号 nav 验证、epoch、凭据保存与升级流程继续由既有 SessionRepository 执行。

## Linux 构建与分发

[依赖脚本](../../tool/setup-linux-build.sh)增加 `libwebkit2gtk-4.1-dev`、`bubblewrap` 和 `xdg-dbus-proxy`。没有引入原 WPE WebKit 链路。

[打包脚本](../../tool/package-linux.sh)要求实际 WebView 插件，并通过 [部署脚本](../../tool/linux-webview.py)携带发行版 WebKitWebProcess、WebKitNetworkProcess、可用的 WebKitGPUProcess 和 injected bundle；linuxdeploy 对辅助进程也收集动态依赖。AppDir 和安装后的 Flatpak Runtime 检查同时覆盖这些进程，缺失即失败，不能只检查 `.so`。

发行版 WebKitGTK 的 `WEBKIT_EXEC_PATH` 只在开发构建启用，见 [WebKit 路径实现](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/glib/ProcessExecutablePathGLib.cpp)。打包后将库中唯一、NUL 结尾的 Ubuntu helper 前缀替换为等长相对前缀，保持 ELF 偏移；前缀不符即停止打包。[AppRun](../../linux/packaging/AppRun)设置工作目录和公开的 injected-bundle 路径。包内保留修改前后 SHA-256、变换脚本，以及发行版 binary/source 精确版本和版权文本，便于重建。AppImage 的 Ubuntu 24.04 基线仍需宿主提供 `/usr/bin/bwrap` 和 `/usr/bin/xdg-dbus-proxy`，沿用 WebKit 的沙盒策略。Flatpak 权限没有扩大，也未关闭 WebKit 沙盒。

## 验证

Windows x64／Flutter 3.47.6、Dart 3.13.5：

- `tool/check.ps1 -EnforceLockfile` 完成五份锁文件的严格解析／可复现检查；按 `-Stage Lint -SkipPub`、`-Stage RootTests -SkipPub`、`-Stage PackageTests -SkipPub` 收尾通过。根应用全套 5523 项通过，13 项符号链接用例因 Windows 权限条件跳过；四个包分别通过 API 948、播放器 318、弹幕 161、mux 5 项。播放器另有 3 项环境跳过，未配置 `BILI_MUX_LIBRARY` 的 10 项 mux 原生用例跳过，不计为原生通过。数量包含同期其他修改。
- 最终登录定向 55 项通过，覆盖元数据能力／作用域／UTC、私有存储、Android 清理独占、桌面原生焦点、主框架导航取消与证书错误、GET 重试、迟到响应和关闭释放。根全套第一次发现 Offstage 后测试查找器跳过控件，修正查找器后全套通过；最终另补证书错误回归并定向通过。
- Windows Debug 整应用构建通过；[原生用例](../../integration_test/windows_passport_web_login_test.dart)两项通过，包括弹窗／共享输入宿主中的 DOM 鼠标点击、编辑及重新加载，以及真实网页加载／JavaScript、HttpOnly／有效期和两路仍存活私有会话隔离。已启动普通入口并完成热重载，随后关闭本次调试实例。
- 最终全仓格式、静态分析与打包边界检查通过。日志位于 `build/webview-migration/`。

WSL Ubuntu 24.04.4 x64：

- 固定版本 Linux Flutter SDK、WebKitGTK 2.52.6／4.1 开发包和项目原生依赖下，Linux Debug 整应用构建通过。mpv 源码下载遇到 TLS 中断，使用已有本机归档并核对固定 SHA-256 `068960e89211f2adc80af03f637fa393fb5e407d3dd23592c8fe8c5490bb7ae4`；本机缺开发链接名，在隔离构建目录给产出的固定 `libmpv.so.2` 建立 `libmpv.so` 链接，未修改个人 fork 或 Pub 缓存源码。
- 同一原生测试文件用 `--plain-name "native private stores isolate full HttpOnly cookies"` 执行通过，验证 WebKit 网页进程加载、JavaScript、Cookie 元数据及同时存活的独立存储。另以实际发行版 WebKitGTK 共享库的相对前缀变换、打包 helper 和 injected bundle 重跑通过。
- Linux 构建／分发脚本共 40 项离线回归通过，覆盖 helper 缺失／损坏、子进程动态依赖、等长前缀变换、未知 ABI 拒绝、原有 mpv 来源／许可与版本检查。Bash 语法检查通过；变换后的 WebKit 库与来源摘要写入独立验证目录。

未执行本次 Android／iOS／macOS 构建与设备登录、真实账号密码／短信／验证码、Linux 发行安装包 AppImage／Flatpak 的完整生成和安装验收，或纯 Wayland／其他发行版验收。WSL 受控原生测试不代表这些流程已通过；未测性能。文档相对链接和 `git diff --check` 通过。
