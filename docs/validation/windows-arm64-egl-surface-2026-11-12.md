# Windows ARM64 黑屏：修正 EGL 生产者表面生命周期

日期：2026-11-12。基线 master `ef2d5cdd`，关联 [issue #100](https://github.com/CKopoer/BiliSail/issues/100)。

## 证据与原因

用户补充确认 media_kit 有声音，硬件解码时任务管理器有 Video Decode 占用，改为软件解码仍黑屏，多种编码均受影响。两种解码模式共用 ANGLE 视频输出，因此继续检查绘制／交付链路；这些反馈不能单独确定哪条 GPU 调用失败。

固定媒体依赖 `9858a8db83faf8bcfa39a8bfbc02dde9a2e92572` 的 `ANGLESurfaceManager::CreateAndBindEGLSurface()` 在创建 D3D11 pbuffer 后调用了 `glGenTextures`、`glBindTexture` 和 `eglBindTexImage`，把生产者表面绑定成采样纹理。后续 `Draw()` 却将同一表面作为默认 framebuffer 写入，绘制前没有 `eglReleaseTexImage`。

这违反 [Khronos eglBindTexImage 契约](https://registry.khronos.org/EGL/sdk/docs/man/html/eglBindTexImage.xhtml)：表面绑定后不可读写，释放绑定前绘制结果未定义。首次创建时没有 current context，绑定可能被忽略；`VideoOutput::Initialize()` 创建 mpv context 后保持 current，首次视频尺寸到达时 `CleanUp(false)` 又保留无表面的 current context，导致重建路径实际执行采样绑定。旧代码还会改变同一渲染线程上其他 current context 的纹理状态，且每次创建的 GL 纹理没有对应删除。

[Microsoft 的 ANGLE 互操作说明](https://github.com/microsoft/angle/wiki/interop-with-other-directx-code)分别描述了采样 pbuffer 和向默认 framebuffer 绘制的两种用途。本插件生产者使用后者，Flutter 独立负责导入完成的 D3D11 快照并绑定采样，不需要生产者再绑定一次。

这里定位并复现的是生产源码中的 EGL 契约缺陷。当前没有 Surface Pro X 的原生图形日志或设备，不能证明它是用户设备黑屏的唯一原因，也不将 fake EGL 回归当作 ARM64 驱动上的像素验证。

## 修复与来源

- 个人 [media-kit 修复提交 b4328505](https://github.com/CKopoer/media-kit/commit/b4328505605e03d3c73fda90306f3ce556709aef)移除生产者的 GL 纹理创建与 `eglBindTexImage`，保留默认 framebuffer 绘制和已有 GPU 完成查询／不可变快照交付。
- resize／销毁先用 `EGL_NO_CONTEXT` 解除 current，再销毁旧 surface。resize 保留 mpv 所属 EGL context，不再要求 `EGL_KHR_surfaceless_context`；空 display 不调用 EGL 清理函数，也不终止 Flutter 共用的 display。
- 更新生产源码 SHA-256 清单。根应用与 `bili_player` 的八个媒体包／overrides 及两份锁文件统一固定到 `eaae0273a93fbd23b24e3c951b99efd9b73e702b`（包含上述修复与 Clang 回归兼容性）。应用不变换依赖源码，不修改 Pub 缓存。
- 自动／软件解码、ARM64／x64 的 GPU 输出默认值、D3D11 快照及二进制 SDK 均沿用原配置。没有采用按 ARM64 架构统一禁用 GPU 的降级。
- [应用媒体回归](../../tool/test_windows_media_assets.py)增加入口，调用 fork 的 `native/test_windows_egl_surface.py`；其独立 C++ 测试直接编译生产的表面创建／清理／MakeCurrent 方法，模拟 EGL 对采样绑定后写入的限制。

## 验证与设备边界

旧生产方法在新增回归中失败：`draw surface is bound for sampling: video writes are undefined`。修复后覆盖首次 1×1→视频尺寸、连续四种尺寸、其他 current context 的隔离、上下文复用及空／正常释放。原渲染初始化与九项释放／渲染队列／尺寸回归也通过。

Flutter 3.47.6／Dart 3.13.5 下的结果：

- 五份锁文件严格解析通过。最终媒体提交仅补齐回归 fixture 的 Clang 未使用常量标注，全部生产源码／SDK 与首版修复相同；最终引用再次严格解析，11 项 Windows 媒体资产／源码摘要／初始化／EGL 回归全部通过，EGL 专项同时通过 GCC 和 Clang。
- 1,153 个 Dart 文件格式检查无改动；根静态分析及本地 Linux 插件静态分析通过。完整脚本在 macOS 检查之后的其余打包／资产／纹理检查分别执行并通过。
- 根应用 5,183、bili_api 886、bili_player 398、bili_danmaku 161、bili_mux 5，合计 6,633 项 Dart／Flutter 测试通过。根应用 6 项按原环境条件跳过；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。
- `tool/check.ps1 -EnforceLockfile` 在未修改的 `tool/test-macos-release-validation.ps1:320` 中断，报告 `The independent parent failed to terminate a stalled worker and its child`，与此前 Linux 验证记录一致。随后完成上述独立检查和全部应用／包测试；不宣称完整检查脚本通过。

日志保存在忽略目录 `build/issue-100-egl/`。当前执行主机为 Linux；Windows ARM64 应用构建、真实 ANGLE／D3D11 像素回归及 Surface Pro X 的悬停、点播、软件／硬件解码、seek、暂停缩放、全屏／小窗仍需在相应平台验收。x64 共用表面实现，也需确认原生播放；不能把受控 EGL 测试解释成实机黑屏已消失。

## CI 锁文件序列化修复

[CI 43071478079](https://github.com/CKopoer/BiliSail/actions/runs/43071478079) 对应应用提交 `410b700f`。静态检查、根测试四个分片、包测试及 mux 原生回归均成功。七个平台完成编译和打包，其中 Windows x64／ARM64 安装包验证也成功；所有构建任务最后都在 `tool/build-release.ps1:404` 报告 `Build changed pubspec.lock; do not publish this package.`。

原因是此前替换 Git ref 时保留了旧锁文件的引号。新提交号以 `e` 开头，固定 Pub 的标准序列化会将其写成无引号字符串。`pub get --enforce-lockfile` 接受带引号的等价 YAML，且不改写文件；Flutter 构建为更新插件注册再次运行普通 Pub 时，会移除引号，触发发布脚本的文件 SHA-256 校验。这是锁文件表示形式的变化，依赖版本、Git 提交和校验摘要没有变化。

本次使用 Flutter 3.47.6／Dart 3.13.5 的普通 `pub get` 重新生成根应用与播放器包的锁文件，未手动移除引号。`tool/check.ps1 -Stage Lint -EnforceLockfile` 增加严格解析后再执行普通解析的检查，并要求锁文件字节不变，覆盖根应用和四个包，提前发现构建会引发的序列化漂移。严格解析失败仍立即失败；发布前哈希校验及构建时插件注册重生成均保留。

新增六项受控回归，覆盖两种 Pub runner、序列化改写拒绝、严格解析失败传播及非 lint／非严格模式。另用真实 SDK 对原带引号锁文件复现拒绝，再检查五份锁文件的严格／普通解析往返保持原字节。验证日志保存在 `build/issue-100-ci/`。

前述 Windows ARM64 构建未测边界是本地执行时的快照；此次 CI 日志已补充编译和打包成功的证据，仍不能替代 Surface Pro X 的实际音画验收。
