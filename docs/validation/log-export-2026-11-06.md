# 设置页日志压缩导出

2026-11-06 后续：#69 独立诊断分支增加普通播放／倍速下每 500ms 的原生性能采样、长按与松手时间线、Flutter 帧耗时及更多播放配置，播放文件上限提高为 512KiB。下文首次实现“不包含持续采样”和播放通道 256KiB 的描述属于增加诊断前的范围；当前字段、容量和验证见[播放性能诊断](playback-diagnostics-2026-11-06.md)。

日期：2026-11-06（Asia/Shanghai）。按用户要求在设置页标题栏增加“导出日志”，无需电脑或调试包。导出期间禁用重复操作，成功后显示可选择、可复制的保存位置；失败保留原始日志并允许重试。

## 恢复默认与日志导出按钮布局

同日按用户后续要求调整标题栏，按设置页实际可用宽度适配：600 逻辑像素及以上时标题居左，“恢复默认设置”和“导出日志”作为紧邻的操作组居右；不足 600 时，操作组移到标题下一行并继续右对齐。组内间隔 8 逻辑像素，空间不足或字号放大时自动换行，不截断按钮文案。分类栏继续位于整个标题／操作区域下方，随内容滚动时保持固定。

宽窄布局切换复用同一组按钮元素，日志导出期间缩放窗口不会丢失完成弹窗；恢复默认的确认与保存、导出过程的忙碌／失败／重试行为沿用原实现。

## 内容与隐私

- 压缩包为 `BiliSail-logs-<UTC 时间>-<进程号>.zip`，包含 `logs/core-*.log`、`logs/playback-*.log`（含轮转文件）、`diagnostics.json` 与中文说明。
- 核心日志新增启动／就绪／退出、启动失败、Flutter 框架与未处理异步异常、API 请求成功／取消／错误分类及耗时、账号会话切换事件、下载队列数量及失败摘要。下载进度变化不逐次写入；相同摘要去重。原有错误处理继续执行。
- 只记录结构化允许字段：异常类型／错误分类、数量、耗时及最多 16 条 package/Dart 栈位置。异常消息、原始栈文本、本机路径、账号 ID、Cookie、Token、二维码 key、请求／响应正文及完整 URL 均不记录。播放器继续沿用既有脱敏事件；不导出系统 logcat／bugreport、数据库、安全存储、WebView 数据或离线媒体。
- 元信息包含应用版本、平台、系统／Dart 版本、日志通道可用状态、导出时间及文件数量。Android 另含厂商、型号、系统 API 与 ABI，不采集序列号或设备唯一标识。版本／设备元信息读取失败不阻止已有日志导出。
- 核心与播放通道共享有界文件写入器：每文件最多 256 KiB，每通道最多约 6 个文件，写入等待队列最多 64 项；溢出计数随下一条事件记录，存储不可用不阻止正常业务。历史保留按通道独立清理。
- 导出先 flush 已排队写入，再在 worker isolate 读取、压缩。只读取日志目录直属且名称符合规则的常规日志文件，不递归读取或跟随已发现的链接。最多 32 个文件、单文件 512 KiB、日志总量 8 MiB；优先较新的文件，超限或轮转期间消失的文件计入 `skippedLogFiles`。没有日志时仍导出说明与零文件计数。
- 无自动上传或第三方遥测，不改变账号、下载偏好或数据库 schema。日志不会追溯补录升级前缺少的核心事件，也不包含持续掉帧／音画时钟差采样。

## 各平台默认位置

| 平台 | 保存位置与方式 |
| --- | --- |
| Android 10+ | 公共 `Download/BiliSail/logs/`；MediaStore Downloads 先写入 pending 项，成功后发布，失败删除未完成项；无需申请广泛存储权限 |
| Android 7–9 | 同一公共下载子目录；申请既有 `WRITE_EXTERNAL_STORAGE` 权限，拒绝时说明失败；临时文件写完后发布 |
| Windows／macOS | 默认应用文档根目录下 `BiliSail/exported_logs/`，与默认 `BiliSail/offline/` 相邻 |
| iOS | 应用 Documents 下 `BiliSail/exported_logs/`；启用系统文件共享与原地打开，使用户可在“文件”中取出压缩包 |
| Linux | 应用 support 根目录下 `exported_logs/`，与既有默认 `offline/` 相邻，遵守 Flatpak 私有持久目录边界 |

桌面／iOS／Linux 先写 `.partial` 再改名。目录规则复用 `FileAccessService.defaultDownloadDirectory` 的平台根目录，不随用户自选的离线下载目录变化。文件名包含微秒时间与进程号；Android 原生层只接受限定文件名及最多 10 MiB 的 ZIP 字节。

## 依赖与源码

- 新增精确依赖 `archive: 4.5.2`（MIT，Brendan Duncan；[官方仓库](https://github.com/brendan-duncan/archive)），用于纯 Dart ZIP 编码；传递依赖 `posix: 6.5.2`。本功能只编码 ZIP，不调用外部工具或增加原生压缩库。根锁文件同步；其他四个包依赖未变。
- [核心日志](../../lib/core/logging/core_diagnostic_log.dart)、[共享写入器](../../lib/core/logging/diagnostic_log_writer.dart)、[导出仓储](../../lib/features/settings/data/diagnostic_log_export_repository.dart)、[平台保存适配](../../lib/core/platform/log_archive_storage.dart)、[Android 发布](../../android/app/src/main/kotlin/dev/bilisail/bilisail/LogExportHandler.kt)。

## 验证

- `tool/check.ps1 -EnforceLockfile` 完整通过，覆盖可复现依赖解析、打包边界脚本、格式与静态分析，以及根应用 4416、bili_api 659、bili_player 148、bili_danmaku 161、bili_mux 5，共 **5389 项测试**。13 项 Windows 符号链接测试因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志：`build/log-export-check.log`。
- 定向回归覆盖核心／播放日志的轮转及洪泛限流、异常敏感信息过滤、API 结果与会话事件、ZIP 两通道／轮转文件汇总、排除私有与嵌套文件、空日志、容量限制、flush 与重复导出去重、权限失败后重试、默认保存路径／Android channel 及设置按钮忙碌／成功／失败状态。已有设置页测试一并通过。
- Windows Debug 构建并启动隔离验证入口，调用生产导出仓储与文件保存适配器，生成含两个日志文件的实际 ZIP；使用独立 Python `zipfile` 校验 CRC、两通道、manifest 文件数及敏感测试值缺失。随后 DTD 热重载成功，未发现运行时错误，并关闭本任务启动的进程。此入口只使用构建目录内的假数据，不读取真实账号；不等于完整正式入口验收。日志与输出：`build/log-export-preview.log`、`build/validation/log-export/`。
- `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 复用已有 Android arm64 mux 资产构建通过，原生 Kotlin 保存通道参与编译。产物 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，包名 `dev.bilisail.bilisail.test`、名称 `BiliSail 测试版`、版本 1.2.6+7／12607；脚本完成签名及不可调试等身份校验。SHA-256：`50d4e55a9ceebd860905af668658a2ff918b08c26999c7b208b5cf1313d20615`。未安装到设备。构建保留既有插件 KGP 与图标字体告警，无编译错误；日志：`build/log-export-android-build.log`。
- 文档新增相对链接及 `git diff --check` 通过。当前无 adb 设备连接；Android 公共目录写入、旧系统授权、iOS 文件共享、macOS／Linux 实际目录访问仍需对应平台验收，不由单元测试或构建结果替代。未执行 Apple／Linux 构建、性能或真实账号测试。

### 后续按钮布局验证

- `tool/check.ps1 -SkipPub` 完整通过：打包边界、格式与静态分析通过，根应用 4417、bili_api 659、bili_player 148、bili_danmaku 161、bili_mux 5，共 **5390 项测试**。13 项 Windows 符号链接测试因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。未修改依赖或锁文件。日志：`build/settings-actions-check.log`。
- 设置页面、分类滑动与日志导出定向回归 56 项通过，覆盖 320／375／599／600／1280 逻辑像素、两倍字号、标题与分类固定、按钮可点击且不重叠，以及导出过程中反复跨断点缩放后仍展示成功弹窗。日志：`build/settings-actions-targeted.log`。
- Windows Debug 构建并启动隔离预览入口，以内存设置渲染真实设置页，确认宽屏、窄屏、两倍字号与深色主题截图；DTD 热重载成功，运行时无错误。截图与预览源码位于 `build/validation/settings-actions/`，运行日志为 `build/settings-actions-preview.log`；已关闭该预览进程。此项不读取真实账号或偏好，不等于移动设备或完整正式入口验收。本次布局调整未执行 Android／Apple／Linux 构建、设备或性能测试。
