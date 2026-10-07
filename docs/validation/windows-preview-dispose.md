# Windows 悬停预览销毁崩溃

日期：2026-10-07。用户的 MSIX `0.4.2.1` 在稍后再看页面悬停视频卡时崩溃。

## 故障证据

Windows 事件 1000（Record 82992）记录北京时间 20:32:21 的 `ucrtbase.dll / 0xc0000409`，异常参数为 7。本机转储的前三个可靠原生帧为 `ucrtbase+0xa527e → libmpv+0xbbdc7 → libmpv+0x975ab`。使用与转储 PE 元数据一致的已安装 DLL 反汇编，确认执行的是渲染上下文未释放时调用 `abort()` 的分支；固定提示为 `mpv_render_context_free() not called`。上游对应 [mpv 652a1dd 的 mp_clients_destroy](https://github.com/mpv-player/mpv/blob/652a1dd/player/client.c#L176-L186)。

最后一条播放日志距事件约 5.44 秒，但没有实例 ID 或 dispose 时间，不能据此绑定到特定卡片。具体操作竞态未复现。直接致命条件已定位，与此前 Windows 无障碍树空指针崩溃不同，也没有证据指向 MSIX 安装损坏。转储和原始证据仅保存在忽略的 `build/crash-diagnostics/msix-20261007-203221/`，不提交或上传进程内存。

## 释放顺序修正

锁定依赖 `media_kit 1.2.6` 会在 `Player.dispose` 后延迟 5 秒销毁 mpv 核心；`media_kit_video 2.0.1` 的 Windows Dispose 原先启动分离线程后立即回复 Dart，而实际 `mpv_render_context_free` 仍在异步排队。应用层等待 `dispose()` 并不保证渲染资源已释放。

本轮在 Windows 插件边界建立完成顺序：

1. 将渲染通知的检查与排队放在同一互斥区，进入销毁时禁止新任务，并解除 mpv 更新回调。
2. 排空已开始/已排队的渲染和尺寸修改任务；待执行的 Render/CheckAndResize 在销毁状态下直接返回。
3. 等待当前纹理和之前 Resize 留下的所有纹理注销回调，保持对象及纹理资源存活。无纹理时不等待不存在的回调。
4. 在原渲染线程上绑定原 GL 上下文，完成 `mpv_render_context_free`，再销毁纹理、ANGLE 和像素缓冲。
5. `VideoOutputManager.Dispose` 在上述清理完成后回调；插件将方法通道回复投递回主线程。Dart 收到回复后，原依赖的核心销毁才可能继续。

没有增加固定延时，也没有在 UI 线程等待纹理/渲染任务。该路径覆盖 Windows 的预览和正常播放器；主应用继续只调用 `PlayerEngine`，Android/macOS 保持既有实现。

## 可复现的构建补丁

补丁位于 [windows/patches/media_kit_video](../../windows/patches/media_kit_video/README.md)，由 [Windows CMake 入口](../../windows/CMakeLists.txt) 在插件目标创建后自动应用。源码复制到构建目录，目标改为编译修正后的副本；不修改共享 Pub 缓存、生成的插件注册文件或依赖锁文件。

五个上游源文件使用 SHA-256 校验；已与官方 Pub `media_kit_video-2.0.1.tar.gz` 对照，归档 SHA-256 与根锁文件相同。升级依赖或内容变化会使配置明确失败，需审查后更新补丁。原始 Windows 插件源码和补丁中的引用按 MIT 使用，保留版权头及 [LICENSE](../../windows/patches/media_kit_video/LICENSE)，构建安装步骤额外复制该许可证到 `data/licenses/media_kit_video/`。

## 本轮检查与未测项

按用户要求仅做针对性检查并提交，未构建或打包应用，未安装 MSIX、启动真实账号或做长时间播放验证，未运行整个 `tool/check.ps1`。

- [原生生命周期单测](../../tool/native_tests/video_output_dispose_test.cpp)：4 项通过，直接编译生产补丁的方法体，控制渲染队列和纹理回调的完成时机，确认 Dispose 不会提前回复；覆盖旧纹理回调、无纹理、软件渲染和已不存在的输出。命令：`pwsh -File tool/test-windows-video-dispose.ps1`，需要 Visual Studio C++ 工具及 `flutter pub get`。
- 三个受影响的原生 `.cc` 使用 MSVC `/Zs` 语法检查通过，没有生成或链接应用。
- CMake 轻量夹具确认全部编译输入切换到修正后的副本、重复配置成功、上游内容变化时拒绝应用。
- `flutter test test/features/video/video_card_preview_playback_test.dart --reporter compact`：12 项通过。
- 提交前检查差异空白和新增文档的相对链接。

仍需用户构建后验证：快速跨卡悬停、预览未就绪就移开、滚动回收卡片、打开超时/备用地址、页面切换，以及正常播放和多标签关闭。需覆盖停止预览后的 5 秒以上窗口，检查崩溃、释放停滞和资源增长；单测及语法检查不能代替真实 Flutter 纹理注销、显卡驱动与 MSIX 验收。
