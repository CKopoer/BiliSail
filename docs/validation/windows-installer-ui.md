# Windows EXE／MSI 安装界面改版

日期：2026-10-29；主机：Windows x64；WiX：6.0.2。

## 界面与流程

两种安装包统一使用现有粉色小电视图标、浅蓝船帆侧栏、大标题、中文操作文案与较大的按钮间距。[界面源码与来源](../../windows/packaging/README.md) 集中在 `windows/packaging`；图稿由[构建脚本](../../tool/windows-installer-artwork.ps1) 从现有图标和几何图形生成，不下载字体、图片或引入客户端依赖。

- MSI 将欢迎与安装目录合并为首页，支持直接输入和浏览文件夹，再进入显示实际目录的确认页。确认、进度、维护、成功、失败与取消页面采用同一布局。保留原生目录验证、空间不足提示、文件占用、管理员权限和修复／卸载事件；位图只占侧栏，避免遮挡右侧原生控件。
- EXE 的首页展示实际安装目录；“更改位置”进入可编辑／浏览的目录页，“保存位置”应用并返回，“返回”放弃编辑。保留进度、修复、卸载、重启提示、错误日志入口、命令行帮助及 passive／quiet 模式。
- 继续使用既有 MSI／Burn UpgradeCode、目录注册表、组件身份、secure 目录属性与签名顺序。MSI 界面编译文化为 `zh-CN`、代码页 936，产品语言保留旧值 1033，避免翻译界面破坏与旧英文安装包的双向版本识别。MSIX 仍由系统提供安装界面。
- 改编自固定 WiX 提交的三个 UI 文件保留文件级 MS-RL；打包时连同共用片段、来源说明与许可证放入应用的 `data/licenses/wix/installer-ui/`。原生引擎未改动。

## 本地验证

使用已有、文件版本为 `1.2.3+1` 的完整 Windows Release 目录，另行暂存 VC++ runtime、第三方说明及许可，通过生产 `New-WindowsMsi`／`New-WindowsBundle` 构建两种安装包；没有重新编译 Flutter 客户端，没有使用正式签名私钥。这些文件位于 `build/installer-ui-validation/`，仅作为本轮打包／界面验证产物。

[实际产物检查](../../tool/test-windows-installer-packages.ps1) 反编译 MSI 并提取 Burn manifest、主题与本地化资源，覆盖 56 项检查：目录输入／浏览／双向导航、实际路径确认、旧目录恢复／显式选择优先级、MSI secure 属性、EXE → MSI 目录传递、产品语言身份、中文标题、进度事件、维护／退出入口、所有主对话框的位图与交互控件无交叠，以及改编源码／许可随包分发。

真实窗口检查确认 EXE 首页以及 MSI 首页／确认页可显示中文、品牌侧栏和完整按钮。MSI 输入 `C:\Apps\哔帆 安装验证\BiliSail\` 后进入确认页，目录正确；返回后仍保留。没有点击实际安装、修复或卸载。EXE 执行 `/layout <工作区临时目录> /passive /norestart` 成功退出，日志记录中文界面语言 2052、退出码 0，生成的本地 EXE 副本与输入产物一致；该操作没有安装应用。

`tool/check.ps1 -SkipPub -Stage Lint` 通过打包边界、格式和静态分析；四包测试共 709 项通过（API 492、播放器 96、弹幕 116、封装 5），10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不计作原生集成覆盖。

首次完整 `tool/check.ps1 -SkipPub` 的格式／静态分析通过，根测试 3349 项通过、3 项失败、13 项 Windows symlink 因权限跳过；失败发生在同期导航／侧栏修改的工作区：`shell_layout_test.dart:1009` 的 Android／Windows 消息布局期望高度 43、实际 44，`workspace_shell_test.dart:978` 期望位置 63、实际 65。保留这些源码和测试修改，没有为安装器调整它们。同期导航修正进入工作区后，最终 `tool/check.ps1 -SkipPub -Stage RootTests` 复测 3352 项通过，13 项 symlink 用例仍按环境跳过。最终三个检查阶段合计 4061 项离线测试通过；本任务只提交安装器、文档与产物检查修改。

## 尚未验收

本轮没有执行真实全新安装、旧版本覆盖升级、实际修复／卸载、签名／SmartScreen 信任、Windows 10、其他系统语言或多显示器 DPI 切换验收。产物结构检查、窗口预览和本地副本模式不替代这些项目；没有发布 Release 或替换已发布附件。

## 2026-10-29：文件夹选择器与系统卸载入口复查

MSI 的 WiX `BrowseDlg` 与 EXE 的旧 `BrowseDirectoryAction` 均替换为共享的原生 `IFileOpenDialog` 文件夹模式。新窗口提供系统地址栏、导航侧栏、文件夹列表、新建文件夹及中文确认按钮；取消保留原路径，EXE 仍只编辑选项页草稿。通过固定版本／SHA-256 验证的 WiX API 头文件接入 BAFunctions，MSI 仅从 UI 调用即时 custom action；辅助 DLL 使用静态 CRT，源码和 SDK 头文件随包分发。EXE 实际窗口确认新选择器已打开；MSI 导出入口、绑定和条件更新由编译及产物检查覆盖，后续界面操作按用户 Escape 停止。

卸载注册沿用 Windows Installer／Burn；EXE 的系统条目只提供卸载，重新运行安装包仍提供修复。新增 [生命周期回归](../../tool/test-windows-installer-lifecycle.ps1)，使用生产 authoring 的副本、随机 UpgradeCode／ProductCode、独立注册表／开始菜单目录和不执行的合成文件，避免触碰正式应用或账号数据。测试卸载只针对本轮随机身份；失败也会清理注册。

本机以 `-Scope perUser -PauseForSettings` 执行，结果保存在 `build/installer-picker-validation/lifecycle-5bb80f74d4074bffb3d99a0ab87dea2a/result.json`：

- 独立 MSI 安装后，真实 Windows“设置 → 应用 → 安装的应用”中出现带品牌图标的隔离条目，菜单的“卸载”可用；直接卸载命令为 `MsiExec.exe /X{测试产品码}`。删除一个测试文件后，修复成功恢复。
- EXE 安装后生成一个可移除的 Bundle 卸载注册，内嵌 MSI 标为 `SystemComponent=1`，不产生重复可见注册。删除测试文件后，缓存的 EXE 修复成功；移动原始安装包后，仍可用应用条目指向的缓存程序执行卸载。
- 两次卸载均返回 0，产品／Bundle 注册、快捷方式、安装目录注册值和所属程序文件移除；额外写入的非安装器文件仍保留。未读取或改动真实账号、数据库、下载或应用设置。
- EXE 的用户范围注册未在本机系统设置列表中显示，不能将注册表可见性检查当成该界面的通过记录。生产安装包仍为 `perMachine`，本轮没有执行需管理员权限的生产范围生命周期；只确认其编译产物包含可卸载的 ARP 注册。独立 MSI 的真实系统列表检查与上述用户范围回归分别记录。

最终原生辅助库通过 MSVC `/W4 /WX` Release 编译，两种完整载荷安装包编译并通过 67 项产物检查。PowerShell 语法、71 条相对文档链接及本任务差异检查通过。完整根检查的打包边界、格式与静态分析通过；根测试 3348 项通过、4 项失败、13 项 symlink 因权限跳过，失败为同期正在修改的 `playback_panel_test.dart` 的四项 `picture seek holds its target until confirmed`，预期 seek 54000 ms／进度 0.3，实际为 31000 ms／0.172222。未为本任务修改这些播放文件；四个包另行通过 709 项测试（492／96／116／5）。10 项 mux 原生用例仍因未配置库而跳过。本节不替代生产管理员安装、Windows 10 或多 DPI 验收。
