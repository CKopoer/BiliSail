# 关于页与每日更新检查

日期：2026-10-06。在已有工作区修改上增量实现。

## 行为与边界

关于页显示真实应用版本、可点击的 `https://github.com/CKopoer/BiliSail` 和“检查更新”。应用启动后不阻塞首屏，每个本地日历日首次启动检查一次；先持久化尝试日期，自动检查失败或没有新版本时不弹窗，当天重启不再次检查。手动检查不受日期限制，有加载状态和明确结果，与正在进行的自动检查共享同一次请求。

新版本弹窗显示版本、预览标记与更新说明；“稍后再说”关闭弹窗，“前往 Release”调用系统浏览器打开该版本页面。只有用户点击才打开外部页面，不自动下载、安装或打开浏览器。提示由进程级宿主管理，切换或关闭设置标签不会取消整个应用的更新检查；同一请求不产生重复弹窗。退出或请求超时会取消网络读取，迟到响应不更新状态。

## 协议、版本与存储

- 独立无凭据 `HttpClient`，单次 GET `https://api.github.com/repos/CKopoer/BiliSail/releases?per_page=100`；`Accept: application/vnd.github+json`、`X-GitHub-Api-Version: 2026-03-10`。不附 Bilibili Cookie/token，不跟随重定向、不自动重试，保留系统 TLS 验证。
- 检查最近最多 100 个 Release，排除草稿，包含已公开的预览版本，按版本大小选候选。空列表表示暂无发布，错误格式不伪装成“已是最新”。依据 [GitHub Releases REST 文档](https://docs.github.com/en/rest/releases/releases#list-releases) 使用列表端点，兼容本项目的 prerelease 发布流程。
- 版本先按 `major.minor.patch` 与预发布标识比较，再比较数字 Flutter `+N` 构建号，支持 `v0.1.0+2`。同一语义版本的不同数字构建可提示更新；非数字构建元数据不改变优先级，不按字符串字典序比较。
- `package_info_plus 10.2.2` 从已有锁定的传递依赖提升为直接依赖，BSD-3-Clause，支持 Android/Windows/macOS，未改变解析版本。常规运行读取平台包版本，[Release 脚本](../../tool/build-release.ps1) 通过 `BILISAIL_RELEASE_VERSION` 注入实际 `x.y.z+N`，避免 Android split APK 的 `versionCode +2000` 被当作 Release 构建号。自行执行 split APK 构建时应传相同 Dart define。
- 网络总读取期限 12 秒，整个检查期限 20 秒；响应最多 2 MiB，展示说明最多 12000 字符。说明以纯文本显示；只接受本仓库的 HTTPS Release 链接，拒绝其他 host、仓库、端口、userinfo、query 或 fragment。
- 日期写入既有 `settings` 表的 `app_update.last_startup_day.v1`，与账号无关。不改表、不改变 SQLite schemaVersion 2、不清空设置或历史；版本查询、HTTP、日期存储与链接打开均通过应用层注入。

## 参考与采用范围

只读参考相邻 biliuwp-lite 提交 `7c1baab53a5afb80235323ef5b37463e4b93db9f`：

- [AboutSettingsControl.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/AboutSettingsControl.xaml) / [代码](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/AboutSettingsControl.xaml.cs)：关于页检查入口。
- [BiliExtensions.CheckVersion](../../../biliuwp-lite/src/BiliLite.UWP/Extensions/BiliExtensions.cs)：版本比较、更新说明弹窗和查看详情。
- [App.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/App.xaml.cs)：窗口启动后的静默检查入口。
- [GitApi.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/GitApi.cs)：参考项目使用自有 `new_version.json`，本项目独立接入自己的 GitHub Release。

仅借鉴流程与职责，独立编写 Dart/Flutter；未复制 C#/XAML、资源、版本描述 schema，亦不依赖或修改相邻仓库。参考项目每次 release 启动检查，本项目按用户要求增加每日尝试记录；未加入忽略版本或镜像更新地址功能。

## 验证

离线测试覆盖版本及构建号排序、预览/草稿、空列表、错误协议与链接、容量、SQLite 日期重开、跨日/失败后重启、手动合并、取消/超时与迟到结果、窄窗口、弹窗确认及浏览器打开失败。Windows 原生入口为 [windows_app_updates_test.dart](../../integration_test/windows_app_updates_test.dart)，在线读取需显式 `--dart-define=BILI_UPDATES_ONLINE=true`，正常检查不访问真实账号或外网。

本轮在 Windows / Flutter 3.47.6 / Dart 3.13.5 完成：

- `tool/check.ps1 -EnforceLockfile` 通过：根应用 641、bili_api 207、bili_player 16、bili_danmaku 21 项，共 885 项；根应用和三个包格式检查、静态分析均通过。更新专项 24 项包含在根应用计数中；日志 `artifacts/app-updates-check.log`。
- `flutter test integration_test/windows_app_updates_test.dart -d windows --dart-define=BILI_UPDATES_ONLINE=true` 通过 2 项。真实 Windows 包读取 `0.1.0+1`，原生窗口显示更新提示，SQLite 当日标记与弹窗操作正确；实际无凭据 GitHub 查询取得已公开的 `0.1.0+2`。外部打开端口在此测试中记录目标 URI，没有实际启动浏览器；日志 `artifacts/app-updates-windows.log`。
- 原生截图 `artifacts/app-updates-windows.png` 已查看，关于页、版本、GitHub 地址、检查入口与更新弹窗布局正常。
- 显式 `BILISAIL_RELEASE_VERSION=1.2.3+45` 的版本读取回归通过，验证发布版本覆盖平台包的原生版本码；日志 `artifacts/app-updates-version-override.log`。
- `flutter build windows --debug` 的普通应用入口构建成功，产物 `build/windows/x64/runner/Debug/bilisail.exe`；日志 `artifacts/app-updates-build.log`。PowerShell 构建脚本语法、110 条本地文档链接及 `git diff --check` 通过。

正常离线检查不访问真实账号或外网，本轮只读访问 GitHub，没有发布 Release、下载更新包或更改账号。Android/macOS 构建与实机运行、真实系统浏览器打开，以及修改后版本的 MSIX 安装升级待验证；Windows 原生验证不代表这些平台或安装链路已经验收。
