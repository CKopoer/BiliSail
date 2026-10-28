# 图片查看器保存、复制与长图

日期：2026-10-25。

## 行为与平台

评论、首页／空间动态继续共用 [ImageViewer](../../lib/shared/ui/image_viewer.dart)。工具栏增加“保存图片”“复制图片”，仅在受支持平台显示，原图未就绪和导出进行中禁用。操作由[图片控制器](../../lib/features/image_viewer/application/image_viewer_controller.dart)捕获点击时的原图；不重新请求 CDN。切图、账号变化和关闭后，迟到的完成反馈不能覆盖新状态。明确点击后的系统写入不因切图而回滚；失败允许显式重试，30 秒超时提示先检查目录／粘贴结果，不自动重放。

[平台适配器](../../lib/core/platform/image_export_service.dart)只向原生端传递文件字节、依据实际文件签名确定的扩展名和 MIME，不传远端 URL、查询参数或账号凭据。没有新增第三方依赖。保存不转码，生成唯一文件名，保留原始格式与动图数据。

| 平台 | 保存位置 | 图片剪贴板 |
| --- | --- | --- |
| Windows | `SHGetKnownFolderPath(FOLDERID_Pictures)` 返回的系统图片目录下 `BiliSail/`，兼容目录重定向 | WIC 解码第一帧为原尺寸 BGRA DIBV5；PNG 同时放入原始 PNG 数据，供不同接收程序使用 |
| macOS | `FileManager.picturesDirectory` 下 `BiliSail/` | `NSImage` 写入系统 `NSPasteboard`；最终粘贴取决于接收程序支持的图片格式 |
| Android 10+ | `MediaStore.Images`、`Pictures/BiliSail/`，完成写入后清除 `IS_PENDING`，供相册发现 | 私有缓存中的原文件经只读、URI 授权的 ContentProvider 提供给系统剪贴板，不复制 URL 文本 |
| Android 7–9 | 系统 `Pictures/BiliSail/`，用户授予旧存储权限后写入并触发媒体扫描 | 同上，复制不要求公共存储权限 |

Android 剪贴板保留最近四份文件，最多 128 MiB，关闭查看器不删除当前剪贴板文件；后续复制淘汰旧文件。Provider 只接受固定 UUID 文件名、图片扩展名和只读打开，不暴露其他缓存。macOS 的 Debug/Profile 和 Release 均增加图片目录读写 entitlement；[发布检查](../../tool/macos-release-validation.ps1)同步要求该权限，继续拒绝其他额外／重复／禁用权限。

## 长图根因与新边界

旧[原图仓储](../../lib/features/image_viewer/data/network_original_image_repository.dart)在读取编码图片尺寸后，主动拒绝任一边超过 **16,384 px** 或总像素超过 **32 × 1024 × 1024** 的文件。该判断发生在原图下载成功后、Flutter 像素解码前，是客户端限制。没有具体失败 URL，不能断言每一次长图失败都由此造成，CDN 非 200、超时、损坏或不支持的格式仍分别可能失败；本轮没有新增 API，也未用真实图片 URL 做在线核对。

现将编码原图和显示预览分别限额：

- 编码文件仍最多 **32 MiB**、下载 deadline **30 秒**；长宽分别最多 **262,144 px**，总像素最多 **64 × 1024 × 1024**（约 6711 万），限制极端解码输入。
- 原图尺寸和字节保持完整。Flutter 主预览最长边最多 **8192 px**、解码最多 **16 × 1024 × 1024** 像素；背景同时限制在 **256 × 256** 包围框内，避免仅指定宽度使长图背景仍生成超高纹理。按 [Flutter ResizeImage](https://api.flutter.dev/flutter/painting/ResizeImage-class.html) 的尺寸解码机制降低预览内存与纹理尺寸，不承诺无限尺寸或原分辨率长图文字清晰度。
- 缩放布局仍使用原图长宽，最低缩放改为 `0.0001`，适应窗口能容纳极长图；大图显示“缩小预览”说明。底部工具栏按实际高度参与布局，窄窗口换行不会覆盖预览视口。
- 保存使用编码原文件；图片剪贴板使用原文件／原尺寸第一帧，接收程序仍可能自行转换。Windows WIC 不支持的编解码格式会明确复制失败，不报虚假成功。
- 公共传输层新增有类型的体积超限错误，原图查看器将 Content-Length 与分块累计超限归为大小限制，而非笼统的下载失败。取消、HTTPS／公开主机校验、无凭据传输和代次隔离沿用原实现。

## 验证

- [原图仓储测试](../../test/features/image_viewer/original_image_repository_test.dart)：生成 24,000 px 长图／宽图，验证仓储接受、原字节保留与有界尺寸实际解码；覆盖体积、尺寸、像素上限及取消。原有 16,384 px 判定会拒绝这些长图。
- [导出控制器测试](../../test/features/image_viewer/image_viewer_controller_test.dart)覆盖未加载、重复点击、当前原图、失败重试、切图／账号／关闭后的迟到完成；[平台通道测试](../../test/core/platform/image_export_service_test.dart)覆盖签名格式、原字节、平台能力和错误传播；[宽窄屏组件测试](../../test/features/image_viewer/image_viewer_test.dart)验证两个按钮、保存路径／复制反馈与不额外下载。
- 双窗口原图／路由和公开图片传输回归一并执行，定向合计 29 项通过。
- [Windows 原生回归](../../tool/test-windows-image-export.ps1)在独立窗口站、独立桌面使用真实剪贴板，不打开或覆盖交互用户剪贴板。验证 WIC 原图转 DIBV5、PNG 原字节、损坏文件失败保留前次剪贴板、24,000 px 长图复制不缩小／裁切、系统图片目录保存与原字节一致，并删除本次生成的测试文件。
- Windows 原生资产按 `tool/build-download-mux.ps1 -Target windows-x64` 准备；Windows Release 构建通过。Android `:app:compileDebugKotlin -x compileFlutterBuildDebug` 通过，只证明原生源码／manifest 相关依赖可编译，未构建 APK 或设备安装。
- 本机未发现 DTD／调试应用，热重载调用因无活动连接未执行。macOS 无本机工具链；Android／macOS 真实相册保存、权限交互和跨应用粘贴，以及 Windows 实际接收程序粘贴仍需设备验收。本轮未测性能。

`tool/check.ps1 -SkipPub` 最终完整通过：根应用 2,237、`bili_api` 446、`bili_player` 81、`bili_danmaku` 93、`bili_mux` 2 项，共 **2,859 项**；五处格式、静态分析及打包边界检查通过。mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能视作原生封装回归通过。此前的检查先因本次新增 Pictures entitlement 尚未同步发布白名单而失败（已修复），随后因同期新增的 `test/shared/ui/app_dialog_test.dart` lint 失败；最终检查时同期 lint 已消除，本任务未修改该文件。

日志位于本机忽略目录 `build/validation/image-export-{check,windows-build,android-compile}.log`。计数包含工作区同期修改，不代表全部由本任务新增。`git diff --check` 通过，用户和其他任务的修改保留；本任务未提交或推送。

## 2026-10-28 左右滑动与缩放

共用查看器在适应窗口或更小的缩放下，支持单指左滑查看下一张、右滑查看上一张；横向距离需达到视口宽度的 15%（最少 48、最多 100 逻辑像素），且明显大于纵向距离。首尾不循环，短拖动、竖向／偏竖向拖动和取消手势不切图。加载中或加载失败时也可滑动切图，沿用控制器取消旧读取与代次隔离。

缩放继续交给 `InteractiveViewer`。双指接触会取消本次切图候选，直到全部手指抬起；放大后的单指拖动继续平移图片，回到适应窗口后恢复滑动切图。单图继续允许平移，按钮、键盘、滚轮缩放及关闭行为保留。缩放矩阵同步设置三个坐标轴的比例，避免 `getMaxScaleOnAxis()` 把适应窗口后小于 1 的实际比例读成 1，保证大图缩放百分比、相对缩放和手势模式判断一致。

[组件回归](../../test/features/image_viewer/image_viewer_test.dart)新增宽／窄视口的左右切图、首尾边界、短／竖向拖动、取消、双指放大缩小、单指续拖、放大平移、切图恢复适应窗口，以及加载失败／迟到响应和单图行为。连同[双窗口回归](../../test/app/workspace_image_viewer_test.dart)共 14 项通过。本轮未构建安装包，未进行 Windows／Android／macOS 实机触控或触控板验收；不以组件测试代替设备验收。

本次两个改动 Dart 文件的定向静态分析通过。`tool/check.ps1 -SkipPub` 的打包边界及各目录格式检查通过，全量分析被同期工作区的 `playback_panel.dart` 多余导入和 `window_orientation_host_test.dart` 缺少花括号阻断。随后分别执行根应用与四包测试阶段：根应用 3,324 项通过、4 项失败、13 项因 Windows 符号链接权限不足跳过；失败分别为 `navigation_bar_mode_test.dart` 的两项导航布局断言、`playback_panel_test.dart` 的宽屏旋转全屏保持断言、`dpi_adaptation_test.dart` 的逻辑几何断言，均未由本任务修改。四包分别为 492／83／116／5 项通过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。本轮全量检查未记为通过，未改动上述同期文件；日志为 `build/validation/image-viewer-swipe-{check,root-tests,package-tests}.log`。文档相对链接及 `git diff --check` 通过。
