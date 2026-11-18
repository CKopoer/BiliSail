# Windows 评论选图与窗口归属

日期：2026-11-18。

## 定位与证据

共享 `CommentsPanel` 原先只把剩余图片数量传给 `pickCommentImages`，桌面统一调用 `file_selector.openFiles`。根锁文件固定的 `file_selector_windows 0.9.3+6` 在 `RegisterWithRegistrar` 中通过 `registrar->GetView()` 获取隐式主视图，`GetRootWindow` 再取其顶层 HWND，没有接收发起选图的 view ID。因此双标签独立播放窗口中的评论选图也会使用主窗口作为系统对话框 owner。

该插件在平台消息处理函数中同步执行 `IFileDialog::Show`，且没有进程级在途选择保护，无法保护其他窗口的额外选图调用。现行 Flutter Windows 平台／UI 合并线程下，这条路径还让 Shell 模态循环和 Flutter 平台回调共用调用栈。此次替换该调用路径并补齐重入与关闭边界；这些是源码确认的风险，尚无现场栈证明它们就是用户偶发崩溃的触发链。

本机最近七天的 Windows Application 事件包含 2026-11-18 的 `AppHangB1`／`AppHangTransient`，以及 2026-11-17 的 NVIDIA 驱动模块访问异常。没有与用户此次选图操作直接对应的崩溃栈，不能据此断言所有偶发崩溃已被同一原因解释，也不能将驱动事件归因于选图。

## 实现

- 评论、动态和私信在点击图片按钮时读取 `View.of(context).viewId`，通过既有注入端口交给共享本地图片适配器。没有把 Flutter 类型或 HWND 放进领域模型。
- Windows 使用 `bilisail/image_picker`；runner 按 view ID 查询原生 Flutter 视图，再取 `GA_ROOT`。无效／已关闭视图返回 `window_unavailable`，不回退主窗口。其他平台沿用原选择器。
- Windows 系统 `IFileOpenDialog` 在请求独有的 STA 工作线程中创建、调用和释放；对话框 owner 是调用窗口，支持 JPG／JPEG／PNG／GIF 多选。COM 调用逐步检查 HRESULT；异常和路径读取失败不转换为空成功，原生选择数量有 18 张硬上限。
- 一个进程仅允许一个在途请求。重复打开返回 `picker_busy`；只有明确的 `ERROR_CANCELLED` 返回空列表。路径仅作为当前调用结果传回，不记录到日志或数据库。
- 平台线程定时检查请求完成和调用视图存活。窗口关闭后，通过工作线程的控制窗口取消 Shell 对话框；关闭 channel 时先停用回调，再取消并 join 工作线程，最后释放 engine。等待期间只处理跨线程同步窗口消息，避免 owner 消息与 join 相互等待；不分离后台线程，也不从工作线程调用 Flutter messenger。
- Dart 保留剩余数量、10 MiB、文件签名、尺寸与总像素检查。已有草稿 generation、评论目标和账号 epoch 检查继续丢弃迟到结果。选择不上传，发布仍由显式用户动作触发。

原生接口约束参考 Microsoft [Common Item Dialog](https://learn.microsoft.com/en-us/windows/win32/shell/common-file-dialog)：UI 对话框使用 STA，`Show` 接受 owner HWND。本次实现自行编写，没有修改 Pub 缓存、复制插件实现或增加第三方依赖。

## 验证与待验收

定向 Flutter 测试 93 项通过：Windows 主／播放视图参数、取消、无 owner、原生失败、非法返回、数量和图片校验；真实独立测试 render view 内评论按钮的 view ID、重复点击、关闭组件后的迟到结果；原有评论草稿、动态及私信交互回归。

`tool/test-windows-image-picker.ps1` 的独立 C++ 单元测试通过，使用真实线程、STA、隐藏测试 HWND 和 fake Shell 对话框，覆盖主／播放／子视图 owner、平台线程回传、取消与错误分类、部分路径失败清理、创建异常、重入、调用视图退役，以及有在途请求时销毁 channel 的取消、join 和回调注销。测试按 `/W4 /WX` 及 runner 对应预处理定义编译；只编译测试程序及本次平台实现，链接已有 Flutter wrapper，不构建应用、不显示系统选图界面。

`tool/check.ps1 -SkipPub` 完整通过：根应用和四个包格式、全仓静态分析、离线测试及打包边界脚本均通过，未改动依赖或锁文件。结果如下：

| 范围 | 通过 | 跳过 |
| --- | ---: | ---: |
| 根应用 | 5,811 | 13 |
| bili_api | 1,042 | 0 |
| bili_player | 243 | 10 |
| bili_danmaku | 161 | 0 |
| bili_mux | 5 | 10 |
| 合计 | 7,262 | 33 |

`BILI_MUX_LIBRARY` 未配置，10 项 mux 原生用例跳过；播放器 10 项原生／HTTP 媒体用例也按配置跳过，不计原生播放或封装通过。最终测试 fixture 的路径改用 `package:path` 后，又单独通过 24 项图片适配器测试及该文件静态分析。`git diff --check` 和新增相对文档链接／源码路径核对通过。完整日志为忽略目录下的 `build/image-picker-check.log`、`build/image-picker-dart-final.log`。

主要命令：

```powershell
flutter test --no-pub test/features/comments/comment_image_picker_test.dart test/features/comments/comment_composer_test.dart test/features/dynamic/dynamic_compose_dialog_test.dart test/features/messages/message_center_ui_test.dart
.\tool\test-windows-image-picker.ps1
.\tool\check.ps1 -SkipPub
```

按用户要求没有构建、启动或安装应用，也没有热重载运行实例。真实系统选择框的焦点、连续多次选择／取消、中文输入法组合、播放中选图及偶发崩溃消除情况由用户后续自行构建并实机验收。Android／macOS／Linux 未做设备验收；单元测试不代表这些平台的系统选图已通过。
