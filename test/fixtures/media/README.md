# 原生分轨测试素材

本目录的 12 秒色彩测试图与 440 Hz 正弦波由 FFmpeg 的 lavfi 信号生成，无真实视频、账号或签名 URL。它们只用于显式执行的原生集成测试，不打入正式应用资源。

生成工具使用本机 PATH 中的 FFmpeg，不随客户端分发。

```powershell
ffmpeg -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=12' -an -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 24 -movflags +faststart -y test/fixtures/media/video.mp4
ffmpeg -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=12' -vn -c:a aac -b:a 64k -movflags +faststart -y test/fixtures/media/audio.m4a
```

执行 `./tool/test-windows-media.ps1` 验证本地 HTTP 分轨；显式加 `-Online` 才访问游客公开 API 和媒体 CDN。测试要求两轨实际解码，并检查音视频请求头、同主机重定向、Range、暂停/seek/倍速/释放重开。它不能替代人工音画同步、跨主机重定向或长时间稳定性测试。
