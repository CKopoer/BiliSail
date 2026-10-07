# 快捷键重构实施与验证

日期：2026-10-07。依据[重构设计](refactor-design.md)实施；运行期代码已接入，真实键鼠与跨平台实机验收仍开放。

## 当前结构

- [AppInputHost](../../lib/core/presentation/app_input_host.dart) 位于根 Navigator 外层，拥有唯一业务键盘提前监听和鼠标全局路由。InputNormalizer 共用录制／执行键名表，Quote／quoteSingle 统一，修饰键精确匹配；未知逻辑标识可回退到两个标点物理位置，合法其他 Unicode 布局不会强行解释为 US 标点。
- [ShortcutDispatcher](../../lib/core/input/shortcut_dispatcher.dart) 为纯 Dart 泛型内核；[命令目录](../../lib/domain/shortcut_command.dart) 保持 20 个动作和默认别名；[组合根](../../lib/app/shortcut_coordinator.dart) 编译设置、目录归属及固定／图片绑定。输入只选择一个目标；重复注册返回 duplicateTarget，边界／忙碌仍消费已认领序列。
- [InputScope 与目标注册](../../lib/core/presentation/input_scope.dart) 提供可释放句柄、source revision、编辑／控件保护和非 Route 弹层屏障。根／Shell Navigator observer 共用路由账本，包括 requestFocus:false 的弹窗。普通弹窗隔离底层；全屏属于呈现，保留所属页的工作区／页面／媒体命令。
- [PlaybackShortcutController](../../lib/features/playback/application/playback_shortcut_controller.dart) 由 PlaybackPanel owner 持有，普通／全屏视图共享；视图只保留绘制和控件行为。长按达到阈值即标记正在加速，异步 begin 未完成时释放也不会变成短按 seek；失焦、弹层、切页、换源、设置修改、呈现交接均可取消。
- PlaybackSession 保存待确认音量／永久倍速目标；[MediaCommandPump](../../lib/features/playback/application/media_command_pump.dart) 将原生调用限制为一个进行中与一个最新目标。快速离散调速从目标值推进；失败清除本代次待处理动作，不自动重放。临时开始／恢复与永久调速共享协调规则，临时倍速不写共享记忆。

旧 shell／route／player／UGC／PGC 的业务键盘监听、鼠标 Listener、Expando 去重和固定循环 CallbackShortcuts 均已移除。[keyboard_shortcuts.dart](../../lib/core/presentation/keyboard_shortcuts.dart) 只保留侧键名称的展示格式化。[页面选集契约](../../lib/shared/ui/playback_page_commands.dart) 移到 shared/ui，避免 core 依赖应用命令；播放器按钮复用该契约，输入执行由页面注册负责。

## 行为与设置

- 真实按下冻结物理身份、目标句柄及媒体代次；修饰键先释放不影响对应 KeyUp。无有效 Down 的 Repeat／Up 不创建动作，合成事件只清理。已消费序列的尾部不落入新标签或下一层弹窗。
- 鼠标按 view／device 的按钮变化识别侧键边沿，支持与普通按钮同时按及 Move 中新增按钮位；双侧键同时新增不任选其一。初始 Move 同步状态，按住跨页面重建只执行一次；失焦／Cancel／移除清理状态。此范围为 Flutter 客户区。
- 输入时仅明确绑定的侧键或 Ctrl／Meta 关闭组合、固定标签循环可越过编辑保护；普通 W／F8 关闭绑定仍保留输入。控件的 Enter／Space 激活和未绑定／禁用按键交回 Flutter。
- 总开关控制 20 个可配置动作，固定 Ctrl+Tab／Ctrl+Shift+Tab 和图片查看器操作独立。图片命令通过顶部局部作用域执行，Esc 一次只关闭图片层，保留翻页／缩放重复和局部 Ctrl+滚轮／拖动。
- 录制使用同一入口，整个 Flutter 客户区捕获侧键；Escape 可录制，取消使用按钮。候选按键释放后才退出独占，Ctrl+W／Ctrl+Tab 不执行底层命令。保存失败保留编辑草稿与旧生效配置，成功后统一替换编译表并取消旧长按。
- 保留 preferences.v1 快捷键 JSON 的动作 name、bindings 数组、disabled、enabled 和播放参数；没有新增依赖、偏好版本或 SQLite migration。空列表仍为解除绑定；合法旧设置 round-trip 不变。损坏项局部停用，冲突键从双方移除，设置列出待修复项；用户未确认快捷键设置前仍保留原快照供后续修复。
- 设置提供默认关闭、只在当前进程内存在的诊断，最多 256 条，关闭／离开该设置页清空。记录相对时间、设备／view、phase、逻辑／物理标识或按钮位、归一化匹配方式、命令、作用域、目标注册代次及分发／完成原因；编辑器和普通模态区屏蔽具体键值及按钮位，没有字符／文本／凭据日志或上传。播放器提示从当前设置读取首个有效绑定。

## 页面刷新

刷新只归活动页面，进行中重复触发合并；播放器不再独立解释 F5／侧键为 retry。首页保留频道，搜索使用 refresh 保留当前筛选，历史、消息、下载、用户页调用各自刷新。UGC 复用相关推荐／标签刷新与本页播放重试组合；PGC 先重新加载剧集，同一选择与源代次稳定才重试，变更选集由原激活路径开源；直播由房间 controller.load 驱动目标，不另发 retry。离线保留本地源 retry；设置等无能力页不注册空回调。页面销毁／账号和 source generation 继续由已有控制器及会话隔离。

## 验证

本轮实现基线执行 `tool/check.ps1 -SkipPub`，通过根应用与三个包的格式、静态分析和测试：根应用 1,020 项、bili_api 285 项、bili_player 22 项、bili_danmaku 32 项，共 1,359 项。随后工作区同步增加了评论文本改动；末次完整检查格式与静态分析通过，根应用 1,034 项通过、1 项失败，停止于评论 URL 标点用例 `keeps punctuation outside links and balanced path brackets inside`：链接末尾的全角 `）` 未移出链接。该同期改动保留交由所属任务处理，不能将此轮完整检查记为全通过。

最终单独运行快捷键相关的输入、工作区／真实路由、页面刷新、播放会话／视图、设置／录制、图片、PGC 与视频页面回归，共 247 项全部通过。文档本地链接检查无缺失。

行为回归覆盖：

- [纯分发器](../../test/core/input/shortcut_dispatcher_test.dart)与[输入适配](../../test/core/presentation/keyboard_shortcuts_test.dart)：物理序列冻结、修饰键释放、合成／无 Down 尾部、源代次变化、重复注册、诊断容量与键值屏蔽、标点布局和鼠标组合按钮／Move 边沿。
- [工作区外壳](../../test/app/workspace_shell_test.dart)、[真实路由](../../test/app/workspace_router_test.dart)与[播放器](../../test/features/playback/playback_panel_test.dart)：首页保护、编辑关闭例外、隐藏页面、失活后的旧重复、关闭全屏及旧尾部、Ctrl+Tab 重复与总开关、普通弹窗／图片层、刷新和控件焦点。
- [页面刷新事务](../../test/app/shortcut_page_refresh_test.dart)：真实 GoRouter／WorkspaceActivity／PlaybackPanel 组合下，延迟 PGC 加载保持选择时只 retry 一次，选择改变只由激活开源；直播原目标保持与目标改变均不额外 retry；进行中的二次刷新合并，并验证房间加载失败／播放器失败不能记为成功。
- [会话](../../test/features/playback/playback_session_test.dart)与[设置保存](../../test/features/settings/settings_controller_test.dart)、[录制](../../test/features/settings/shortcut_settings_section_test.dart)：延迟和失败引擎、快速相对调速／音量、有界待执行目标、提前释放长按、永久选择与临时倍速记忆隔离；持久化成功才生效、失败保留草稿、混合设置写入不覆盖新快捷键、Escape／Ctrl+W／Ctrl+Tab 录制尾部。

Windows 原生媒体套件通过播放／全屏／工作区 8 项、故障诊断 1 项及同期预览缓冲 1 项。首次套件有两项未通过，原因是原生测试直接构造 MaterialApp，未接入新的 AppInputHost；已将相关入口迁移到与根应用相同的输入宿主／observer，重跑通过。原生测试使用本地媒体，不提交真实账号写请求。`flutter build windows --release --no-pub` 通过，输出 `build/windows/x64/runner/Release/bilisail.exe`；flutter_inappwebview_windows 的既有 CMP0175 CMake 警告未阻止构建。

自动事件均由 Flutter 测试框架注入，未采集物理侧键／中文输入法失败轨迹。没有验证驱动未交付给 Flutter 的事件、系统标题栏／原生 WebView／窗口外操作、Windows 发布包实键矩阵，也未做 macOS Ctrl／Meta、真实侧键／原生全屏或 Android 触控／返回／外接设备实机验收。重构解决已确认的输入所有权与执行一致性问题，不能据此声称已确认所有物理输入间歇失效的根因。未增加原生键盘 Hook 或系统全局热键。

工作区同期有预览播放器／原生首帧、评论和图标资源改动，本次保留原有修改；完整检查基于共同的当前工作区。相邻参考仓库与三个包未由本次快捷键重构修改。
