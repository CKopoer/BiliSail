# 原生分轨测试素材

本目录的 12 秒色彩测试图与 440 Hz 正弦波由 FFmpeg 的 lavfi 信号生成，无真实视频、账号或签名 URL。它们只用于显式执行的原生集成测试，不打入正式应用资源。

生成工具使用本机 PATH 中的 FFmpeg，不随客户端分发。

```powershell
ffmpeg -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=12' -an -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 24 -movflags +faststart -y test/fixtures/media/video.mp4
ffmpeg -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=12' -vn -c:a aac -b:a 64k -movflags +faststart -y test/fixtures/media/audio.m4a
ffmpeg -f lavfi -i 'testsrc2=size=160x90:rate=24:duration=60' -an -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -g 24 -movflags +faststart -y test/fixtures/media/video_preview.mp4
```

执行 `./tool/test-windows-media.ps1` 验证本地 HTTP 分轨；显式加 `-Online` 才访问游客公开 API 和媒体 CDN。测试要求两轨实际解码，并检查音视频请求头、同主机重定向、Range、暂停/seek/倍速/释放重开。它不能替代人工音画同步、跨主机重定向或长时间稳定性测试。

60 秒无音轨测试图用于检查两后端悬停预览的 5 秒向前缓冲窗口、随进度补充、seek 后窗口及普通打开恢复 2 分钟窗口；使用本地 HTTP，不访问公网或账号。

`./tool/test-windows-buffer.ps1` 在忽略的 `build/validation/player-buffer-fixtures` 下生成 12 分钟的同类分轨素材，检查普通播放的 5 分钟向前窗口、暂停、播放推进、窗口外 seek 和短视频重开。它同样只访问本地 HTTP，不访问账号或公网；由 `test-windows-media.ps1` 一并执行。

Apple 视频回归另外使用三段 256×144、24 fps、3 秒的 10 位 HEVC 渐变。它们由 FFmpeg 的 `gradients` 和 libx265 生成，在回归中搭配同目录的独立 AAC 音轨。

| 文件 | 格式和可检查的元数据 |
| --- | --- |
| `hdr10.mp4` | BT.2020/PQ，1000 nit 母版，MaxCLL 1000、MaxFALL 400 |
| `hlg.mp4` | BT.2020/HLG，Profile 8.4 样片的同源基础层 |
| `p84.mp4` | 同一 HLG 码流，经 dovi_tool 2.3.1 的 `generate --profile 8.4` 和 `inject-rpu` 添加 72 帧 V2.9 元数据，MP4 的 dvvC 记录标明 profile 8、compatibility ID 4 |

可用 `ffprobe -show_streams -show_frames p84.mp4` 分别检查容器配置和实际帧的 Dolby Vision Metadata。渐变样片验证传输特性、元数据和渲染路径，画面观感另用真实母版验收。
