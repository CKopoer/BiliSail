# 移动端评论／弹幕键盘避让与相册选择

日期：2026-11-09。范围：Android／iOS 的评论、回复和弹幕输入，以及共用图片选择入口。按用户要求仅执行自动检查，不构建应用，不操作设备；实机确认由用户后续完成。

## 定位与修复

- 视频／PGC 共用 `PlaybackPageLayout` 为普通页面保留最小信息区高度，键盘挤压 Scaffold 后仍可能把评论输入区放在可见区域之外。键盘可见时改用实际剩余高度，收起额外的竖屏／方形视频高度，必要时缩小播放器，为信息区优先留出空间。Scaffold 已消耗键盘 inset，布局只用当前 View 判断键盘状态，不重复扣减高度。
- `CommentsPanel` 原先先测量排序／楼中楼头部，再给输入区分配空间。横屏小高度时头部会挤掉编辑器或发布按钮。现在先测量输入区，头部在剩余空间内显示并裁剪，列表使用余下高度；编辑器自身仍可滚动。不增加头部滚动控制器，保留原评论列表的滚动所有权。
- `Dialog` 默认对键盘 inset 再执行一次动画，实际键盘升起期间发送框会落后。`showAppDialog` 在共享路由内立即消耗底部 inset，并从后续 MediaQuery 中移除已消耗部分，统一覆盖评论、通知回复、弹幕及其子弹窗，避免二次避让；保持原窗口 Navigator、焦点和模态行为。
- 图片入口原先在全部平台调用 `file_selector.openFiles`，Android 是文档 Intent、iOS 是 `UIDocumentPickerViewController`，因此无法保证进入相册。移动端改用 `image_picker` 的系统图片选择，桌面仍用原文件选择器。私信复用同一入口，也随之采用相册。
- 传入剩余可选数量，保留返回后的数量复核、每张 10 MB、JPG／PNG／GIF 内容签名、尺寸／像素上限和草稿的账号代次隔离。取消返回空列表，平台错误继续向上传播；不在选择时上传，仍需用户显式发送。不跨进程恢复临时草稿，也不将进程重启后遗留的图片附加到其他账号／评论目标。

## 依赖与平台配置

新增精确依赖 [`image_picker` 1.2.4](https://pub.dev/packages/image_picker/versions/1.2.4)，根锁文件固定 `image_picker_android` 0.8.13+25、`image_picker_ios` 0.8.13+15 和其余传递依赖。未改四个独立包的依赖声明。

核对了下载的官方包源码与平台清单：Android／iOS 通过系统图库接口选图，iOS 当前 podspec 下限为 15.0，与应用下限一致；插件包含 Kotlin／Swift 平台实现，无额外手动下载的媒体二进制。许可证为 Flutter 部分的 BSD-3-Clause，并保留包内 aFileChooser 的 Apache-2.0 声明，由 Flutter 插件及许可收集流程处理。没有复制插件源码或修改 Pub 缓存。

依据[插件配置说明](https://pub.dev/packages/image_picker)，iOS 添加 `NSPhotoLibraryUsageDescription`；调用使用 `requestFullMetadata: false`，仅获取用户选择的图片，不主动请求完整照片元数据。不引入相机／录像入口，也不增加相关权限。Android 沿用系统选择器配置；具体设备的图库展示由系统实现决定。

## 自动验证

新增回归先在旧实现复现失败，再验证修复：

- 视频／PGC，在 Android／iOS 平台模拟的 390×800 竖屏、844×390 横屏中逐步改变键盘高度，输入框和发布按钮位于键盘上方，保留草稿、焦点与播放器实例。
- 弹幕弹窗在两平台、横竖屏中逐帧跟随键盘升降，发送入口保持可点击，保留文本与焦点。
- 移动相册入口的剩余 1／2／9 张、取消、超量返回、空图片、非法内容、超过 10 MB、满草稿和平台错误。
- 原评论图文发布、迟到选图与账号切换、通知回复、播放页滚动折叠及共享弹窗行为回归。

最终验证结果（根检查脚本按阶段执行，并补齐中断的检查）：

| 检查 | 结果 |
| --- | --- |
| `tool/check.ps1 -EnforceLockfile` 中的依赖解析 | 根应用与四个包的五份锁文件可复现解析通过；仅根应用锁文件新增图片选择依赖 |
| 根检查脚本的打包边界／CI 断言 | 通过；其中按宿主或配置跳过的测试保留原跳过状态 |
| 根应用、四个包及 Linux 本地适配器格式复核 | 通过；`git diff --check` 通过 |
| `flutter analyze --no-pub`、Linux 本地适配器 `dart analyze` | 均无问题 |
| `tool/check.ps1 -SkipPub -Stage RootTests` 最终重跑 | 4,889 项通过，13 项按既有配置跳过，无失败 |
| `tool/check.ps1 -SkipPub -Stage PackageTests` | bili_api 769、bili_player 367、bili_danmaku 161、bili_mux 5 项通过；mux 原生 10 项跳过 |

本轮最终根应用与子包合计 6,191 项测试通过。`BILI_MUX_LIBRARY` 未配置，10 项原生 mux 跳过不算原生集成通过。日志保存在忽略目录 `artifacts/mobile-input-root-final.log`、`mobile-input-package-tests.log`、`mobile-input-analysis-final.log`、`mobile-input-format.log`，本次没有应用构建或设备回归。

## 后续设备验收

本次未构建、未运行 Android／iOS 真机，也无活动调试应用可热重载。需用户在自行构建后确认系统输入法（含候选栏、换行、收起／切换）、横竖屏、全屏弹幕、动态评论／通知回复、相册单选／多选／取消和权限处理。iCloud 图片、HEIC 的系统转换、Android 旧系统／厂商图库以及进程被系统回收后的体验均未做设备验证；自动布局测试不能替代这些确认。
