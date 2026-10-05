# 用户页、倍速与标签播放

日期：2026-10-05。当前未提交工程上的增量修正；相邻参考仓库只读。

## 实现与原因

- 用户空间顶部拆分身份资料、统计、下划线导航和投稿工具条。关注/粉丝继续进入对应只读列表，统计统一字号、内边距和基线；宽屏排序靠左、搜索靠右，窄屏或大文字缩放时分行。沿用已有用户资料、投稿、动态、收藏夹及关系列表，不增加未支持的操作。
- 加减速使用 `0.5、0.75、1.0、1.25、1.5、2.0、3.0x` 相邻档位，菜单与默认/长按临时倍速设置共用集合，首尾不再越界；旧连续设置归到最近档位，无需改变 SQLite 表结构。此前快捷键按 0.25 增减、菜单最高 2x，设置连续滑块还会产生菜单外的值。单引号逻辑键兼容补齐，保持自定义、禁用、输入框与弹窗屏蔽；快捷键调速显示 1.5 秒提示，控制栏隐藏时也可确认变化。
- 切普通标签自动暂停来自 `PlaybackSession.deactivate` 的显式 `engine.pause`，此前测试也固定了该策略。隐藏现在只释放 surface/绘制/快捷键，恢复长按临时倍速并保存进度；解析中隐藏也按原播放意图完成。返回同 owner 不重新 open、seek 或 play，切另一个视频才保存原 owner 快照并复用唯一 engine。
- 关闭正在播放的标签停止视频，关闭其他标签只清理自己的快照；账号切换取消播放与旧请求。移动系统后台仍暂停当前媒体 owner，即使该视频页已经被普通标签遮住。本轮不新增后台服务、PiP 或多路音频。
- 长按恢复与 owner 切换并发时，保留常驻倍速直至恢复命令完成，避免临时 3x 写入工作区快照；新源与新长按隔离迟到的清理。

## 参考与复现边界

实际查看本机 UWP 的 UP 主页，确认下划线导航、紧凑身份入口、排序左/搜索右的位置；阅读相邻 `UserInfoPage.xaml`、`PlayerControlToolBarWithComboBox.xaml.cs`、`PlayerControlToolBarWithSlider.xaml.cs` 的布局与按菜单索引加减速语义。独立实现 Flutter/Dart，不复制新增资源或 C#。来源见 [参考文档](../references.md)。

在修改前启动现有 `build/windows/x64/runner/Profile/bili_lite.exe`，用 Windows Computer Use 注入 F2 和单引号，公开视频速度依次从 1.0 到 1.25、1.5，当前 Profile 构建能收到这些事件。Flutter 3.47.6 Windows 引擎将原生 F1/F2 和 VK 186/222 映射到对应逻辑键；`quoteSingle` 是未覆盖的另一逻辑键形态，不能将它认定为所有 Windows 倍速失效的唯一原因。运行较旧构建、焦点和输入法等仍须按实际运行包区分。

## 本轮验证

- `tool/check.ps1 -SkipPub` 最终复验通过：根应用 258、`bili_api` 76、`bili_player` 16、`bili_danmaku` 5 项，共 **355 项**；四处格式检查和静态分析均通过。依赖未修改，复用锁定依赖；最终日志为 `artifacts/profile-playback-final-check.log`。
- 用户页 29 项测试通过，新增回归覆盖统计对齐与点击、真实控制器接线、320/375 宽与两倍文字、可滚动导航、排序/搜索行为及宽屏左右分布。播放与设置回归覆盖所有倍速档位/边界/旧菜单外值、3x 菜单和持久化、隐藏控制栏提示及两种引号逻辑键；会话测试覆盖隐藏解析、普通标签继续播放、当前 owner 关闭/账号清理、旧异步和并发临时倍速恢复。移动系统生命周期以 fake 平台与 retained owner 行为测试验证。

- `tool/test-windows-media.ps1` 最终通过：分轨 headers/重定向/Range、隔离安全存储、响应式控件/六次全屏、隐藏标签持续推进/返回画面/双视频快照及独立进程 HTTP 403 脱敏诊断。公网媒体分支未启用，实际执行 **5 项本地原生验证**。原生速率验证包含 1.5→2→3、上下边界、F1/F2 与 Windows 引号/分号，source generation 不变。日志为 `artifacts/profile-playback-windows-passed.log`。
- 原生回归修正了两个等待/模拟问题：Windows 按键模拟器不支持 `quoteSingle`，该形态保留构造事件单测，Windows native 用例使用实际 VK 222 对应的 `quote`；后台持续播放时“playing”已成立，返回还需显式等待 surface 挂载，不能拿旧暂停策略的等待条件判断画面。
- 初期原生测试有进程提前退出，Windows dump 符号指向 Flutter 的 `AXNodeData::GetStringAttribute` / `FlutterPlatformNodeDelegate::ChildAtIndex`。隔离测试与最终完整套件通过，但未确定该间歇性无障碍引擎退出的完整根因；临时排除倍速提示语义的对照没有解决问题，已撤回，保留原有及提示无障碍信息。相关失败日志为 `artifacts/profile-playback-windows.log`、`artifacts/profile-playback-windows-retry.log` 和 `artifacts/profile-playback-native-controls-stable.log`，不将其归为已修复的协议或播放器故障。

- `flutter build windows --release --no-pub -t lib/main.dart` 通过，新版入口为 `build/windows/x64/runner/Release/bili_lite.exe`；日志为 `artifacts/profile-playback-build-windows.log`。
- `flutter build apk --debug --target-platform android-arm64 --no-pub -t lib/main.dart` 通过，产物为 `build/app/outputs/flutter-apk/app-debug.apk`；日志为 `artifacts/profile-playback-build-android.log`。
- 启动新版 Windows Release，实际查看公开 UP 页：身份资料、关注/粉丝/获赞/投稿基线、下划线导航和排序左/搜索右已核验，投稿正常加载。公开视频实际使用 F2 从 1.5→2→3，F1 从 3→2，均显示倍速提示；从视频切到 UP 页再返回，进度从约 6:31 推进至 6:50，保持播放，随后主动暂停测试视频。
- 当前保存的加减速绑定为 `F1 / Semicolon`、`F2 / Quote`。本轮末次 Computer Use 的 `apostrophe` 注入未改变倍速，快捷键录制弹窗也未识别该输入，因此不将这一注入结果视为实键验证通过；Windows native 构造的 `quote` 事件及两种逻辑键单测已通过。中文输入法下的物理标点键仍需实键复核，本轮未改写用户绑定。

本机没有 Android/macOS 目标设备，Android 播放与系统生命周期、macOS 构建与播放均未实测。没有新增 profile/release 性能测量，也不从 Windows 结果推导其他平台支持状态。
