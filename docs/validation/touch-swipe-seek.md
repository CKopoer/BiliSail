# 触屏横向滑动进度与中央预览

日期：2026-10-26。

## 交互与边界

- 普通视频、影视和离线点播共用 `PlaybackPanel` 的画面横向触摸手势，普通／全屏、控制栏显示／隐藏时均可使用。右滑快进，左滑后退；按手势开始时的确认位置计算相对偏移，播放时钟继续前进不改变本次锚点。
- 滑过一个画面宽度最多调整 120 秒；不足 120 秒的视频按总时长计算，目标限制在 0 至总时长之间。累计位移后才转换为毫秒，避免高频小位移被逐次取整丢失；反向拖动可回到原位置，无惯性跳转。
- 画面中央显示至多 100 逻辑像素宽的缩略图，图下方显示「目标时间 / 总时长」。2026-10-27 按用户反馈缩小预览，时间行移除灰色背景和水平内边距，文字按缩略图宽度缩放对齐；白字配轻微黑色阴影。100 为宽度上限，受播放器可用宽度和高度共同约束，高度不足时按原比例继续缩小图片，时间行跟随；不同设备像素密度由 Flutter 换算。预览位于画面亮度遮罩上方，保留文字可读性。小画面与文字放大时收缩图片、保留时间。2026-11-03 起，索引加载中、无缩略图、图片首帧尚未就绪或加载失败时只显示时间，不显示灰色占位或预留图片高度；首帧就绪后再显示缩略图。离线内容没有本地缩略图索引时也沿用此降级，不额外抓帧。
- 底部进度条及控制栏隐藏时的细进度同步显示预览目标；预览不改写会话确认位置、续播记录、弹幕时钟或播放意图。松手隐藏中央预览卡片，仅提交一次 `PlaybackSession.seek`，进度条保留目标直到会话完成跳转，再交回确认时钟；失败或失效时清除目标。回到锚点不提交，已暂停的视频保持暂停。
- 直播、未准备好的源、无有效时长、隐藏页面及失活应用不接收横向进度手势。只有单指触摸且超过系统拖动阈值后才接受，鼠标／触控板保留原行为。横向／纵向与长按倍速由 Flutter 手势仲裁，按钮和原进度条位于画面手势层上方，沿用原操作。
- 手势取消、第二根手指、模态弹层、切源、时长变化、画面尺寸变化、切到后台或销毁均丢弃未提交目标。与「滑动调节亮度和音量」开关独立；关闭纵向调节不关闭横向进度。

## 性能与复用

`PlayerSeekControls` 仅在识别拖动时读取一次确认位置，不订阅高频播放时钟。拖动更新通过当前呈现视图拥有的局部 `ValueNotifier` 通知预览卡片和进度条，不通知整个会话或重建视频／弹幕。手势层和预览绘制隔离，底部控件沿用已有绘制边界，避免中央卡片布局更新向视频合成底层传播。

缩略图在手势开始时调用一次 `ensureStoryboard`，与时间轴悬停预览共享按源单飞、取消、账号代次及成功缓存。连续移动只二分查询已有索引并裁剪雪碧图，复用 `StoryboardThumbnail` 与有界图片缓存，不请求新的媒体源、不创建第二个播放器，也不执行截图或逐帧 seek。图片预算与协议沿用[时间轴缩略图记录](playback-timeline.md)。

只读参考了相邻 PiliPlus 的 `lib/plugin/pl_player/view/view.dart`（提交 `936072449e82e3d90c28c728c0087bf5136fa441`，GPL-3.0-or-later）中相对拖动、预览位置和松手提交的交互职责。实现独立编写，未复制源码或资源，未增加依赖或原生接口。

## 验证

- 手势、播放面板、纵向亮度／音量和时间轴共 268 项定向测试通过。新增回归覆盖相对位移与反向、短片／边界、高频小位移、鼠标／触控板／抖动排除、多指、取消／切源／模态／尺寸／时长／后台、隐藏再返回、拖动中销毁、迟到缩略图、小画面和文字放大。
- 普通／全屏与控制栏显示／隐藏的四组面板回归确认：连续移动不调用 seek、不重开源、不改变播放／暂停、音量或倍速；进度条跟随目标，松手只提交一次。结构探针确认画面子树不重建、视频合成底层不因连续预览重绘。额外验证切源后、下一帧重建前松手也不能提交旧目标。
- 已按 `tool/check.ps1 -SkipPub` 分阶段完成 `Lint`、`RootTests` 和 `PackageTests`：格式、完整静态分析与打包边界检查通过；根应用 2945、`bili_api` 478、`bili_player` 83、`bili_danmaku` 93、`bili_mux` 5，共 **3604 项测试通过**。根应用 13 项 Windows 符号链接测试因权限跳过；mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，均不计为通过覆盖。日志：[Lint](../../build/validation/player-touch-seek-lint.log)、[根应用](../../build/validation/player-touch-seek-root-tests.log)、[四个包](../../build/validation/player-touch-seek-package-tests.log)、[最终定向回归](../../build/validation/player-touch-seek-targeted-final.log)。最终呈现层顺序调整另行重跑相关定向回归与四个修改文件的静态分析。
- 工作区存在同期历史记录与视频卡片菜单修改，检查结果包含这些文件；本任务未改写无关修改，通过数量不能全部视为本功能新增覆盖。
- DTD 发现没有运行中的调试进程，热重载工具返回无活动应用连接。未构建或安装新测试包，未执行 Android／Windows 触屏／macOS 实机验收，也未测 Profile／Release 帧耗时、解码流畅度或触摸手感；结构探针不能替代这些测量。

## 2026-10-27 紧凑预览调整

- 缩略图宽度上限改为 100 逻辑像素；可用宽度减去两侧共 16 的留白，高度不足时按原比例继续缩小，图片太矮时只显示时间。时间行背景透明、无水平内边距，文字缩放后两端与图片对齐；仅图片保留圆角。
- 预览组件 24 项测试通过，包含 90×200 窄画面、180×70 矮画面的比例与边界检查，以及双倍文字、小画面降级。连同纵向手势、时间轴共 47 项组件测试及 12 项相关面板测试通过；修改文件静态分析、格式和差异检查通过。日志：[组件回归](../../build/validation/player-touch-seek-100-components.log)、[面板回归](../../build/validation/player-touch-seek-100-panel.log)。
- 根检查脚本已执行：格式、完整静态分析及打包边界检查通过；根应用 2949 项通过、13 项符号链接测试按权限跳过，3 项同期首页列表测试失败，分别位于 `feed_virtualization_test.dart`（追加卡片和重复视频更新）与 `recommendation_feedback_test.dart`（反馈仅刷新自身）。扩大播放面板回归时另有 8 项同期手机全屏方向测试失败。本次未修改这些文件，不宣称全量检查通过。日志：[根检查](../../build/validation/player-touch-seek-compact-check.log)、[扩大定向检查](../../build/validation/player-touch-seek-100-targeted.log)。
- 四个包的检查另行完成：`bili_api` 478、`bili_player` 83、`bili_danmaku` 93、`bili_mux` 5 项通过；10 项 mux 原生测试仍因未配置 `BILI_MUX_LIBRARY` 跳过。日志：[包检查](../../build/validation/player-touch-seek-compact-package-tests.log)。未构建或安装设备测试包，DTD 发现和热重载尝试均无活动调试连接；真机显示与性能未验收。

## 2026-10-29 松手进度闪动修复

- 原因：横滑松手先清空局部预览，再发起异步 seek，后端确认前进度条会重新显示旧播放位置，随后跳到目标。原面板测试的 fake engine 立即更新位置，未覆盖这个等待窗口。新增延迟确认和等待期间旧时钟采样的回归，修复前普通／全屏、控制栏显示／隐藏四组均失败。
- 修复：横滑提交回调返回会话 seek 的 Future；松手立即结束中央卡片显示，进度条继续使用局部目标，等待跳转完成后在 `finally` 清除。复用手势 revision 隔离迟到完成，旧 seek 不能清除后续拖动或跳转的目标；切源、失活、后台与销毁继续使旧预览失效。仍只提交一次 seek，不将预览写入会话或弹幕时钟。
- 手势、时间轴、纵向调节和完整播放面板共 344 项定向测试通过，覆盖跳转等待、旧位置采样、失败清理、连续拖动／跳转及失效后的迟到完成。日志：[组件与面板回归](../../build/validation/touch-seek-release-components.log)。
- `tool/check.ps1 -SkipPub` 全部通过：格式、完整静态分析、打包边界检查通过；根应用 3359、`bili_api` 492、`bili_player` 96、`bili_danmaku` 116、`bili_mux` 5，共 4068 项测试通过。根应用 13 项 Windows 符号链接测试因权限跳过；mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生验证。工作区包含同期 Windows 安装包修改，本次保留且未纳入提交。日志：[全仓检查](../../build/validation/touch-seek-release-check.log)。文档相对链接与 `git diff --check` 通过。
- 未构建或安装测试包；`adb devices -l` 无连接设备。DTD 未发现活动调试应用，热重载尝试返回无连接；未执行 Android／Windows 触屏／iOS／macOS 实机验收或 Profile／Release 性能测量。

## 2026-11-02：视频底层手势抢占（Issue #58）

- [#58](https://github.com/CKopoer/BiliSail/issues/58) 反馈 Android 横滑进度、纵滑亮度／音量没有提示，偶尔成功。核对[固定的视频插件](piliplus-dependencies-2026-11-01.md)发现，`media_kit_video` 的 `Video` 在 `NoVideoControls` 下仍挂载 `InteractiveViewer`，默认允许缩放，Android 的局部 `touchSlop` 为 4。应用画面点击层使用 `HitTestBehavior.translucent`，Stack 会继续命中下面的视频组件；其缩放识别器可早于应用的方向拖动识别器赢得手势竞争，随后应用横滑／纵滑被取消。事件若一次跨过应用阈值，也可能由应用先获胜，因此表现为偶发成功。长按倍速不是这次抢占的来源。
- 将共享画面点击层改为 `HitTestBehavior.opaque`，使触摸事件止于应用画面层。其父级的进度、亮度／音量和长按倍速仍在同一命中路径内；上层按钮、进度条与弹层继续独立处理输入。未修改播放器依赖、原生解码、手势阈值或长按时限。
- 原来的 fake 视频仅绘制黑色区域，缺少真实视频组件的缩放识别器，因而既有快速滑动测试不能复现。新增与固定插件相同的低阈值 `InteractiveViewer` 夹具，用连续小位移覆盖 390dp 手机画面、普通／全屏、控件显示／隐藏；修复前 4 组均无法提交横滑，修复后均通过。用例还验证长按释放后的双向进度、双向音量和双向亮度、底层缩放未触发、暂停意图／倍速／源代次不变，且没有重新打开或增加视频 surface。
- 手势组件和完整播放面板 **447 项定向测试通过**，包含原有长按固定／解除倍速、点击／双击、控件和生命周期回归。日志位于忽略目录 `build/validation/issue-58-interactive-before.log`、`issue-58-interactive-after.log` 与 `issue-58-targeted.log`。
- `tool/check.ps1 -SkipPub` 全量通过：格式、静态分析与打包边界检查通过；根应用 4010、`bili_api` 544、`bili_player` 131、`bili_danmaku` 153、`bili_mux` 5，共 **4843 项测试通过**。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生覆盖。日志为 `build/validation/issue-58-check.log`。
- `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 构建通过，复用既有 Android arm64 mux 资产，普通 `lib/main.dart` 入口的 AOT 测试包输出为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`。脚本已校验 `dev.bilisail.bilisail.test`／`BiliSail 测试版`、`1.2.6+3`、不可调试、arm64 ABI 和既有开发签名，未安装；日志为 `build/validation/issue-58-android-release.log`。没有连接 Android 设备，未验收实际窗口亮度、响度、触摸手感或性能。DTD 发现无活动调试进程，热重载尝试因无连接而未完成；其他平台实机未测。

## 2026-11-03：缩略图就绪后再显示

- 触屏横滑时，索引或图片尚未加载好、无可用缩略图或加载失败均只显示「目标时间 / 总时长」，不显示灰框、图标或保留图片高度。首帧解码完成后显示当前目标的缩略图；滑到尚未加载的另一张雪碧图时再次收起图片，滑回已缓存图片时立即恢复。普通／全屏、视频／影视／离线点播沿用共享组件；桌面时间轴保留原占位行为。
- 触屏进度与时间轴共 48 项组件测试通过，覆盖时间独显、延迟首帧、换图等待、加载失败、缓存返回、迟到索引、小画面比例及原有手势与跳转行为。现有雪碧图像素裁剪回归通过。日志为 `build/validation/touch-seek-thumbnail-targeted-final.log`。
- `tool/check.ps1 -SkipPub` 全量通过：格式、完整静态分析和打包边界检查通过；根应用 4112、`bili_api` 547、`bili_player` 142、`bili_danmaku` 161、`bili_mux` 5，共 4967 项测试通过。13 项 Windows 符号链接测试因权限跳过；10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生覆盖。日志为 `build/validation/touch-seek-thumbnail-check.log`。
- 未构建或安装测试包，未执行真机触屏显示或性能验收。DTD 未发现活动调试进程，热重载尝试因无连接而未完成。
