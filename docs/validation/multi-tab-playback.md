# 多标签并发播放

日期：2026-10-06。当前工作区的增量修改，保留此前用户修改；不改相邻参考仓库。

## 行为与实现

- 原因是所有播放页共用一个 `PlaybackSession` 和 native engine，打开新视频会调用 stop 并替换旧媒体源，因此旧流中止而非保持暂停。
- `PlaybackManager` 按标签管理独立会话，app 注入原有 Repository、安全日志、账号／epoch 和进度端口的会话工厂；页面作用域按需创建并在关闭时释放。视频、影视、直播共用这个机制，每个标签内换源仍只有一个播放器。
- 多标签模式允许多个已打开的播放标签同时播放。隐藏页卸载 surface、绘制和快捷键，媒体继续推进；返回沿用同一源，不重算磁盘续播或重新请求 URL。
- 单标签模式进入其他播放页时先完成旧会话的原生暂停，再允许目标播放。播放许可同步更新并约束解析完成、用户命令和播放命令队列，快速导航不会放行过时目标。切到普通页面保留最近播放会话；导航暂停保留用户意图，返回或切回多标签模式时恢复，手动暂停保持暂停。
- 各页的刷新和视频／影视弹幕发送读取本页会话，避免使用另一标签的源／播放位置。全屏仍转交同一会话的 surface。关闭标签只释放自己的播放器；账号变化取消全部播放和旧请求，退出等待所有会话及已开始的释放。
- 不改变平台默认模式、16 页容量上限、凭据边界、插件／SDK 版本或数据库 schema；不增加系统后台服务或性能支持结论。

## 验证

- 会话回归新增多标签并发与独立进度／倍速、关闭单页、单标签导航互斥、手动暂停保留、迟到解析、延迟原生暂停、快速选择隔离、账号停止与全资源释放。
- 页面回归直接运行真实工作区 router、ProviderScope 和 PlaybackPanel，覆盖单／多标签初始模式、模式来回切换、隐藏 surface、返回原源和关闭标签。
- Windows 原生用两个独立 MediaKitEngine 打开本地 DASH 音视频分轨，确认两路均解码视频／音频并同时推进；切单标签后旧进度冻结，返回恢复原 generation，手动暂停与关闭一个会话不影响另一路。未使用真实账号或账户写操作。
- `tool/check.ps1 -SkipPub` 最终通过：根应用 707、`bili_api` 227、`bili_player` 16、`bili_danmaku` 21 项，共 **971 项**；四处格式检查和静态分析均通过。日志：`artifacts/multi-tab-playback-check-final.log`。
- 完整检查期间修正近期功能变更留下的测试夹具：合集页面显式注入游客控制器，播放快捷键测试安装已有 AppNoticeHost，工作区测试保留输入框的新标签屏蔽并覆盖 Ctrl+W 关闭行为。未改变对应生产逻辑。
- `tool/test-windows-media.ps1` 通过：执行 7 项本地原生验证，包含新增两路 DASH 并发、分轨 headers／重定向／Range、云端／本地进度、响应式／全屏、保留页面与 HTTP 403 脱敏诊断；未开启公网媒体分支。主文件日志中的 `+7` 包含一个未执行的公网分支，诊断文件另有 `+1`，不把这个提前返回计为实测。日志：`artifacts/multi-tab-playback-native.log`。
- `flutter build windows --release --no-pub -t lib/main.dart` 通过，入口为 `build/windows/x64/runner/Release/bilisail.exe`；日志：`artifacts/multi-tab-playback-windows-release.log`。正在运行的已安装 MSIX 应用未替换，新构建可从该目录运行。

本轮未构建 Android/macOS，二者没有设备实测；Windows 并发实测使用本地分轨 fixture，没有进行真实账号、公网多视频／PGC／直播并发或 CPU/GPU／内存测量。不将 Windows 并发结果推导为其他平台的播放、系统后台或性能验收。
