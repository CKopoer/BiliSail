# canvas_danmaku 与 Predidit media-kit 切换方案

日期：2026-10-29。用户要求将弹幕绘制与播放器依赖切换到 Predidit 的实现。本文同时记录实施范围和实际验证；构建、设备验收、性能结果分别列出。

## 固定来源

| 组件 | 源码提交 | 采用范围 |
| --- | --- | --- |
| [canvas_danmaku](https://github.com/Predidit/canvas_danmaku/tree/401915a11ae113cddb5409632cd99729f4b0a301) | `401915a11ae113cddb5409632cd99729f4b0a301`，包版本 0.3.3 | MIT；上游 Canvas 绘制管线，封装在 `bili_danmaku` 内 |
| [media-kit](https://github.com/Predidit/media-kit/tree/83b7ca63772856e1ea0158916177e136f7b7b0be) | `83b7ca63772856e1ea0158916177e136f7b7b0be` | MIT；核心及视频插件使用同一提交，Native Assets 负责原生库 |

只读检查目标源码，不修改相邻参考仓库，不修改 Pub 缓存。Git ref 使用完整提交；根应用保留核心 override，使直接、传递依赖解析到同一来源。四个独立包继续存在，协议、账号、播放队列不下沉。

目标视频插件固定 `wakelock_plus 1.3.3`，其 `package_info_plus <9` 约束与本应用 10.2.2 冲突。已核对插件只调用 `WakelockPlus.enable/disable`，根应用和播放器包显式 override 为原已锁定的 `wakelock_plus 1.8.1`，不降低应用版本信息依赖。目标分支额外解析 `wakelock_plus_ohos`，本轮不增加 OHOS 应用目标。

Android 的目标实现已替换旧 fork 的 `surface_lifecycle.dart`。应用继续传递 `androidAttachSurfaceAfterVideoParameters: false`，但本次固定的目标 Android 控制器没有读取该兼容字段；原播放器配置单测只验证传参，不证明旧 `on_load` 绑定顺序仍生效。首开、后台恢复、旋转／全屏和 Surface 重建须按目标分支的新策略重新做设备验收。

## 实施顺序

1. 固定上述提交，更新根应用、`bili_player`、`bili_danmaku` 的清单与相应锁文件。新 media-kit 已删除 `libs/`，移除全部 `media_kit_libs_*` 依赖及 override，不能把旧的七处路径机械改为新 URL。
2. Windows 采用上游 D3D11/mailbox 输出及匹配的 DXGI libmpv。移除旧 ANGLE／LGPL DLL 注入；审查并保留“纹理注销、队列排空、渲染上下文释放后才回复 Dispose”的屏障。尺寸调整继续经包内适配，保留 generation、owner、延迟缩小和立即放大。
3. `bili_danmaku` 保留无网络的点播／直播控制器、确认媒体时钟／单调到达时钟和容量限制，接入上游公开 painter。上游 `DanmakuScreen` 自带独立时钟，直接整件替换会丢失有界插值、暂停 seek 重建、混合字体、阴影和缓存预算，因此使用其可扩展绘制管线，布局及兼容设置仍由包内适配负责。每个 overlay 继续只有一个 Ticker，不引入第二套播放器或全局逐帧状态。
4. 按 Native Assets 更新各平台打包：避免 Linux 打包时再次加入系统 mpv；Apple 最低部署版本核对固定 Flutter 的 framework 生成要求；保留 CocoaPods 路径，关闭 SwiftPM 的选择不在本轮混改。
5. 执行根检查、弹幕像素／生命周期回归、播放器包测试，以及 Windows 本地分轨、直播夹具、关闭和窗口回归；构建 Windows Release。Android／macOS／iOS／Linux 没有在对应主机或设备验证前保留待验状态。

## 必须保留的行为

- 点播按确认位置触发，滚动时间独立于倍速；暂停／缓冲冻结，seek 确认后重建，超过有界插值窗口停止外推。
- 直播按到达时钟调度，不跟随视频 seek；关闭／换房清理，普通／全屏继续使用同一控制器。
- 滚动／顶部／底部、颜色、大小、字体、粗细、阴影／描边／纯色、透明度、区域、间距、偏移、去重和数量上限保留。过大文本及高 DPR 仍有内存预算与直接绘制降级。
- 一个播放会话只有一个原生播放器，DASH 音视频分轨、headers、Range、备用恢复、播放意图与账号隔离沿用原契约。
- 原生资产来源以固定 fork 的 `media_kit/hook/native_bundles.json` 的 URL 与 SHA-256 为准。新资产不能继续沿用旧 Windows `gpl=false` 结论；源码许可和二进制的子依赖许可分别记录于 [第三方说明](../THIRD_PARTY_NOTICES.md)。

## 回退与验证边界

回退时整体恢复本次清单、锁文件和平台适配，不混用两种原生协议或 DLL。设置与数据库没有迁移，不删除用户数据。旧 ANGLE 性能记录只描述旧实现，不能直接推导新 D3D11 的性能。

## 当前实现边界

`CanvasDanmakuRenderer` 继承上游公开 `BaseDanmakuPainter`，实际绘制经上游的批量 Picture 与图像采样路径执行。位置、轨道和有界文字／像素缓存继续由本包持有，文字 shaping 与阴影／描边适配没有改用上游全局字体选项。批次借用缓存图像，不取得释放所有权；发生淘汰或直接文字降级前先提交批次，保持混合覆盖顺序。每帧复用有界 item 对象，不另建上游动画时钟。

本轮没有把上游 `DanmakuScreen` 的轨道分配、独立计时或高级弹幕加入产品，因此不能将其所有功能或宣传的性能直接视为项目已有能力。如果后续需要整件替换轨道／缓存实现，须先为上游补齐媒体时钟、预算、混合字号和现有字体效果的适配契约。

## 本机验证（2026-10-29）

- 五份锁文件逐项 `pub get --offline --enforce-lockfile` 通过；三份相关锁文件由 Pub 重生成，另外两份保持原内容。
- `tool/check.ps1 -SkipPub` 通过：根应用 3359、API 492、播放器 96、弹幕 118、mux 5，共 4070 项通过。根应用 13 项按原条件跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生封装覆盖。最终夹具调整后另跑 `-Stage Lint -SkipPub` 通过。
- 弹幕新增 18 条混合内容触发上游批量路径，在阴影／描边／纯色和 DPR 1／1.25／2 下与逐条结果逐像素一致；原暂停、倍速、seek、全屏尺寸、预算与小容量淘汰用例继续通过。
- Windows 原生 Flutter 回归共 27 项通过：主播放 8、诊断 1、打开／取消／超时 5、视频就绪 5、截断视频 2、预览缓冲 1、音量均衡 2、UGC／PGC／直播内容夹具 2、五分钟缓冲 1。使用本地文件／HTTP／HLS／FLV，无 `-Online`，不代表真实账号或 CDN 验收。
- `tool/test-windows-video-dispose.ps1` 的 9 项受控原生回归通过；`tool/test-windows-gpu-queue.ps1` 对实际 D3D11 共享纹理完成 8 轮创建、绘制、像素读回、缩放及销毁。补丁校验另确认 LF／CRLF 等价源码可用，实质源码变更被拒绝；仍只修改构建副本。
- 原生界面夹具修正了命中控件的旧 `(30, 50)` 点击坐标，并忽略已销毁测试 view 的残留原生指针包，之后主播放 8 项完整通过。播放产品交互没有因测试修改。
- Windows x64 Release 已构建成功；增量安装会清理旧 ANGLE DLL、旧库插件及旧资产来源说明，打包当前 Native Assets 来源与第三方说明。正常入口固定为 `lib/main.dart`。
- 另启动独立本地分轨＋弹幕调试夹具，确认日志实际使用 Flutter 同一 DXGI adapter 的 D3D11 输出，音视频均已解码；查看了合成测试图画面，热重载成功，Dart 工具报告无运行时错误。该画面检查不代替人工音画同步或性能测量，结束后已关闭夹具。
- Android arm64 开发 Release 已通过标准脚本构建，实际包名 `dev.bilisail.bilisail.test`、名称 `BiliSail 测试版`、版本 1.2.4+0，脚本已校验签名及不可调试；未安装到设备。APK 含 `libmpv.so`、匹配 JNI helper、Native Assets 事件桥和独立 mux。SHA-256：`386af2780884a70d6396d46b88610f7aaa1fd2f0348e6f5402bdfafe0cb450df`。
- Linux 打包边界原有 12 项 Python 回归通过；修改文档的相对路径和 `git diff --check` 通过。

本地日志位于 `build/predidit-*.log`。Android 与 Windows 同时构建曾导致 Flutter 插件注册文件交叉更新；已改为串行并通过标准入口重新构建 Android Release，没有手改生成文件。

macOS 部署下限提高至 13.0 的依据已核对固定 Flutter SDK `packages/flutter_tools/lib/src/isolated/native_assets/macos/native_assets.dart` 中的 `targetMacOSVersion = 13`。macOS／iOS／Linux 的本平台构建、Android 实机音画与 Surface、真实账号／长时间播放、跨 GPU 和性能对照尚未执行。新原生二进制完整分发材料仍需按来源归档；本轮未创建正式发布。

## CI 构建兼容修复（2026-10-29）

[CI #216](https://github.com/CKopoer/BiliSail/actions/runs/40738122479) 的检查和 Android 构建通过，三个 Apple 目标在 Swift 编译时缺少 mpv 声明，Linux 在打包时缺少 `libva-wayland.so.2`，Windows 仅输出 Native Assets 汇总错误。

- 两份 Podfile 在 Flutter 创建插件链接后调用 [构建副本准备脚本](../tool/prepare-media-kit-apple.py)。校验固定 podspec 的 SHA-256，将插件复制到 `build/apple-plugins/<platform>/`，把共享 C 绑定放进 Pod 根目录并重定向生成的插件链接。保留上游源码、许可和符号链接；不修改 Pub 缓存或依赖提交。升级依赖时必须重新审查校验值和目录布局。
- Linux 显式安装 `libva-wayland2`，打包前输出固定 libmpv 的完整 `ldd` 结果。继续使用 Native Assets 的库，禁止用系统 mpv 替换。
- Windows 打包脚本启用 Flutter verbose 输出；原生编译期间移除 MSIX 签名凭据，随后恢复供签名使用。失败时收集经过环境敏感值和 URL query 过滤的 hook 输入、输出与日志，上传独立诊断产物。

Windows 本地 `tool/check.ps1 -SkipPub` 通过格式、分析和 4070 项测试，根应用 13 项既有跳过，mux 10 项因未配置 `BILI_MUX_LIBRARY` 跳过；两项 Apple staging 回归、18 项 Linux 纯 Python 回归、PowerShell／Bash 语法和诊断脱敏检查通过。7 项 POSIX shell 运行时检查未在此 Windows 环境执行成功，交由 Ubuntu CI 验证。远端构建结果将在修复推送后的 CI 核验；以上不代表设备安装、音画或性能验收通过。
