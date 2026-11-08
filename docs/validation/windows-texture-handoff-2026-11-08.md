# Windows 两后端纹理交接与偶发画面分界

日期：2026-11-08。按用户要求只修改源码、运行检查和独立原生测试，不构建应用、不操作设备。用户描述为播放时偶发新旧画面分界、很快恢复，重放同一位置通常不出现。

## 定位与证据

两后端均存在可以产生新旧画面混合的交接缺口：

- media_kit 的 ANGLE 生产者持续改写私有渲染目标；原同设备分支直接交出这个目标，其他设备分支反复复制到同一张交付纹理。
- fvp 的 MDK 生产者与纹理回调使用 CPU mutex，但回调也反复复制到同一张交付纹理。CPU 解锁不代表 GPU 复制完成，更不代表 Flutter 完成了取样。
- 两者复制后都仅调用 `Flush`。[Microsoft 文档](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-flush)明确区分提交与完成；[CopyResource](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-copyresource)本身也是异步操作。
- [Flutter 3.47.6 ExternalTextureD3d](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/shell/platform/windows/external_texture_d3d.cc)在导入／绑定 EGL surface 后立即调用 descriptor 的 `release_callback`，之后才读可见尺寸，并交给引擎绘制。这不是消费者 GPU 完成通知，不能据此重用像素内容。
- media_kit 的 CPU 软件输出也在解锁后交出生产者会继续写入的同一块内存。

新增回归保留前四个已交付的 GPU 资源，在后续 100 帧渲染、尺寸变化及生产者销毁后才读取像素。原固定版本 `f57d7c5ffd564d7a91c45769943831d468caeb2f` 稳定失败，报告 `Texture contains stale or torn pixels`；修复版本通过。这证明了交付后覆盖缺陷，但不代表已在用户设备复现所有肉眼可见的分界，也不排除显示链路的其他原因。

## 修复与来源

个人 [CKopoer/media-kit ba68fe1c](https://github.com/CKopoer/media-kit/commit/ba68fe1c56d46ed5d0e651da8d15e803e45038cb)新增 `D3D11TextureSnapshot`，Windows 两后端共用：

1. 原生渲染目标保持私有；每个新交付版本复制到独立分配的 GPU 纹理，发布后永不写入。
2. 同一生产者 D3D11 immediate context 顺序提交绘制、复制与 `D3D11_QUERY_EVENT`；只有查询确认完成才发布。
3. 回调最多等待 2 ms；未完成时保留上一张完整帧，同时请求后续 Flutter 帧重试。最多保留一个待完成复制，避免积累后台复制队列；首次没有完整帧时返回空描述符。
4. 同一已完成版本直接复用快照；缩放期间沿用旧完整帧及其实际尺寸，直到新分配完成。
5. descriptor 元信息维持至纹理注销，资源租约与元信息分别释放。Flutter 自己导入的 D3D11／EGL 资源继续持有旧图像；应用不把早期 release 回调当作 GPU fence。
6. CPU 软件输出在生产者锁内复制交付字节，由 Flutter 上传后的 release 回调释放，不再暴露可变生产者缓冲。
7. 若不能查询到 ANGLE 的实际 D3D11 device 或启用其多线程保护，沿用既有软件输出回退。不能再另建未知队列的 GPU device：否则有界等待返回后，后续跨设备渲染仍可能覆盖待复制的生产者图像。

应用与 `bili_player` 的全部八个媒体包／overrides、两份锁文件统一固定到上述完整提交。二进制 SDK、ANGLE、mpv 和 MDK 资产及摘要未变。修复在隔离检出目录完成，未修改相邻媒体仓库或 Pub 缓存。

fvp 继续固定官方 `e81637411c58a9ae28de246ee73ad06e3418f10e`；[CMake 适配](../../windows/patches/fvp/apply.cmake)校验整个上游 Windows 源文件的规范化 SHA-256，只在构建目录生成替换副本，以[纹理适配](../../windows/patches/fvp/texture_player.inc)接入同一快照实现。插件注册、MDK SDK、平台账号与播放状态机保持既有入口。BSD-3-Clause、MIT 与 SDK 授权分别保留。

此方案每个被消费的新版本分配一张 GPU 快照并进行一次 GPU 复制；没有引入常规 GPU→CPU 回读。分配和完成查询的性能代价尚未做 Profile／Release 对照，不宣称零复制或性能提升。

## 检查与回归

- [GPU／纹理专项](../../tool/test-windows-gpu-queue.ps1)：真实 D3D11／ANGLE 的 100 帧完整像素、延后消费、跨尺寸和释放后旧图像；真实生产 resize 回调、软件输出副本和稳定 texture ID；fvp 实际替换类配合 fake MDK renderer／registrar，在两个独立 D3D11 device 上验证 20 帧、未渲染首帧过滤、早期租约释放及销毁后延后取样。fvp renderer 为受控替身，不能计作 MDK 解码／音画同步实机验收。
- 同一脚本以 `/W4 /WX` 编译实际 media_kit `video_output.cc` 与生成的 fvp 插件源码；只生成独立测试程序与对象文件，不生成 Flutter 应用。
- 使用两个设备的共享 D3D11 fence 确定性阻塞生产者 GPU 队列，验证待完成复制保持旧完整帧、反复重试仍只有一个 pending copy，以及暂停／缩放后最新版本不会被旧复制吞掉；旧候选 `53683f2d` 在该新增断言失败，最终版本通过。
- [原生释放专项](../../tool/test-windows-video-dispose.ps1)：9 项生命周期、队列、尺寸用例通过。
- [构建副本回归](../../tool/test_texture_handoff.py)：3 项通过，覆盖原文件不改写、上游漂移拒绝和 LF／CRLF 一致性；已纳入根检查脚本。
- `tool/check.ps1 -EnforceLockfile` 全量通过：根应用 4,719、bili_api 719、bili_player 325、bili_danmaku 161、bili_mux 5，共 5,929 项离线测试通过；根应用 13 项按环境条件跳过，mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生通过。全量检查在第一版纹理修复 `53683f2d` 上完成；后续仅调整原生 pending-copy 交接与生产者队列能力回退，Dart 源码未变，最终引用再次通过锁文件强制解析／完整 Lint 阶段及上述最终原生回归。日志位于忽略目录 `build/texture-handoff/`。

## 平台边界与后续实机确认

同日后续已继续修复 Apple／Linux 风险并审查 Android，见[后续记录](apple-linux-texture-handoff-2026-11-08.md)。下表保留 Windows 专项提交时的验证快照，不能作为后续平台修复仍未实施的现状说明。

| 平台／后端 | 本轮结论 |
| --- | --- |
| Windows x64，两后端 | 本次修复的实际路径；独立原生 GPU 回归通过。用户自行构建后仍须确认原片源、窗口／全屏、硬解／软件解码、seek、长播放和 4K／高倍速的视觉与性能表现。 |
| Windows ARM64，两后端 | 共用修复代码，固定依赖会一起生效；未编译 ARM64 测试或运行设备，不声称该架构已验收。 |
| Android，两后端 | 使用系统 Surface／SurfaceTexture 队列及系统 fence；没有 Windows 这段共享 HANDLE 交付路径。本轮未修改、未做设备验证，不能由 Windows 测试推导无撕裂。 |
| Apple，fvp | 静态检查发现同一 CVPixelBuffer 反复使用、Metal blit 提交后直接返回的类似风险；未在本轮改变其实现。Windows 修复不会自动覆盖 Metal／CoreVideo，需在 Apple 主机建立保留旧帧与 GPU 完成回归后处理。 |
| Apple，media_kit | 独立 OpenGL／CoreVideo 三缓冲实现，发布使用 `glFlush`；缓冲数量与 CPU 锁不能单独证明 GPU 已完成。没有本轮设备证据，不声明风险已排除或一并修复。 |
| Linux，两后端 | 独立 GL populate／EGLImage 路径；fvp 在 Flutter 当前 GL 上渲染，media_kit 存在跨 context 的交接。未修改、未构建／运行图形环境，本轮结论不外推。 |

本轮不构建、不安装，不把独立原生测试、Dart 离线测试或历史构建记录算作完整应用播放与跨平台实机验收。
