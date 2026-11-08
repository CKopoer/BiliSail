# 音视频恢复时保留画面与进度

日期：2026-11-08（Asia/Shanghai）。用户要求音频加载失败时停在当前位置，避免黑屏和进度条回到开头；所有现行播放后端采用相同行为。本轮按要求仅执行离线测试和检查，不构建应用、不操作设备。

## 原因与实现

[PlaybackSession](../../lib/features/playback/application/playback_session.dart) 原先在重新解析或首次音频准备失败后先 `stop()`，会发布零位置、零时长；随后 [SharedPlayerEngine](../../packages/bili_player/lib/src/shared_player_engine.dart) 解绑并释放原生输出，新输出准备期间显示黑色。健康检测还可能把显示进度回退到落后的单轨边界。这些共享路径同时影响 media_kit 与 fvp。

- 同一内容的自动恢复、备用 CDN 和首次音频重准备使用 `OpenOptions.retainPresentation`。会话先暂停，保留位置、时长、倍速和音量；新管线准备时的零时长样本不清空已有时长。故障保持最后确认的显示进度，单轨边界继续保留在诊断事件中。
- 共享输出在故障暂停后、旧输出释放前，仅抓取一次已绘制的视频层，作为恢复期间的停帧。普通网络 buffering 继续使用原生纹理，不逐帧抓图。图像只在内存中保留一张，限制到 1920×1080 范围（约 8 MiB），抓取等待最多 250 ms，不含弹幕、控件或磁盘写入。
- 停帧覆盖新输出，直到替换管线的音频与画面确认就绪；只有视频先就绪不会撤下停帧。暂停打开时沿用首次播放的音频确认门槛。显式停止、切换内容、释放会话会清理停帧；迟到的抓图结果按代次销毁，不污染新内容。
- 旧原生管线仍须完成释放屏障，新管线才允许分配。没有并存的影子播放器，不增加第二路音频；重试次数、总准备预算、用户暂停和源代次隔离继续沿用原规则。直播恢复仍从直播边缘打开，不把停帧当作直播续播位置。
- 应用实际使用的 [ConfigurablePlayerEngine](../../packages/bili_player/lib/src/configurable_player_engine.dart) 同样保留进度，并在重选后端、释放整个旧 runtime 前接管停帧。内部已有停帧时克隆图像句柄共享像素，不再做第二次读回；新后端确认播放或用户主动 seek 后撤下。仍可在下次打开时采用新保存的后端设置。

## 验证与边界

- [共享引擎测试](../../packages/bili_player/test/shared_player_engine_test.dart)：覆盖暂停、旧管线释放屏障、恢复全过程的位置／时长、新管线零样本、音频就绪与停止清理。
- [输出组件测试](../../packages/bili_player/test/switching_video_output_test.dart)：检查实际读回的像素、尺寸上限、解绑／新输出未就绪时的图像身份、视频先就绪时继续停帧、清理后的图像释放及迟到抓图取消。
- [会话测试](../../test/features/playback/playback_session_test.dart)：覆盖延迟解析、延迟 native open、首次音频失败的备用线路、恢复不经过 `stop()`，以及原有暂停／账号／换源／预算隔离。
- [后端选择测试](../../packages/bili_player/test/configurable_player_engine_test.dart)：覆盖实际包装层的旧 runtime 释放、选取新后端、准备阶段零样本和恢复参数传递；输出组件另验证子 runtime 销毁后共享图像句柄仍可读取原像素。

检查结果：根 `tool/check.ps1 -SkipPub` 的根应用测试 4719 项通过，13 项按原有条件跳过；首次包检查发现两项 fvp seek 中断回归，调整为先保存停帧、再中断待处理的原生请求后，通过 `-Stage PackageTests` 复验全部四包：API 719、播放器 325、弹幕 161、mux 5 项通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。随后在最终代码上复跑会话与播放面板 750 项通过；`-Stage Lint` 的格式、静态分析和打包边界检查通过。文档相对链接与 `git diff --check` 通过。日志保存在忽略目录 `build/validation/recovery-*.log`。

本轮的图像测试使用 Flutter 测试渲染器与可控输出；原生纹理读回、真实网络故障、扬声器音画同步和各平台的实际画面效果，留待用户自行构建后实机确认。无已绘制画面（首次加载、隐藏／未挂载输出）或图像读回超时时没有可保留的停帧；故障暂停和有界恢复仍继续，不能据单元测试宣称这些原生场景全部验收。

未启动新的 Debug 应用；DTD 检查未找到运行中的 Debug／DTD 进程，因此未执行热重载。
