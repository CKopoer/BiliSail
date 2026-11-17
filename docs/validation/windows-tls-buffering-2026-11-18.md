# Windows 持续缓冲与 PiliPlus 原生读取对照

日期：2026-11-18（Asia/Shanghai）。补充[底层对齐](piliplus-playback-parity-2026-11-17.md)中普通 HTTP 截断未覆盖的不完整 TLS 记录边界。

## 现场与原因

运行的是 `build/windows/x64/runner/Release/bilisail.exe`，PID 34548。00:13:19 打开点播 DASH，3× 播放；00:16:03 起停在 507.72 秒，总时长 1474 秒。原生采样为 `paused-for-cache=yes`、前向字节和缓存时长均为 0、`cacheEof=false`、读取仍活跃。音频时钟 507.864 秒，A/V 差约 2 毫秒，没有硬解丢帧。3 秒后的采样相同，窗口持续显示缓冲。

保留进程，对原生读取线程取栈，并结合相同 DLL 的反汇编与固定 FFmpeg 源码核对：demux 线程位于 `ffurl_read` / `retry_transfer_wrapper` 的 `EAGAIN` 等待循环，经过 HTTPS 和 TLS 两层。从展开后的线程上下文只读检查到这两层 `URLContext.rw_timeout` 均为 0；TCP 连接有 `CLOSE_WAIT`。日志、只含地址／函数的线程栈及故障实验保存在忽略目录 `build/validation/windows-buffering-2026-11-18/`，未保存媒体地址、请求头或账号凭据。

PiliPlus 应用参考提交为 `217fb54f51f6764176319bbdedab2a7522d75401`，核心实际锁定 `73771ec38176be2d984a3049c28177bce23b54a0`。两套应用均沿用 SDK 的 `network-timeout=5`，实际 Windows 原生库不同：本项目是 `mpv v0.41.0-dev-gafd6da884` / FFmpeg `git-2026-10-12-615b071`，当前安装的 PiliPlus 是 `mpv v0.41.0-725-g43b14a4c9` / FFmpeg `N-124868-gd1faab734`。

本项目固定 FFmpeg 的 [SChannel 读取实现](https://github.com/FFmpeg/FFmpeg/blob/615b071/libavformat/tls_schannel.c)在 TCP 已关闭、仍缓存不完整加密记录时，解密返回 `SEC_E_INCOMPLETE_MESSAGE`，随后返回 `EAGAIN`。后续调用跳过已关闭的 TCP 读取，再次尝试同一条不完整记录。外层 [AVIO 重试](https://github.com/FFmpeg/FFmpeg/blob/615b071/libavformat/avio.c)只在 `rw_timeout` 非零时限制等待。因此仅设置 TCP 层的 `network-timeout`，仍可能无限缓冲。

## 修复与对齐边界

在生产原生工厂配置 `stream-lavf-o=rw_timeout=5000000`，把既有的 5 秒网络等待边界补齐到 lavf TLS／HTTPS 读写重试。超时后由 lavf 使用原地址和已接收的字节偏移续读，保留播放器、原生 playlist 条目、DASH 双轨、位置和倍速；播放器复用后配置仍保持。

这是适配当前原生库所需的兼容补齐，PiliPlus Dart 控制器并未原样设置这个参数。应用层缓存、同步、倍速、seek 和明确网络错误后的延迟重开继续采用已对齐的行为；没有恢复半窗口、轮询时钟或自动切 CDN。没有修改相邻仓库、Pub 缓存、固定 SDK 或生产 TLS 证书策略。

此前排查中注意到的 `buffered.value == 0` 判断确实是 PiliPlus 应用当前行为，本次没有以另一套缓存判断替代它；此次永久等待发生在原生读错向上传播之前。

## 验证

- 内存 TLS 服务端加密合成媒体，少发送最后 8 字节后关闭 TCP，分别截断音轨与视频轨；保留完整 HTTP Content-Length，正常支持 Range。真实播放器自主产生缓冲／续读，没有注入 SDK 错误或状态。
- 同一原生库的旧配置在两种截断下均停在缓存耗尽处，`paused-for-cache=yes`、EOF 未到、无续读。生产工厂配置在 5 秒边界后从正确字节重新请求，音视频继续推进、A/V 差低于 0.5 秒，保持 playlist entry 1。四项控制／修复回归通过。
- 相同音轨截断下，实际安装的 PiliPlus 原生库立即报告 TLS EOF 并按字节续读，本项目旧配置一直等待。该对照确认原生差异，不能据此推导两套应用对所有网络故障的发生率。
- Loopback 夹具使用临时自签证书，测试播放器仅对这个隔离服务关闭证书验证；未导入系统证书、修改用户设置或改变生产证书策略。密钥和证书由脚本生成在忽略的 build 目录。

- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界及根应用 5793 项、bili_api 1035 项、bili_player 243 项、bili_danmaku 161 项、bili_mux 15 项测试通过。根应用 13 项 Windows 环境用例跳过；播放器普通检查的 8 项原生 opt-in 用例跳过，本次受影响的 TLS／HTTP／策略复用用例分别另行执行。已配置实际 Windows bili_mux.dll 和 ffprobe，15 项封装用例包含原生执行。
- 原有 HTTP 累计中断控制／修复用例和生产策略复用用例通过；后者覆盖点播／直播／点播复用、倍速往返及 `rw_timeout` 保留。Windows 实际 ANGLE／WASAPI 播放集成 8 项通过，另 1 项环境跳过。
- 隔离普通 Debug 夹具完成双轨播放、热重载及原生释放，无运行时错误；未读取真实账号与数据库，音量为 0。此项不代表长期性能或扬声器听感验收。
- Windows x64 普通入口 Release 构建通过；在独立工作树编译以保留原现场，原生 SDK 下载超时后复用同摘要本机归档，冷 CMake 安装前缀显式设置到 bundle，未改动依赖源码。完整 bundle 的 `data/app.so` SHA-256 为 `74c3f0ac088f57aa7a6e5e7d1c364064c292bde5d545134ec0ac22b71f8916e7`，libmpv 仍为 `8fa6af29a94623d7d1e16bc6db48668f321e3fc9f1eaa86a8df8d61ec57f00e3`。
- 扩展后的 `tool/test-windows-http-audio.ps1` 从生成素材、证书到 6 项实际原生回归完整通过。原现场进程后续已退出，未由本次工具终止；确认没有进程使用目标目录后，将完整修复 bundle 放回 `build/windows/x64/runner/Release/`，旧目录保留为同级 `Release.before-tls-fix-20261118/`。
- Android、Apple、Linux 本轮未构建或实机验证；没有声称线上同一内容已完成长期回归。
