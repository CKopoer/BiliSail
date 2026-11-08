# 跨后端起播同步

日期：2026-11-08。修复打开视频时 fvp 偶发先有声音、后有画面的路径；不调整播放器依赖、缓存窗口或解码设置。

## 原因

- fvp 的 MDK 适配器在 `prepare` 阶段已应用用户音量。主视频准备后挂载的外部音频是独立管线，不能依靠主视频的暂停状态替代静音屏障。
- Android／直播首帧需要短暂推进管线。原先兼容输出在结束预滚时只下发异步暂停，随即恢复音量；只有直出输出等待原生暂停完成。音频可能在暂停完成前漏出。
- `NativeTextureVideoOutput.confirmFrame` 原先只安排一个 post-frame 回调，调用方没有等待。回调设为 ready 时，当帧仍绘制黑色准备滤镜，需要下一帧才真正显示视频。
- 自动播放以及暂停打开后的首次播放，原先都在请求原生 play 后以用户音量等待实际音频解码确认。

源码依据为 `packages/bili_player/lib/src/fvp_native_player.dart`、`fvp_engine.dart` 和 `native_texture_video_output.dart`；MDK 的异步状态操作及 `waitFor` 契约另见[官方 Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。

## 修复边界

`packages/bili_player/lib/src/playback_startup.dart` 的 `finishSynchronizedStartup` 由 media_kit 和 fvp 共用：后端保持静音准备，按用户意图推进或暂停，等待各自所需的轨道／输出确认，重新检查源有效性和暂停意图，最后恢复音量。失败、超时或被替换的源不能解除静音；沿用各后端已有总 deadline、取消与释放流程。

fvp 从创建媒体开始保持零音量，全部预滚输出都等待原生暂停屏障；加载期间手动暂停也在解除静音前等待同一屏障，Android worker 将暂停确认传回 UI 进程。首次 play 需要确认实际音频帧时，同样经过共享门槛。加载期间的手动暂停以 pause revision 保留，旧自动播放意图不能覆盖。

fvp 的共享纹理输出提供可等待的呈现确认：已有视图等待移除黑色滤镜后的下一帧；无视图的纯后台调用不依赖 Flutter 绘制；解绑和关闭释放等待，源 revision 阻止迟到回调确认新源。纯音频不创建或等待视频输出；明确无音轨视频不等待不存在的音轨。media_kit 保留自身的解码／原生输出确认，仅将起播音量放行纳入共享流程。

## 回归与验证

- 共享门槛测试覆盖音频先就绪、视频后就绪，以及取消、失败和等待期间手动暂停。
- fvp fake port／widget 测试覆盖原生双轨、Flutter 揭示画面的帧边界、加载取消／超时／暂停；不把请求播放或 decoder 初始化当作可听输出证明。
- 共享纹理输出测试覆盖揭示画面的下一帧、旧源回调隔离及解绑释放。
- `integration_test/windows_playback_startup_test.dart` 为 media_kit 和 fvp 分别添加受控 HTTP 延迟视频／音频的原生用例，验证不会提前完成打开、解除延迟后双轨解码及进度正常。

本机执行结果：

- 按 `tool/check.ps1 -SkipPub` 完成格式、打包边界、根静态分析和根应用 4677 项测试（13 项按既有环境条件跳过）；`-Stage PackageTests` 完整复跑通过：bili_api 714、bili_player 292、bili_danmaku 161、bili_mux 5 项。未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过，不计为原生通过。最终 `flutter analyze --no-pub` 与本任务格式、`git diff --check` 通过。
- Windows Debug 原生起播专项 9 项通过，包含 4 项双后端延迟双轨回归；最终暂停确认改动后复跑通过。
- Windows fvp 中途双轨中断／恢复 4 项、直播／音频／后端切换 3 项、seek 同步 9 项通过。暂停确认接口变更后，seek 的观测适配器同步更新并完整复跑通过。
- Windows 明确无音轨视频 2 项通过；2 项在线用例未启用。上述 Windows 原生验证合计 27 个不同用例通过，使用本地／受控 HTTP 素材、零音量，没有账号写操作。
- 临时独立 fvp Debug 入口加载分轨、暂停首帧及 DTD 热重载通过，未发现运行时错误；探针正常退出，不作为日常应用入口。
- `tool/build-android-development.ps1 -Mode Release` 准备 Android arm64 原生组件并构建普通入口；最终取消边界改动后使用 `-SkipMuxBuild` 复用已构建组件重建通过。包名 `dev.bilisail.bilisail.test`，名称“BiliSail 测试版”，版本 `1.2.8+5`，不可调试，沿用原开发证书。APK 为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 `f3d90da459f216faef15e350d95a246ad5bebee719a70a747958460653d1d9f7`；身份、签名及 AOT 检查由开发构建脚本完成，没有安装操作。

Android 当前没有连接设备；Apple 原生路径不在 Windows 主机可执行范围。受控静音素材验证不代替扬声器／耳机的物理音画同步测量，也不作为启动速度或性能结论。日志保存在忽略目录 `build/validation/playback-startup-*.log`。
