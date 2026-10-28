# 快捷键重构实施与验证

日期：2026-10-07。依据[重构设计](refactor-design.md)实施；运行期代码已接入，真实键鼠与跨平台实机验收仍开放。

## 当前结构

- [AppInputHost](../../lib/core/presentation/app_input_host.dart) 位于根 Navigator 外层，拥有唯一业务键盘提前监听和鼠标全局路由。InputNormalizer 共用录制／执行键名表，Quote／quoteSingle 统一，修饰键精确匹配；未知逻辑标识可回退到两个标点物理位置，合法其他 Unicode 布局不会强行解释为 US 标点。
- 2026-10-29 补充 Flutter 控件手势的窗口边界清理：沿用同一 pointer route 跟踪本 view 未结束的鼠标指针，失焦／失活、迁移、设备移除及销毁时调用 `cancelPointer`。业务快捷键序列取消和控件 tap／drag 取消分别完成，避免丢失 Up 后只有曾按下的侧栏按钮持续失效；迟到 Up 不执行动作。模拟 Command+W 关闭双窗口后的失败复现、修复及 macOS 实机验证边界见[侧栏记录](../validation/wide-sidebar.md#多标签按钮统一与关闭播放后侧栏交互2026-10-29)。
- [ShortcutDispatcher](../../lib/core/input/shortcut_dispatcher.dart) 为纯 Dart 泛型内核；[命令目录](../../lib/domain/shortcut_command.dart) 提供 22 个动作和平台默认别名；[组合根](../../lib/app/shortcut_coordinator.dart) 编译设置、目录归属及图片绑定。输入只选择一个目标；重复注册返回 duplicateTarget，边界／忙碌仍消费已认领序列。
- [InputScope 与目标注册](../../lib/core/presentation/input_scope.dart) 提供可释放句柄、source revision、编辑／控件保护和非 Route 弹层屏障。根／Shell Navigator observer 共用路由账本，包括 requestFocus:false 的弹窗。普通弹窗隔离底层；全屏属于呈现，保留所属页的工作区／页面／媒体命令。
- [PlaybackShortcutController](../../lib/features/playback/application/playback_shortcut_controller.dart) 由 PlaybackPanel owner 持有，普通／全屏视图共享；视图只保留绘制和控件行为。长按达到阈值即标记正在加速，异步 begin 未完成时释放也不会变成短按 seek；失焦、弹层、切页、换源、设置修改、呈现交接均可取消。
- PlaybackSession 保存待确认音量／永久倍速目标；[MediaCommandPump](../../lib/features/playback/application/media_command_pump.dart) 将原生调用限制为一个进行中与一个最新目标。快速离散调速从目标值推进；失败清除本代次待处理动作，不自动重放。临时开始／恢复与永久调速共享协调规则，临时倍速不写共享记忆。

旧 shell／route／player／UGC／PGC 的业务键盘监听、鼠标 Listener、Expando 去重和固定循环 CallbackShortcuts 均已移除。[keyboard_shortcuts.dart](../../lib/core/presentation/keyboard_shortcuts.dart) 提供侧键、Command／Option 和方括号的展示格式化。[页面选集契约](../../lib/shared/ui/playback_page_commands.dart) 移到 shared/ui，避免 core 依赖应用命令；播放器按钮复用该契约，输入执行由页面注册负责。

## 行为与设置

- 2026-10-24：关闭当前标签页默认绑定为 `Ctrl+W, MouseBack`，恢复默认使用同一组键位。保留已保存的关闭绑定（含空绑定）；旧配置若已将 `MouseBack` 分配给其他动作，则保留该自定义操作，关闭标签继续使用 `Ctrl+W`。快捷键页底部只保留标签切换提示，移除 UWP 参考和未移植功能说明。
- 上述默认值调整通过 `tool/check.ps1 -SkipPub`：根应用与四个包格式、静态分析、打包边界检查及 2,603 项测试通过；10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/shortcut-default-check-2026-10-24.log`。本轮未构建或实机验证，未发现可连接的 Flutter 调试实例。
- 真实按下冻结物理身份、目标句柄及媒体代次；修饰键先释放不影响对应 KeyUp。无有效 Down 的 Repeat／Up 不创建动作，合成事件只清理。已消费序列的尾部不落入新标签或下一层弹窗。
- 鼠标按 view／device 的按钮变化识别侧键边沿，支持与普通按钮同时按及 Move 中新增按钮位；双侧键同时新增不任选其一。初始 Move 同步状态，按住跨页面重建只执行一次；失焦／Cancel／移除清理状态。此范围为 Flutter 客户区。
- 输入时仅明确绑定的侧键或 Ctrl／Meta 关闭组合，以及侧键或含 Ctrl／Alt／Meta 的标签切换组合可越过编辑保护；普通 W／F8 绑定仍保留输入。控件的 Enter／Space 激活和未绑定／禁用按键交回 Flutter。
- 总开关控制 22 个可配置动作，包含上一／下一标签；图片查看器操作独立。图片命令通过顶部局部作用域执行，Esc 一次只关闭图片层，保留翻页／缩放重复和局部 Ctrl+滚轮／拖动。
- 录制使用同一入口，整个 Flutter 客户区捕获侧键；Escape 可录制，取消使用按钮。候选按键释放后才退出独占，Ctrl+W／Ctrl+Tab 不执行底层命令。保存失败保留编辑草稿与旧生效配置，成功后统一替换编译表并取消旧长按。
- 保留 preferences.v1 快捷键 JSON 的动作 name、bindings 数组、disabled、enabled 和播放参数；没有新增依赖、偏好版本或 SQLite migration。空列表仍为解除绑定；合法旧设置 round-trip 不变。损坏项局部停用，冲突键从双方移除，设置列出待修复项；用户未确认快捷键设置前仍保留原快照供后续修复。
- 设置提供默认关闭、只在当前进程内存在的诊断，最多 256 条，关闭／离开该设置页清空。记录相对时间、设备／view、phase、逻辑／物理标识或按钮位、归一化匹配方式、命令、作用域、目标注册代次及分发／完成原因；编辑器和普通模态区屏蔽具体键值及按钮位，没有字符／文本／凭据日志或上传。播放器提示从当前设置读取首个有效绑定。

## Apple 默认键位与可配置标签切换（2026-10-27）

原实现所有平台共用 Ctrl 默认键，且将 `Ctrl+Tab`／`Ctrl+Shift+Tab` 编译为固定保留命令；设置页没有编辑入口，也拒绝将这两个键重新分配。现在上一／下一标签属于 `ShortcutAction`，可编辑、录制、解除绑定及单独停用，遵守快捷键总开关。主工作区和独立播放窗共用同一配置，保留按键重复、编辑保护、弹窗隔离和窗口交接规则。

| 操作 | macOS／iOS 外接键盘默认 | Windows／Android／Linux 默认 |
| --- | --- | --- |
| 新建浏览标签 | Command+T | Ctrl+T |
| 关闭标签／播放返回 | Command+W、MouseBack | Ctrl+W、MouseBack |
| 刷新当前页 | Command+R、F5 | Ctrl+R、F5 |
| 切换 1／2 倍速 | Command+1 | Ctrl+1 |
| 下一标签 | Command+Shift+] | Ctrl+Tab |
| 上一标签 | Command+Shift+[ | Ctrl+Shift+Tab |

Apple 标签循环采用 [Safari 的 Command+Shift+方括号约定](https://support.apple.com/en-ie/guide/safari/cpsh003/27.0/mac/27)。配置和提示显示 Command／Option；编辑器接受 `Command`、`Cmd`、`⌘`、`Option`、`Opt`、`⌥` 与方括号，持久化继续使用稳定的 Meta／Alt／BracketLeft／BracketRight 键名。

平台策略集中在 [platform_defaults.dart](../../lib/app/platform_defaults.dart)，由组合根注入设置仓储，领域层保持纯 Dart。新安装、缺失设置、恢复全部默认、恢复默认快捷键以及设置加载前的临时界面使用同一平台策略。有效旧绑定（包括 Ctrl、自定义 Meta、空列表与动作开关）保留；新增默认键若已被旧显式绑定占用，优先保留原绑定。其余实际键位冲突继续局部停用；多键冲突不会因后续过滤重新引入已移除的键。

继续沿用 `preferences.v1` 的 bindings／disabled，不增加 SQLite schema 或 JSON 快照版本。自动回归涵盖两种 Apple 平台默认、旧设置与 SQLite 重启、两类恢复默认、Command 录制、标签循环重绑／停用、输入与模态隔离，以及独立播放窗配置更新。本轮在 Windows 运行 Flutter 的平台模拟回归，macOS／iOS 构建和物理键盘验收仍待目标平台确认。

共同工作区的 `tool/check.ps1 -SkipPub` 完成并通过格式、静态分析、打包边界及 3,786 项测试（根应用 3,127、API 478、player 83、danmaku 93、mux 5），见 `build/apple-shortcuts/check-final.log`；根应用另有 13 项按平台条件跳过，10 项原生 mux 用例因未配置 `BILI_MUX_LIBRARY` 跳过。随后修正新建标签按钮的硬编码 Ctrl 提示，两种 Apple 平台的提示与键盘分发回归通过。本次涉及的 24 个源码／测试文件末次格式与定向静态分析通过；末次整仓 Lint 因同期 `lib/domain/recommendation_settings.dart`、`lib/features/feed/application/feed_item_index.dart` 的格式检查停止，见 `build/apple-shortcuts/lint-review.log`，未修改这些同期文件，不将最后工作区状态记为全量检查通过。未发现可连接的 Flutter 调试实例，未执行热重载或目标平台构建。

最后重跑快捷键设置／录制／SQLite／恢复默认／分发器／平台默认／主工作区／独立播放窗 195 项定向回归全部通过，见 `build/apple-shortcuts/targeted-final.log`。文档本地链接和 `git diff --check` 通过。

## 双标签播放窗侧键交接（2026-10-25）

独立播放窗原先在侧键 Down 时执行返回／关闭，随即激活主窗口，但鼠标尚未释放。固定 Flutter 3.47.6 的 Windows embedder 会根据每个 view 的按钮状态决定 Down／Move：指针进入此前未按下的主窗口且侧键仍按住时，可以产生该窗口的新 Down。两个 AppInputHost 各自按 view／device 识别按钮边沿，因此 view 过滤无法把这两个 Down 识别为同一次物理按压，主窗口可能再退一步。此处依据固定 SDK 源码和事件序列回归定位，尚未采集修复构建中的真实侧键轨迹。

[WorkspacePlaybackWindow](../../lib/app/workspace_playback_window.dart) 的鼠标工作区命令改为只在 Up 执行。Down 仍由既有分发器认领并冻结目标，窗口保持到释放后再交接；Cancel、失焦或模态隔离沿用既有序列取消规则。键盘命令仍在按下时执行，主窗口自己的侧键返回和自定义绑定保持原有规则，没有增加延时防抖、全局 Hook 或原生消息拦截。

[独立窗口侧键回归](../../test/app/playback_window_side_button_test.dart) 使用真实的两个 Flutter view、输入宿主和工作区路由，模拟 Windows 在按住侧键交接窗口时向主窗口交付 Down。主窗口预置为有返回路径的用户页，避免首页边界掩盖重复动作。修复前 MouseBack／自定义 MouseForward 用例均从用户页误退到首页；修复后关闭播放窗保留用户页，下一次独立侧键点击仍正常返回。另覆盖 Cancel、失焦重新聚焦后的旧释放以及 Ctrl+W 按下关闭。

本次 34 项定向回归通过，任务文件静态分析通过。`tool/check.ps1 -SkipPub` 通过打包边界脚本和根目录格式检查，在根应用分析时因同期新增的 `lib/core/platform/image_export_service.dart:1` 存在 `unnecessary_import` 提示而停止，未改动该任务文件。随后分别执行根应用测试及四个包的格式／分析／测试，共 2,844 项通过（根应用 2,222、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2）；10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志保存在忽略的 `build/side-button-fix/`。以上基于包含同期未提交修改的共同工作区，不能将整仓检查记为全通过。

本轮按用户要求不构建、不启动实机验收，Windows 物理侧键与发布构建由用户后续确认；macOS／Android 未在设备上验证。没有可连接的 Flutter 调试实例，未执行热重载。

## 播放画面滚轮音量（2026-10-09）

播放画面内的鼠标纵向滚轮固定调整音量：上滚增加 5 个百分点，下滚减少 5 个百分点，限制在 0–100%，沿用现有音量百分比提示。普通窗口与全屏、视频／影视／直播／离线播放共用 PlaybackShortcutController 和会话的有界音量命令队列；快速连续滚动从待确认目标累加，不改变播放位置、暂停状态或媒体源。

该操作无需配置，不加入设置页面或持久化快捷键目录，也不受可配置快捷键总开关影响。只在活动播放视图中认领鼠标纵向滚轮，阻止同一次事件滚动外层页面；画面外继续正常滚动，横向滚动和触控板事件不调整音量。普通弹窗、输入屏障、应用失活和隐藏页面保留隔离。

[播放器回归](../../test/features/playback/playback_panel_test.dart)覆盖上述四类内容的普通／全屏音量方向、边界和提示、快捷键关闭时的固定行为、外层页面滚动、弹窗／生命周期／隐藏页面以及延迟引擎下的连续累加。自动注入鼠标事件不替代 Windows／macOS 实际鼠标或 Android 外接鼠标验收。

本次 `tool/check.ps1 -SkipPub` 完整通过：根应用与四个包的格式、静态分析及 1,974 项测试通过（根应用 1,539、bili_api 336、bili_player 32、bili_danmaku 65、bili_mux 2）。bili_mux 的 7 项原生合流测试因未配置 `BILI_MUX_LIBRARY` 按既有规则跳过。本次未构建应用或进行实际鼠标／设备验收。

## Windows 修饰键失焦恢复（2026-10-08）

按 [Flutter #177822 报告中的临时方案](https://github.com/flutter/flutter/issues/177822#issuecomment-3477313405)处理 Alt+Tab 后用鼠标切回时的修饰键残留，以及按 Alt 后下一次键盘输入被原生菜单截走的问题。Flutter SDK 仍固定为 3.47.6，没有新增插件、单例或系统键盘 Hook。

- Windows 的 InputNormalizer 从实际交付的修饰键 Down／Repeat／Up 维护 Alt／Ctrl／Shift／Meta，左右键按物理身份分别保存。合成修饰键事件可以同步状态，但仍不执行快捷键；键盘、侧键、录制和诊断共用这份归一化结果。其他平台继续读取 HardwareKeyboard。
- 滚轮补充修复：平滑滚动原先单独读取 HardwareKeyboard，残留 Alt／Ctrl／Meta 会退出平滑处理并落到原生即时滚动；残留 Shift 会错误切换滚动轴。AppInputHost 通过与命令类型无关的只读 InputModifierScope 共享实时状态，平滑滚动的组合键／轴判断及图片查看器的 Ctrl+滚轮都接入该入口。状态仍由 InputNormalizer 单独持有，按输入读取，不增加全局键盘监听或逐键 UI 重建。独立组件没有宿主时保留 Flutter 默认状态读取。
- AppInputHost 在窗口失焦或应用失活时取消动作，清空修饰键、鼠标按钮，以及分发器的键盘／鼠标按下记录。释放发生在另一个窗口时，回到应用后的新 Down 不会被残留的 sequenceTail 吞掉；无 Down 的旧 Repeat／Up 不执行动作。失活时的输入不回填状态，生命周期恢复与 view focus 必须同时有效才接受输入。
- [Windows runner](../../windows/runner/flutter_window.cpp) 消费 `WM_SYSCOMMAND / SC_KEYMENU`，阻止 Alt 激活原生菜单后截走下一键。命令比较按 [Win32 文档](https://learn.microsoft.com/en-us/windows/win32/menurc/wm-syscommand)屏蔽低四位。
- 两处临时补丁均有 TODO，指向 #177822；修饰键补丁同时指向焦点状态同步问题 [#99330](https://github.com/flutter/flutter/issues/99330)。固定 SDK 升级后，先验证 Alt+Tab → 窗口外释放 Alt → 鼠标切回 → 侧键／键盘快捷键，以及按 Alt 后的下一键交付，再移除对应补丁。失焦清理分发器按下记录属于应用自身的生命周期修复，需要保留。

该方案不读取失焦后的 Flutter 修饰键缓存。在其他窗口先按住修饰键再用鼠标切回时，需要重新按下修饰键或收到新的修饰键同步事件才能形成组合键；不能保证在 Flutter 未交付事件时还原物理状态，也不能修复原生 WebView 内的输入。

[输入宿主回归](../../test/core/presentation/app_input_host_test.dart)模拟 HardwareKeyboard 仍残留 Alt／Ctrl 的窗口失焦与生命周期失活，验证侧键及键盘恢复、真正的 Alt 组合、旧按下记录清理、旧 Repeat 隔离，以及 lifecycle resume 不覆盖未聚焦 view。[归一化回归](../../test/core/presentation/keyboard_shortcuts_test.dart)覆盖四种修饰键左右独立释放、失焦重置和合成同步。物理 Windows Alt+Tab／鼠标侧键及输入法仍需实键验收，自动注入结果不能替代这些检查。

首次修饰键补丁的定向静态分析通过；快捷键、工作区、播放和设置相关 336 项回归通过，三个包的格式／分析及 416 项测试通过（bili_api 319、bili_player 32、bili_danmaku 65）。Windows 播放／全屏／工作区集成测试 8 项通过；`flutter build windows --release --no-pub` 通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，既有 flutter_inappwebview_windows CMP0175 警告未阻止构建。本地文档链接与本次差异的空白检查通过。

首次运行 `tool/check.ps1 -SkipPub` 时根格式与发布脚本检查通过，整仓分析停在同期个人主页改动的 `profile_screen.dart:221`／`use_null_aware_elements` 提示。另行尝试根全量测试时，同期 `dynamic_scrollbar_test.dart` 持续触发 Flutter 的 `!semantics.parentDataDirty` 渲染断言，因此停止该次运行；该测试未挂载 AppInputHost。首次修饰键补丁保留这些无关修改，当时没有将整仓检查或根全量测试记为通过。

滚轮补充修复后，`tool/check.ps1 -SkipPub` 完整通过：根应用 1,397、bili_api 325、bili_player 32、bili_danmaku 65 项，共 1,819 项测试；根应用及三个包的格式和分析通过。新增六项滚轮／图片组合键回归包含在根应用检查中。验证日志位于 `build/input-investigation/wheel-modifier-check.log`；真实 Windows 鼠标与焦点切换体验由用户自行构建后验收。

## Windows 输入法与标点快捷键（2026-10-11）

中英文输入法切换后 `;`／`'` 调整倍速失效，存在原生事件交付边界。固定 Flutter 3.47.6 的 [KeyboardKeyEmbedderHandler](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/shell/platform/windows/keyboard_key_embedder_handler.cc#L177) 会把 IME 接管的 `VK_PROCESSKEY` 视为已处理，不向 Dart 发送对应硬件按键；[TextInputPlugin](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/shell/platform/windows/text_input_plugin.cc#L217) 的 hide 是空操作，clearClient 只清理编辑模型／组合状态，没有解除窗口的输入法上下文。仅增加全角标点、扩大物理键回退或清空 Dart 按下记录不能恢复未交付的事件。

AppInputHost 使用已有的编辑焦点判定，通过 app 注入的 WindowService 在进入可编辑输入框时恢复 IME、离开时解除 Flutter view 的 IME 关联；只读文本与播放器／侧栏焦点不启用 IME。搜索、评论、弹幕、弹窗内编辑框及显式 InputProtection 共用该判定，编辑时仍由原分发器保护，不执行播放命令。普通／全屏及各播放内容共用根宿主，不增加页面键盘监听。

Windows runner 的 `bilisail/text_input` 通道调用 [ImmAssociateContext](https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immassociatecontext)，保存并恢复该 view 原来的 HIMC。上下文归窗口所有，适配器不创建／销毁它；重复解除关联不覆盖保存值，宿主移除和原生适配器销毁时恢复。只操作 Flutter view，保留输入语言与中英文转换模式，不递归影响原生 WebView 或其他窗口。其他平台为无操作，没有新增依赖或设置。

回归入口：

- [宿主测试](../../test/core/presentation/app_input_host_test.dart)覆盖编辑／只读／播放焦点反复切换、弹窗中文标点输入和宿主移除恢复。
- [原生测试](../../tool/native_tests/window_ime_context_test.cpp)使用实际隐藏 Win32 窗口和 IMM，覆盖精确恢复、重复操作、原本无 HIMC、其他窗口／语言／转换模式隔离及窗口销毁。
- [Windows 集成测试](../../integration_test/windows_ime_shortcuts_test.dart)在真实 Flutter view 检查 HIMC 关联，并向本测试进程投递原生键消息，验证 `VK_PROCESSKEY` 不到达快捷键层、恢复普通标点消息后命令执行、进入编辑器后保护及离开后重新响应。原生消息注入不等于真实 Microsoft Pinyin／第三方 IME 的实键切换验收。
- 运行 `tool/test-windows-ime.ps1` 完成原生及 Windows 集成验证；`-NativeOnly` 只运行 IMM 测试。

本次 `tool/check.ps1 -SkipPub` 通过根应用及四个包的格式、静态分析与 2,367 项测试（根应用 1,848、bili_api 390、bili_player 41、bili_danmaku 86、bili_mux 2）；7 项既有原生合流测试因未配置 `BILI_MUX_LIBRARY` 跳过。IMM 原生回归与 1 项 Windows 集成测试通过，`flutter build windows --release --no-pub -t lib/main.dart` 通过，普通应用产物为 `build/windows/x64/runner/Release/bilisail.exe`。日志在 `build/ime-test/`。Microsoft Pinyin／第三方 IME 的真实实键切换、原生 WebView 内输入与 Android／macOS 本轮未验收。

### 第三方输入法的上下文恢复（2026-10-17）

用户报告微信输入法在搜索、评论和弹幕输入框中只能输入英文字母。本机注册的微信输入法为 3.0.0.34。源码和隐藏 Win32 窗口回归确认原策略存在三个恢复缺口：首次解除关联时没有 HIMC，后续进入编辑器仍恢复为空；输入法重新关联了上下文后，进入编辑器会被缓存旧值覆盖；原生关联改变但编辑布尔值未改变时，不再校正。上述受控回归证明应用的恢复缺陷，不等于捕获了用户现场的微信输入法失效轨迹。

[WindowImeContext](../../windows/runner/window_ime_context.h) 不再跨解除关联期间保存借用的 HIMC。进入编辑器时保留当前已有关联；关联缺失时调用 Windows 的 [ImmAssociateContextEx / IACE_DEFAULT](https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immassociatecontextex) 恢复当前默认上下文。非编辑状态仍解除本 Flutter view 的关联，重复请求重新核对实际状态；销毁时恢复可用的默认关联。此策略替代上节“恢复保存的精确 HIMC”约定，不创建／销毁系统上下文，不强制输入语言或中英文模式，也不递归操作其他窗口。

AppInputHost 在窗口重新聚焦或应用恢复活动时，于帧后重新发送当前编辑策略，即使原 TextField 仍持有 Flutter 焦点也会同步；窗口与生命周期均有效才执行。原有编辑保护、标点快捷键和模态隔离继续共用根输入宿主。

回归新增默认上下文缺失恢复、新关联保留、同策略下原生关联改变，以及编辑／非编辑状态下的窗口切回与应用恢复。Windows 集成补充原生 `WM_CHAR` 中文字符交付和编辑草稿保留；直接字符消息不代表输入法候选／组合会话已通过验收。微信输入法实际候选选择、Win+Space 切换与长时间失焦恢复仍需人工验收。

`tool/check.ps1 -SkipPub` 通过根应用及四个包的格式、静态分析与 2,537 项测试（根应用 1,944、bili_api 426、bili_player 72、bili_danmaku 93、bili_mux 2）；10 项原生合流测试因未配置 `BILI_MUX_LIBRARY` 跳过。`tool/test-windows-ime.ps1` 的 IMM 原生回归和 1 项 Windows 集成测试通过。整仓检查和 Windows 集成日志分别为 `build/ime-test/check-2026-10-17.log` 与 `build/ime-test/integration-2026-10-17.log`。

`flutter build windows --release --no-pub -t lib/main.dart` 通过，普通应用产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/ime-test/release-2026-10-17.log`。既有 flutter_inappwebview_windows CMP0175 警告未阻止构建。Android／macOS 本轮未构建或实机验证。

### 原生焦点边界与独立编辑上下文（2026-10-22）

安装版 1.0.7.3、微信输入法 3.0.0.37 的故障现场已记录到：Flutter view 存在 HIMC，IMM32 显示打开且为中文模式，但相同 UI 线程的 TSF 打开状态没有值；按键直接产生普通字符，没有组合输入消息。同一微信 profile 在标准 Windows EDIT 和使用相同 Release 引擎 DLL 的普通 Flutter TextField 中可以产生真实候选。加入旧关联策略的简化 Flutter 对照在短流程中也能工作，因此不能把某一次关联 API 调用直接认定为故障的唯一触发条件。

原策略有两个可单独验证的生命周期缺口：原生失焦到 Dart 帧后同步之间仍可能保留关联；延迟送达的编辑通知不检查原生焦点，可能在窗口已切走后重新关联。原策略还只检查 HIMC 非空或恢复线程默认 HIMC，不能处理现场中“存在上下文但没有组合会话”的状态。此次修复覆盖这些边界，不声称已捕获首次从健康状态变为异常的完整轨迹。

[WindowImeContext](../../windows/runner/window_ime_context.cpp) 使用仅针对 Flutter view 的窗口 subclass，在 `WM_KILLFOCUS` 转交 Flutter／系统窗口过程前解除关联；`WM_SETFOCUS` 在系统处理完成后才按当前编辑意图恢复。`setActive(true)` 还检查实际原生焦点，拒绝为后台 view 重新挂接输入法。没有增加全局键盘 Hook，也不递归修改原生 WebView 或其他窗口。

每个新的编辑激活区间通过 `ImmCreateContext` 创建独立 HIMC，关联后才释放已脱离的旧自有上下文；失焦、离开编辑器、窗口销毁和适配器释放均清理自有资源。系统默认／输入法提供的借用上下文不缓存、不销毁；销毁适配器时仅在缺失关联或当前仍是自有上下文的情况下恢复系统默认关联。此规则替代 2026-10-17 的“编辑状态直接复用默认上下文”实现。

打开状态、转换模式和句子模式以值保存。由于两个中文 TSF 输入法可能具有相同 HKL，恢复缓存模式还必须匹配 profile 的 CLSID／GUID；未知或已切换的 profile 使用当前系统输入状态。重复启用仍保留当前编辑上下文，包括输入法在活动编辑期间新提供的上下文，不打断正在进行的候选／组合。输入语言和用户的中英文选择不由应用强制切换。

AppInputHost 同时要求窗口、生命周期有效且存在可编辑焦点，失活时也发送禁用策略；原生同步解除不再依赖该 Dart 帧及时执行。搜索、评论、弹幕和弹窗沿用同一根宿主。原生回归补充独立上下文、原生失焦顺序、后台迟到请求、无编辑器的重新聚焦及释放；Windows 集成测试显式聚焦本测试窗口，不再依赖后台窗口也能启用 IME 的旧行为。

验证结果：宿主 11 项测试、IMM 原生回归和 1 项 Windows 集成通过。`tool/check.ps1 -SkipPub` 通过根应用与四个包的格式、静态分析及 2,575 项测试（根应用 1,981、bili_api 426、bili_player 73、bili_danmaku 93、bili_mux 2）；未配置 `BILI_MUX_LIBRARY` 的 10 项原生封装测试按配置跳过。整仓和 Windows 集成日志分别为 `build/ime-test/check-2026-10-22.log`、`build/ime-test/integration-2026-10-22.log`。

`flutter build windows --release --no-pub -t lib/main.dart` 通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志在 `build/ime-test/release-2026-10-22.log`；既有 flutter_inappwebview_windows CMP0175 警告未阻止构建。正常 Debug 应用也已重新构建、启动并完成热重启，搜索框可显示真实微信输入法候选。Release 原生策略对照完成 `ni` 选词和“你”字上屏，用户随后反馈实际复测无问题并授权提交。

上述结果包含自动按键经过真实微信输入法的候选／组合检查及用户复测反馈，不等于所有输入法、长时间后台、Win+Space 切换和原生 WebView 场景已逐项完成验收。Android／macOS 本轮未构建或实机验证。直接原生消息注入仍只证明消息路径，不能替代真实输入法验收。

### 切换输入法时避免激活旧默认上下文（2026-10-24）

用户反馈选择微信输入法后返回微软输入法，快捷键和任务栏选择均可能失败。本轮核对发现：新编辑区间在创建独立 HIMC 之前，仍会先用 `IACE_DEFAULT` 临时关联线程默认上下文，以读取输入模式。新增原生回归观察 `WM_IME_SETCONTEXT`，在修复前确认恢复输入框时确实激活了默认 HIMC；现有独立编辑上下文并没有消除这个中间激活步骤。它会让旧默认会话参与刚选择的输入法恢复，不应依赖该路径获取新输入法的状态。

[WindowImeContext](../../windows/runner/window_ime_context.cpp) 现在直接创建并关联新编辑上下文。已保存的打开／转换模式只用于相同 HKL、CLSID 和 profile GUID；切换到其他 profile 时只读当前线程已有 TSF manager 的打开／转换模式，不创建或激活 TSF manager，也不临时恢复默认 HIMC。关联后再次核对 profile，防止同步重入期间输入法改变后回写旧模式。当前编辑区间的上下文继续保留，不增加每次按键的重建或输入法监听，不主动选择微信／微软或修改系统默认输入法。销毁适配器时恢复系统默认关联的清理行为保留。

原生回归增加“恢复编辑器期间不激活线程默认上下文”的行为检查。`tool/test-windows-ime.ps1 -NativeOnly -RealImeProfiles` 显式启用本机已安装的微信输入法／微软拼音检查：仅用 `TF_IPPMF_FORPROCESS` 在测试进程内反复切换，核对进入编辑器、重复同步及原生失焦／重新聚焦后的实际 CLSID／profile GUID，退出前恢复测试进程原来的 profile；不修改注册表或用户默认输入法。普通检查不要求安装这两种输入法。

验证结果：修复前新增的“不激活线程默认上下文”断言失败，修复后原生回归及显式启用的真实微信／微软 profile 检查通过；最终日志为 `build/ime-test/native-profiles-final-20261024.log`。`tool/check.ps1 -SkipPub` 通过根应用和四个包的格式、静态分析及 2,635 项测试（根应用 2,025、bili_api 434、bili_player 81、bili_danmaku 93、bili_mux 2）；未配置 `BILI_MUX_LIBRARY` 的 10 项原生封装测试按配置跳过。日志为 `build/ime-test/check-20261024.log`。

Windows 集成首轮在标点命令断言中收到空列表，保留 `build/ime-test/integration-20261024.log`；测试补充原生按键及分发原因的失败诊断后，复跑 1 项通过，见 `build/ime-test/integration-retry-20261024.log`。首轮失败原因未确认，不归因于输入法回退。补充诊断后的格式与 `flutter analyze` 通过。`flutter build windows --release --no-pub -t lib/main.dart` 通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/ime-test/release-20261024.log`；既有 WebView CMP0175 警告未阻止构建。系统安装的 1.1.1+3 未被替换。

尚未捕获同一故障窗口由微信 profile 变回微软 profile 的连续轨迹；修复针对已确认的默认上下文中间激活缺陷。两轮安装版的只读采样均没有收到测试按键，不能作为故障已复现或修复成功的证据。真实候选／提交、长时间后台和原生 WebView 仍待修复构建中的实际验证，不将 profile API 检查当作完整实键验收。Android／macOS 本轮未构建或实机验证。

### 跨应用输入法切换的 TSF 激活期（2026-10-24）

用户补充的完整故障包括：Alt+Tab 返回后在非编辑播放区按 Shift／普通快捷键，回搜索框只能输入英文，Shift 无法恢复中文；切换到其他输入法后无法重新选择微信。进一步缩短为“切到其他应用并选择微软输入法 → 回 BiliSail → 选择微信”也能复现，因此播放快捷键和 Shift 不是必要条件，不能仅按最初的快捷键触发点定位。

完整应用的本地原生诊断记录到：异常时仍有输入上下文、活动 profile 可以仍显示微信，但线程的 TSF 打开状态由有效值变为缺失，按键仅产生普通字符而没有组合消息。分别关闭应用的 IME 上下文干预、移除 `SC_KEYMENU` 拦截、使用系统默认上下文、保留 `ITfThreadMgr` COM 引用以及限制失活时的 `SetFocus`，均未提供稳定恢复；部分短流程正常后继续切换仍失败。因此这些对照不能作为移除 Alt 补丁或改写 HIMC 策略的依据，最终保留原有修饰键、菜单和编辑焦点保护。

[TextServicesScope](../../windows/runner/text_services_scope.h) 在 UI 线程创建 Flutter 引擎和窗口前调用 `ITfThreadMgr::Activate`，在所有窗口／引擎析构后调用配对的 `Deactivate`，最后才释放 COM apartment。依据 [Microsoft 的激活契约](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfthreadmgr-activate)，COM 引用寿命与 TSF 激活计数是两回事；本次修复给应用明确的激活所有者，不再仅依赖 IMM 兼容路径的隐式激活。窗口创建失败的提前返回也经过相同的资源释放顺序。没有主动选择输入法、强制中英文模式或修改系统默认输入设置。

显式保持激活的完整应用诊断版通过用户的跨应用微软／微信切换及中文输入复测，日志同时恢复组合消息。该结果定位到应用需要维持的文本服务激活边界，没有证明 Windows／微信输入法内部首次丢失状态的具体实现原因，也不能用某次短流程正常代替后续反复切换验收。诊断副本与限量、无输入内容的日志保存在忽略的 `build/ime-test/`，正式源码不带诊断钩子。

原生回归增加 TSF 激活的嵌套所有权、精确配对和提前返回释放，并在与应用相同的激活期内验证原有窗口焦点、上下文和真实微信／微软 profile 切换。自动 profile 激活和原生消息注入仍不替代候选、组合和实际中文提交验收。

当前源码执行 `tool/check.ps1 -SkipPub` 通过根应用和四个包的格式、静态分析及 2,639 项测试（根应用 2,029、API 434、player 81、danmaku 93、mux 2）；另有 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。`tool/test-windows-ime.ps1 -RealImeProfiles` 通过原生 TSF／IME 回归和 Windows Flutter 输入法集成测试。

Windows 本地 Release 构建通过，入口为 `build/windows/x64/runner/Release/bilisail.exe`，运行需保留整个 Release 目录。该构建使用升版前的 `1.1.1+5`；提交时同步远端已有的 `1.1.1+6` 并升至 `1.1.1+7`，新版本安装包由远端工作流生成。升版后执行 `tool/check.ps1 -EnforceLockfile` 再次通过格式、静态分析及上述 2,639 项测试，五份锁文件未变，10 项 mux 原生用例仍按配置跳过。诊断版的跨应用切换及真实中文输入已由用户确认；不含诊断钩子的 Release 连续多轮切换、播放页 Shift／空格／倍速仍待人工复测，Android／macOS 本轮未在本机验证。

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


## 2026-10-26 macOS 独立播放窗口首次焦点同步

原生窗口创建可在播放子树仍位于主 view 的 Offstage 内时发出新 view
聚焦事件。旧输入宿主此时记为失焦，GlobalKey 迁移后不会收到第二次事件，
导致包括用户配置 Meta+W 在内的快捷键在第一次打开时被窗口过滤拒绝。

应用启动时（包括 macOS 主窗口创建前）订阅共享原生 view 焦点账本；
宿主所属 view 改变时重新核对账本并清理键盘／鼠标旧序列。
迟到的 A 失焦不清除 B 的新焦点。挂载后仅在原生焦点、view 身份和事件版本
仍匹配且 Flutter primaryFocus 属于其他 view 时修复宿主 FocusScope；
保留同 view 编辑器焦点和窗口过滤，不改默认绑定、原生 performClose 或播放返回历史。

回归覆盖提前聚焦、准备期间切回主窗、迟到失焦、失焦拒绝、切窗恢复、
Meta+W 逐媒体返回及历史耗尽关闭、尾键不误触主窗、重开窗口，
以及保留 State 的跨 view 迁移与旧按键 repeat/up 清理。

本次环境无 Flutter/Dart SDK，临时获取固定 SDK 的二进制下载被代理 403 阻断；
本地只能执行源码检查与 git diff --check，格式／分析／测试和构建以修复分支 CI
结果为准。Widget 回归与 CI 构建不能替代 macOS 实机首次打开、输入法和真实按键验收。


### 后续首次聚焦事件缺失修正

用户反馈首次打开空格仍失效、切窗后恢复；反馈时安装包 SHA 未确认，不能据此
断言某个精确构建的设备结果。重新核对固定 Flutter 3.47.6 源码发现：
`engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterWindowController.mm`
的 `createRegularWindow` 先 `makeKeyAndOrderFront`，后设置发送
`windowDidBecomeKey` 的 delegate。首次事件可能根本未到 Dart；上一版的
事件缓存及主动发送 focus 的测试漏掉了该边界。

主窗／播放窗准备完成及输入宿主跨 view 迁移时，现通过只读原生快照核对当前
`NSApp.keyWindow`、应用 active 状态和同引擎 Flutter view；不使用 mainWindow
冒充键盘窗口，不切换原生窗口。请求代次、Dart 事件版本和原生通知版本隔离
晚到回复；未知失焦状态最多重读三次，不因旧快照恢复已失焦窗口。

macOS 打包 startup smoke 在任何再次 activate 前检查初始原生焦点和 Flutter
primaryFocus，并通过目标 NSWindow 的 responder → engine → AppInputHost 路径
发送固定 Space，验证独占消费；该注入仅在显式 startup smoke 参数下可用，
不使用系统 event tap、不要求辅助功能权限。连续创建／销毁两次仍沿用原销毁顺序。
组件回归另覆盖没有新窗 focus 事件、快照失焦、乱序回复、回复期间切窗及卸载。

默认不打印诊断。设置 `BILISAIL_WINDOW_FOCUS_DIAGNOSTICS=1` 或运行显式打包
smoke 时，记录 keyWindow/view、active、responder 类型／所属关系、焦点来源和
版本、host view/active/primaryFocus 及入口分发原因；不记录按键名称、输入文本、
窗口标题、URL、账号或凭据。原生受控事件测试仍不是用户设备上的物理按键验收。

- 原生烟测前置条件：CI 直接启动二进制会保持后台（924a63c 的脱敏轨迹为 active=0/key=0/view=null）。烟测先激活主窗口并核实原生焦点，再创建播放窗口；不会重新激活播放窗口来绕过首次焦点缺失。生产快照继续拒绝非活动应用。
