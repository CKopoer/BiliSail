# Windows 安装界面

2026-10-29：MSI 与 EXE 使用统一的哔帆品牌侧栏、浅色背景、粉色点缀与中文文案。沿用 WiX 6.0.2 原生引擎，用户无需 .NET；MSIX 继续由 Windows 系统显示安装界面。

- [InstallerUI.wxs](InstallerUI.wxs)：MSI 的目录、确认、维护、进度与三种退出页面；[品牌文字](InstallerBrand.wxi) 与[侧栏背景](InstallerBackground.wxi) 为共用片段。原生 MSI 位图不能覆盖输入框／按钮区域；背景只占左侧 152 个对话框单位，保留右侧原生控件与系统配色。新对话框统一使用 `BiliSail` 前缀，避免链接到 WiX 的同名标准对话框。
- [BundleTheme.xml](BundleTheme.xml) 与[中文资源](Bundle.zh-CN.wxl)：Burn 的安装、目录选项、进度、维护、完成、失败与帮助页面，passive 模式共用进度页。保留 WiX 识别的页面／控件名称，以连接原生安装状态、进度、取消确认和日志入口。
- [图稿生成](../../tool/windows-installer-artwork.ps1)：仅使用现有 [app_icon.png](../../assets/branding/app_icon.png) 与几何渐变生成侧栏、MSI 背景和辅助对话框横幅，不绘制文字、不下载资源。系统字体随窗口缩放；图稿为双倍分辨率，生成在安装包旁的 `installer-artwork/`，不提交二进制输出。
- [打包入口](../../tool/windows-installers.ps1) 自动生成图稿，将 UI 源文件与 MS-RL 许可放入应用的 `data/licenses/wix/installer-ui/`，再构建安装包。首次安装目录、64 位注册表恢复、MSI secure 属性、升级身份与签名顺序沿用既有实现。
- MSI 界面以 `zh-CN` 编译，文本代码页为 936；产品 `Language=1033` 保留旧值，使此前的英文安装器也能识别新版本并执行原有升级／降级规则。不要仅为界面翻译改变产品语言身份。
- 两种安装器的“浏览”共用 [native/folder_picker.cpp](native/folder_picker.cpp)，通过 Windows `IFileOpenDialog` 的文件夹模式提供地址栏、导航侧栏和新建文件夹。MSI 仅从 UI 调用嵌入的即时 custom action；EXE 通过 WiX BAFunctions 接入自定义按钮，不修改 Burn。取消选择保持原路径；EXE 只修改选项页草稿，仍由“保存位置／返回”决定应用或放弃。
- [原生构建脚本](../../tool/windows-installer-native.ps1) 从 NuGet 获取固定 6.0.2 的两个 WiX API SDK，并校验脚本内固定 SHA-256；仅编译使用其头文件，不链接新增 WiX 库。原生 DLL 使用静态 CRT，安装前无需先装 VC++ 或 .NET。源码与使用的 SDK 头文件随既有 `installer-ui` 许可目录分发。
- Windows 设置中的应用条目沿用 MSI／Burn 原生注册。独立 MSI 可直接卸载；EXE 仅展示 Bundle 条目，隐藏内嵌 MSI 的重复条目，卸载使用缓存的安装器。`DisableModify="yes"` 只隐藏系统列表的修改入口，不禁用卸载；重新打开 EXE 仍可修复。可用[隔离生命周期脚本](../../tool/test-windows-installer-lifecycle.ps1)验证安装、修复、应用条目、缓存卸载、快捷方式清理及非安装器文件保留；默认需要管理员权限，`-Scope perUser` 仅用于单独记录的用户范围测试。
- passive 模式复用同一 Progress 页，避免两个同名进度控件导致 WiX 只更新其中一个；主题检查拒绝重复的控件／页面名称。
- [实际产物检查](../../tool/test-windows-installer-packages.ps1) 反编译 MSI、提取 Burn，检查导航、中文、目录传递、维护、进度和退出路径；[验证记录](../../docs/validation/windows-installer-ui.md) 区分编译、界面检查与实际安装。

## 上游来源与许可

`InstallerUI.wxs` 的对话事件模式、`BundleTheme.xml` 的页面／控件契约和 `Bundle.zh-CN.wxl` 的运行时字符串契约，改编自 WiX Toolset **6.0.2**，固定提交 `b3f340393117094a75ea8ced77f2357e4aa095e7`：

- [UI 对话框目录](https://github.com/wixtoolset/wix/tree/b3f340393117094a75ea8ced77f2357e4aa095e7/src/ext/UI/wixlib)，涉及 InstallDirDlg、VerifyReadyDlg、MaintenanceTypeDlg、ProgressDlg、ExitDialog、FatalError、UserExit 与 WixUI_InstallDir。
- [HyperlinkLargeTheme.xml](https://github.com/wixtoolset/wix/blob/b3f340393117094a75ea8ced77f2357e4aa095e7/src/ext/Bal/stdbas/Resources/HyperlinkLargeTheme.xml) 与 [HyperlinkTheme.wxl](https://github.com/wixtoolset/wix/blob/b3f340393117094a75ea8ced77f2357e4aa095e7/src/ext/Bal/stdbas/Resources/HyperlinkTheme.wxl)。

Copyright (c) .NET Foundation and contributors. All rights reserved. 上述三个改编文件沿用 [Microsoft Reciprocal License（MS-RL）](../licenses/wix/LICENSE.TXT)，文件头保留来源通知；其他文件不因调用这些界面而改变许可。没有修改 Burn／Bootstrapper 原生实现。二进制条款与工具来源见 [WiX 许可说明](../licenses/wix/README.md)。

新增 SDK 为 `WixToolset.BootstrapperApplicationApi`（SHA-256 `899a3d88db31098d87fbb24c2e72fa1d2dbacf9b38af73a91dae762b0653e6f5`）和 `WixToolset.WixStandardBootstrapperApplicationFunctionApi`（SHA-256 `c5d5d3ce835859cd9cfce8428f9111e052e0358334b7cef7000b8099a78e7742`），均来自同一 WiX 6.0.2 提交。接口头文件保持上游 MS-RL 通知，原生辅助代码自行实现。选择器依据 [Microsoft Common Item Dialog](https://learn.microsoft.com/en-us/windows/win32/shell/common-file-dialog)；应用条目依据 [Windows Installer 卸载注册](https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key)。
