# 播放器双指缩放与中部全屏手势

日期：2026-11-06。需求：[GitHub #64](https://github.com/CKopoer/BiliSail/issues/64)。按用户要求参考 PiliPlus 的相关手势，不增加画面旋转。

## 行为和采用范围

- 普通／全屏、视频／影视／直播／离线播放共用：双指缩放 0.75–2 倍，双指移动画面；控件显示时，变换后的画面提供“还原画面”。关闭“双指缩小视频”后下限为 1 倍，放大仍可使用。
- 单指中部三分之一区域上滑进入全屏，下滑退出；在松手且净位移达到 36 逻辑像素时确认一次。可独立关闭或设置反向。非全屏下滑不导航离开播放页，与 PiliPlus 的进入／退出全屏职责保持一致。
- 左右各三分之一区域继续调节亮度／音量；中部不再调节音量。横滑进度、长按倍速、触屏双击播放／暂停、鼠标双击全屏及滚轮音量沿用既有行为。第二根手指落下会取消当前进度预览、亮度／音量滑动和临时长按倍速；剩余单指继续移动不提交进度或触发全屏。
- 只变换视频输出，弹幕、字幕和控件的位置／字号保持；放大后的输出裁剪在播放器内。平移留有至少一部分可见画面，避免完全拖出视口。
- 同一播放页的普通／全屏共享变换状态，用相对视口的平移量适应尺寸变化。换源和进入听视频重置；页面隐藏、换源、后台、模态层、尺寸变化和指针取消会取消旧触摸序列。变换不发出播放／暂停／seek／重新打开源命令，不创建第二个 engine 或 surface。

只读参考本机 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的：

- [播放器视图](../../../PiliPlus/lib/plugin/pl_player/view/view.dart)：`_videoWidget`、`_onPanUpdate`、还原入口与缩放限制。
- [交互视图](../../../PiliPlus/lib/common/widgets/gesture/mouse_interactive_viewer.dart)：单指与多指职责分开、缩放焦点和位移。
- [播放设置](../../../PiliPlus/lib/pages/setting/models/play_settings.dart)：缩小开关、中部全屏与手势反向。

上游应用采用 GPLv3；本次只借鉴交互行为，独立编写状态、触摸识别与 Flutter 组件，没有复制上游源码或资源、修改相邻仓库或新增依赖。现有 media-kit 固定来源、锁文件和原生补丁保持。

## 实现与设置兼容

- [PlayerPictureController / PlayerPictureControls](../../lib/features/playback/presentation/player_picture_controls.dart) 持有有界缩放和位移，双触点识别参与手势竞争，触摸接管后独立处理画面变换；视频 child 在更新中复用。
- [PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 在页面内持有唯一变换控制器，普通／全屏共用，变换只包裹 `VideoSurface`；播放会话继续由原页面持有。
- [PlayerSwipeControls](../../lib/features/playback/presentation/player_swipe_controls.dart) 按初始触摸位置选择三个纵向区域，第二触点取消单指动作；中部切全屏与侧边亮度／音量分别启停。
- 新设置 `playerShrinkVideo=true`、`playerFullscreenGesture=true`、`playerFullscreenGestureReverse=false` 使用既有设置控制器和仓储。`preferences.v1` 快照 schema 从 37 升至 38，SQLite 表结构不变。缺失／非法值回退默认，保存失败沿用既有回退，恢复默认一致，旧亮度／音量开关保留。

## 验证

- 496 项定向离线测试通过，覆盖共享播放面板、双指几何／边界／局部更新、手势接管、生命周期取消及设置迁移／落盘／恢复默认。日志：`build/validation/issue-64-targeted.log`。
- `tool/check.ps1 -SkipPub -Stage Lint` 通过：根应用及四包格式、静态分析、打包边界脚本；四包离线测试 973 项通过（bili_api 659、bili_player 148、bili_danmaku 161、bili_mux 5）。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生通过。
- 初次根应用全量检查的两个失败均为新增设置后的测试假设：`default_dynamic_tab_test.dart` 的快照版本断言同步为 38；`settings_screen_test.dart` 在断言前滚动至新位置的设置项。修复后 49 项设置回归通过。最终按 `tool/check.ps1 -SkipPub -Stage RootTests -TotalShards 2 -ShardIndex 0/1` 完成全部根应用测试：2275 + 2127 = **4402 项通过**，13 项 Windows 符号链接权限用例跳过；连同四包共 **5375 项离线测试通过**。
- Android arm64 普通入口开发 Release 和专项 Profile APK 均构建成功，包名 `dev.bilisail.bilisail.test`、名称“BiliSail 测试版”、版本 `1.2.6+7`／versionCode `12607`，普通 Release 已验证 AOT、不可调试及本机开发签名；Profile 与其签名／版本一致。产物及 SHA-256 见 `build/development/android-arm64/` 和 `build/validation/android-player-gestures/`。
- 构建后设备 `950c21ca` 在安装前断开，用户明确要求本轮跳过实机。**没有安装专项 APK、没有修改设备常亮值，也未执行 native picture 或窗口／亮度设备用例。** 不将构建通过等同于纹理、手感或设备验收；本轮不作性能结论。Windows／macOS／iOS／Linux 设备运行同样未验证。后续用户明确要求不再追加构建，以单元测试通过后提交为交付范围。
- 复查另修复“侧边音量／亮度提示在开始中部手势后残留”：中部手势开始即清除旧提示；最终 25 项触摸组件回归通过，最终静态分析无问题。
- 无可连接的 DTD／调试进程；已尝试热重载，工具返回没有活动应用，未完成运行中热重载。
- 日志：`build/validation/issue-64/{lint,final-analyze,root-shard-0-final,root-shard-1,package-tests,settings-regression,final-touch-tests,android-build,android-final-build,android-device}.log`。文档相对链接、PowerShell 语法和 `git diff --check` 通过。

Android 设备验证入口：

```powershell
.\tool\test-android-player-gestures.ps1 -DeviceId <adb-device-id>
```

脚本先构建并保留普通入口的开发 Release，再安装同一签名的测试 Profile，仅操作 `dev.bilisail.bilisail.test`。测试使用本地 HTTP 分轨样片和真实 `MediaKitEngine`，检查纹理缩放后像素改变、全屏往返保留变换、还原及源／位置／播放意图不变；随后执行既有视频／直播 fake engine 的实际窗口旋转、亮度和音量测试。`finally` 覆盖恢复普通入口 Release、启动并恢复设备常亮值，移除测试端口转发。测试不使用真实账号、不访问在线媒体，不以自动注入触点替代主观手感或长期性能验收。
