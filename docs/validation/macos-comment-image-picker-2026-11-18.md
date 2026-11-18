# macOS 评论选图与窗口归属

日期：2026-11-18。

## 定位

在 Windows 选图修复后的跨平台复查中，确认 macOS 仍走 `file_selector_macos 0.9.5+2`。锁定版本的 `FileSelectorPlugin.swift` 通过 `registrar.view` 获取隐式原生视图，再用其 window 展示面板；window 为空时同步调用 `runModal()`。

本项目的 macOS engine 以 headless 启动，主窗口与播放窗口均在启用 multiview 后创建。固定 Flutter SDK 的 registrar `view` 仅查询隐式 view 0，多视图模式不会为原生窗口复用该 ID。因此，此路径不能将选择器绑定到发起操作的窗口，并会落入应用级同步模态分支。此结论来自当前应用、锁定插件和 Flutter engine 源码，没有 macOS 现场崩溃栈或实机复现，不将其写成已确认的崩溃原因。

## 修复

- `pickLocalImages` 在 macOS 与 Windows 共用 `bilisail/image_picker`。评论、动态和私信已在 Windows 提交中传入各自 `View.of(context).viewId`，这次复用该参数，不增加业务层平台判断。
- macOS runner 只在当前 engine 的真实 NSWindow 中匹配 view ID。无效／关闭视图返回 `window_unavailable`，不使用 keyWindow、mainWindow 或隐式视图作回退，也不接受原生指针。
- `ImagePicker.swift` 使用 `NSOpenPanel.beginSheetModal(for:completionHandler:)` 异步绑定调用窗口。AppKit 始终留在主线程，面板结束后再排入主队列回传结果，避免 Flutter 回调重入原生 sheet 完成栈；不采用 Windows 的 STA 工作线程策略。
- 进程同时只保留一个请求；其他窗口重复发起选图，或调用窗口已有原生 sheet 时返回 `picker_busy`。选图保持 JPG／JPEG／PNG／GIF 多选和 18 张原生硬上限；Dart 继续校验评论 9 张／动态 18 张、剩余数量、10 MiB、文件签名及像素限制。
- 请求持有面板、弱引用 owner，并监听该 owner 的 `willCloseNotification`。窗口关闭先注销请求／观察者，再结束 sheet，回传一次不可用错误。应用退出先注销 channel 并取消选择，再关闭 Flutter engine；重复关闭、同步取消回调、迟到选图回调不会重复完成或影响新请求。
- 面板确认返回前重新检查 view ID 是否仍指向同一 owner；视图退役后不插入旧图片。选图只读本地文件，沿用原草稿 generation 和账号 epoch 隔离，不自动上传或发布。
- 新原生文件已加入 Xcode Runner 编译 Sources；没有修改 Pub 缓存、依赖、锁文件、数据库或沙盒权限。

接口约束参考 Apple 的 [异步 sheet](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:))、[结束 sheet](https://developer.apple.com/documentation/appkit/nswindow/endsheet(_:returncode:)) 和 [窗口关闭通知](https://developer.apple.com/documentation/appkit/nswindow/willclosenotification)。实现由本项目编写，未复制插件代码。

## 验证

101 项定向 Flutter 测试通过，覆盖两个桌面平台的主／播放视图传参、无 owner、取消、原生失败／忙碌、非法返回、数量与图片校验，以及原评论、动态和私信交互。新增的 macOS 通道测试使用 mock messenger 和临时图片，不调用 AppKit，不能替代原生验收。

`tool/test_macos_image_picker.py` 的 2 项离线接线检查通过，核对 Xcode Runner 的真实编译引用、engine／view 约束和 engine 销毁前的选择器释放顺序。这些是接线约束检查，不计作 Swift 行为测试通过。

`macos/RunnerTests/RunnerTests.swift` 新增 8 项原生单元测试，使用隐藏 NSWindow 和 fake 面板验证：调用窗口与延后单次回传、缺失窗口、跨窗口重入、关闭／重复通知和迟到回调、视图退役、退出时同步取消回调、非法／超量选择，以及 deinit 取消。当前 Windows 主机及本机 WSL 均无 Swift／Xcode／AppKit，未编译或运行这些 XCTest。

`tool/check.ps1 -SkipPub` 完整通过，日志为 `build/macos-image-picker-check.log`（退出标记 `CHECK_EXIT=0`）：根应用与四个包格式、全仓 Dart 静态分析、离线测试及打包边界检查通过，依赖／锁文件未改动。

| 范围 | 通过 | 跳过 |
| --- | ---: | ---: |
| 根应用 | 5,819 | 13 |
| bili_api | 1,042 | 0 |
| bili_player | 243 | 10 |
| bili_danmaku | 161 | 0 |
| bili_mux | 5 | 10 |
| 合计 | 7,270 | 33 |

`BILI_MUX_LIBRARY` 未配置，10 项 mux 原生测试跳过；播放器 10 项原生／HTTP 媒体用例也按配置跳过，不计作原生媒体通过。上述 8 项 macOS XCTest 未执行，不包含在 33 项跳过统计中。定向测试日志为 `build/macos-image-picker-targeted.log`；`git diff --check` 和新增相对链接／源码路径检查通过。

完整检查运行期间出现了同期 Linux 标题栏改动；本任务保留这些文件，提交只包含 macOS 选图相关内容。上述数字是该次脚本的实际结果，不代表之后其他任务修改的重新验收。

按用户要求没有构建、启动或安装应用，也没有热重载运行实例。真实 macOS sheet 所属窗口、焦点与输入法恢复、播放中多次选择／取消、关闭播放窗口以及退出应用需后续在 Mac 上验证；本轮不声称偶发原生崩溃已获实机验证。Linux／Android／iOS 的原生选图实现未变。

主要命令：

```powershell
flutter test --no-pub test/features/comments/comment_image_picker_test.dart test/features/comments/comment_composer_test.dart test/features/dynamic/dynamic_compose_dialog_test.dart test/features/messages/message_center_ui_test.dart
python -m unittest discover -s tool -p test_macos_image_picker.py
.\tool\check.ps1 -SkipPub
```
