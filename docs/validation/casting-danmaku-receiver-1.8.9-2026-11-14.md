# 云视听 1.8.9 弹幕模式加载失败

日期：2026-11-14；初始基线为 `master` `aa3f4654`，交付前同步并 rebase 到 `origin/master` `00c02674`，保留新增的搜索输入清空按钮改动。

## 现象与证据

用户确认：云视听小电视 **1.8.9**，开启“电视弹幕（实验）”后所有视频均提示“加载失败（错误码：null）”。[上一轮修复](casting-compatibility-regression-2026-11-14.md)只恢复了默认直链播放，没有解决身份投屏模式的加载失败。

本轮从[官方下载中心](https://app.bilibili.com/)链接取得[TV 安装包](https://dl.hdslb.com/mobile/latest/android_tv_yst/iBiliTV-master.apk)，核对到版本名 `1.8.9`、版本号 `108900`。本轮下载文件 SHA-256：`73229ae195f45cdbfd4577b81962a4b4c9345a36abcd846e00dbc0647c127ef2`。下载地址会随版本更新，摘要仅对应本次样本。安装包和分析产物只保存在临时工作目录，没有进入仓库。

静态核对 `DLNAProjectionHandler.NvaExtContent`、`DLNAProjectionHelper`、`ProjectionPlayerActivityV2`、`SimpleUrlDataSource` 和 `MediaResourceResolveTask` 的协议字段及分支，确认以下问题：

1. `autoNext` 的短字段为 `an`，缺失时为 `false`。这个字段同时决定电视是否走内容身份解析路径。此前报文没有发送它，即使包含正确的 aid/cid/剧集信息，电视仍进入直接地址播放路径。
2. 身份 URI `bilibili://projection` 经解析后对应空的媒体地址；直接地址路径的取流器对空地址返回空媒体资源，随后只触发失败，未填充错误信息。这条路径能够解释用户看到的 `null`，不能用 SOAP 成功应答或第三方接收器可解码证明它能播放。
3. `isOpen`／`io` 才是初始弹幕开关，`danmakuSwitchSave` 是切换内容时保存偏好的标志。此前只发送后者，不能设置起播弹幕状态。
4. `mobileVersion`／`mv` 小于 `6240000` 时，电视把 `seekTs`／`sk` 按毫秒换算；此前缺失版本字段，却发送秒，会使点播续播位置缩小一千倍。

AES-CBC、原始 DEFLATE、base64url 和 DIDL `longDescription` 的承载方式与这个版本的接收逻辑一致。该版本存在可用的 SOAP 身份接收分支，因此本轮不需要凭猜测新增 TCP 握手，也没有转发手机账号凭据。核对只用于协议事实与行为，未复制官方实现、安装包或官方抓包到项目源码／测试。

## 修改

- 身份投屏报文补充 `an=true`，让电视进入内容解析路径；该标志也启用电视自身的连播行为，后续内容由接收端管理。
- 开关说明注明由电视接管连播，保留切换后显式重新投屏的提示。
- `io` 使用当前弹幕偏好，同时保留已有 `danmakuSwitchSave` 及独立的弹幕控制命令。
- `mv=6240000` 作为秒单位协议的兼容分界值，与发送的 `sk/seekTs` 一致；这不是 BiliSail 的应用版本，也不声称使用某个官方客户端身份。
- 默认直链模式、主动切换及重新投屏流程、直播 AVC 地址选择沿用上一轮修复。未增加凭据、登录转换、自动回退或播放命令重试。

## 验证与边界

- 现有端到端模拟接收器增加与 1.8.9 分支对应的身份解析要求，覆盖普通视频、影视、直播三类内容；同时在 `Play` 时校验初始弹幕与秒单位位置，避免后续 `SetDanmakuSwitch` 掩盖初始字段错误。修复前三项身份交接失败，三项默认直链通过；修复后六项通过。
- 投屏五文件 **44 项通过**。Python `cryptography`／`zlib` 独立解码三类新报文，校验内容解析开关、初始弹幕、位置单位及无凭据字段，**3/3 通过**。
- 固定 Flutter 3.47.6／Dart 3.13.5 下，**1139 个 Dart 文件格式检查**、全项目静态分析、Linux 适配单独分析、修改文档相对链接和 `git diff --check` 通过。无依赖／锁文件变更。
- `tool/check.ps1 -SkipPub -Stage PackageTests` 通过：bili_api **917**、bili_player **238**、bili_danmaku **161**、bili_mux **5** 项通过。播放器 3 项、mux 10 项原生用例因未配置组件而跳过，不算作原生验证。
- `tool/check.ps1 -SkipPub -Stage RootTests` 通过：根应用 **5334 项通过、6 项条件跳过**，耗时约 12 分 28 秒。开关说明修改后另行重跑投屏 44 项及修改文件静态分析，均通过。
- 上述全量检查基于初始基线；交付前 rebase 未改变修复补丁，合入后投屏与搜索输入框 **57 项通过**，全项目静态分析再次通过。
- `tool/check.ps1 -SkipPub -Stage Lint` 仍在 Linux／PowerShell 的既有 `test-macos-release-validation.ps1:320` 子进程回收断言处失败。没有修改该脚本；其余边界／来源检查已独立补跑通过。环境日志：`/workspace/scratch/cast189-*.log`。

本轮没有连接真实电视或在线账号，没有进行应用构建。这是按官方接收逻辑修正报文并完成受控回归；云视听 1.8.9 的实际音画、弹幕、连播以及账号／会员／地区权限仍需设备复测，不能把静态核对和模拟器通过记为实机验收。
