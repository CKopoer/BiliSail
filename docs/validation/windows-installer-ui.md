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
