# Windows 安装界面

2026-10-29：MSI 与 EXE 使用统一的哔帆品牌侧栏、浅色背景、粉色点缀与中文文案。沿用 WiX 6.0.2 原生引擎，用户无需 .NET；MSIX 继续由 Windows 系统显示安装界面。

- [InstallerUI.wxs](InstallerUI.wxs)：MSI 的目录、确认、维护、进度与三种退出页面；[品牌文字](InstallerBrand.wxi) 与[侧栏背景](InstallerBackground.wxi) 为共用片段。原生 MSI 位图不能覆盖输入框／按钮区域；背景只占左侧 152 个对话框单位，保留右侧原生控件与系统配色。新对话框统一使用 `BiliSail` 前缀，避免链接到 WiX 的同名标准对话框。
- [BundleTheme.xml](BundleTheme.xml) 与[中文资源](Bundle.zh-CN.wxl)：Burn 的安装、目录选项、进度、维护、完成、失败、帮助与 passive 页面。保留 WiX 识别的页面／控件名称，以连接原生安装状态、进度、取消确认和日志入口。
- [图稿生成](../../tool/windows-installer-artwork.ps1)：仅使用现有 [app_icon.png](../../assets/branding/app_icon.png) 与几何渐变生成侧栏、MSI 背景和辅助对话框横幅，不绘制文字、不下载资源。系统字体随窗口缩放；图稿为双倍分辨率，生成在安装包旁的 `installer-artwork/`，不提交二进制输出。
- [打包入口](../../tool/windows-installers.ps1) 自动生成图稿，将 UI 源文件与 MS-RL 许可放入应用的 `data/licenses/wix/installer-ui/`，再构建安装包。首次安装目录、64 位注册表恢复、MSI secure 属性、升级身份与签名顺序沿用既有实现。
- MSI 界面以 `zh-CN` 编译，文本代码页为 936；产品 `Language=1033` 保留旧值，使此前的英文安装器也能识别新版本并执行原有升级／降级规则。不要仅为界面翻译改变产品语言身份。
- [实际产物检查](../../tool/test-windows-installer-packages.ps1) 反编译 MSI、提取 Burn，检查导航、中文、目录传递、维护、进度和退出路径；[验证记录](../../docs/validation/windows-installer-ui.md) 区分编译、界面检查与实际安装。

## 上游来源与许可

`InstallerUI.wxs` 的对话事件模式、`BundleTheme.xml` 的页面／控件契约和 `Bundle.zh-CN.wxl` 的运行时字符串契约，改编自 WiX Toolset **6.0.2**，固定提交 `b3f340393117094a75ea8ced77f2357e4aa095e7`：

- [UI 对话框目录](https://github.com/wixtoolset/wix/tree/b3f340393117094a75ea8ced77f2357e4aa095e7/src/ext/UI/wixlib)，涉及 InstallDirDlg、VerifyReadyDlg、MaintenanceTypeDlg、ProgressDlg、ExitDialog、FatalError、UserExit 与 WixUI_InstallDir。
- [HyperlinkLargeTheme.xml](https://github.com/wixtoolset/wix/blob/b3f340393117094a75ea8ced77f2357e4aa095e7/src/ext/Bal/stdbas/Resources/HyperlinkLargeTheme.xml) 与 [HyperlinkTheme.wxl](https://github.com/wixtoolset/wix/blob/b3f340393117094a75ea8ced77f2357e4aa095e7/src/ext/Bal/stdbas/Resources/HyperlinkTheme.wxl)。

Copyright (c) .NET Foundation and contributors. All rights reserved. 上述三个改编文件沿用 [Microsoft Reciprocal License（MS-RL）](../licenses/wix/LICENSE.TXT)，文件头保留来源通知；其他文件不因调用这些界面而改变许可。没有修改 Burn／Bootstrapper 原生实现。二进制条款与工具来源见 [WiX 许可说明](../licenses/wix/README.md)。
