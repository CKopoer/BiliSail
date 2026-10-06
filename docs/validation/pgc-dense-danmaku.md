# 密集番剧弹幕与选集子标签

日期：2026-10-06。保留工作区已有及并行修改；未修改相邻参考仓库。

## 首集无弹幕的原因

用户报告 [名侦探柯南（中配）第一集 ep323085](https://www.bilibili.com/bangumi/play/ep323085) 整集没有弹幕，全屏也无效，出现过“弹幕暂时不可用”，而后续剧集正常。

本轮取得该集 `cid=184593713`。游客首段只有 1575 条普通弹幕，五段共解码 5291 条，游客 Windows 原生播放也显示弹幕，故游客烟测未复现问题。随后仅在显式启动的 Windows 在线探针内读取系统安全存储中的现有会话，未执行账户写操作，也没有持久化或输出凭据、弹幕正文或原始响应。

登录会话对照复现：

| 集数 | 首段 HTTP / 返回大小 | Protobuf 元素数 | 旧解码结果 |
| --- | --- | --- | --- |
| 第一集 `ep323085` | 200 / 1356802 字节 | 12801 | `danmaku_segment / protocol` |
| 第二集 `ep323086` | 200 / 565762 字节 | 5243 | 5243 条 |

首段最大单项仅 389 字节，未达到原有 4096 字节单项或 2 MiB 单段限制。实际失败点是解码器已经保留 6000 条后，将下一项视为协议错误。请求成功但整个分段被丢弃，应用层显示弹幕不可用；首集更容易超过条数限制，与用户观察一致。这不是全部番剧首集都无法请求的协议规则。

## 修复与容量边界

`decodeDanmakuSegment` 先按有界 Protobuf framing 计数，再完整验证每项。超过 6000 项时保留返回序列的首尾，并均匀抽样中间项；返回普通弹幕最多 6000 条，当前及相邻段的缓存预算不变。不依赖服务端元素按播放时间排序，抽样后继续由应用层按时间排序、过滤并装载播放窗口。

单段 2 MiB、单项 4096 字节、字符串字段 1024 字节限制，以及大响应 isolate、解码队列、取消/deadline/session epoch 检查保持有效。未知字段、无效 UTF-8 和截断消息仍检查，包括未被保留的项。抽样属于容量降级，超过预算时不保留全部原始弹幕。

本轮登录复测首段返回 12799 项，成功保留 6000 条；第二集仍完整返回 5243 条。数量是本轮在线快照，会随服务端弹幕池变化。

## 选集子标签

`PgcEpisodePanel` 的分组标签使用独立 `ScrollController`，复用 `SmoothScrollBehavior(horizontalMouseWheel: true)`。鼠标普通滚轮在标签条内横向浏览，底部 3px 拖动条在悬停时显示，并可拖至后方子标签。保留触摸横向滑动、当前分组、剧集列表/网格和排序行为；底部预留空间，拖动条不遮挡标签文字。

## 复测入口

```powershell
# 游客读取指定集的全部分段，仅输出计数、公开 ID 和分布。
dart run tool/pgc_danmaku_smoke.dart ep323085 --all-segments

# 显式读取当前 Windows 安全存储会话，只比较首/次集弹幕。
flutter test integration_test/windows_pgc_danmaku_probe_test.dart -d windows --dart-define=BILI_PGC_SAVED_SESSION=true

# 指定集的原生音视频与画面弹幕；SavedSession 仅用于显式本机在线验证。
./tool/test-windows-content.ps1 -Online -PgcEpisodeId 323085 -SavedSession
```

默认测试和 CI 不启用现有会话探针。安全存储未返回会话时，读取探针输出 `savedSessionAvailable=false`，不能当作登录验证；原生 `-SavedSession` 分支明确失败。在线工具仅执行 GET 和原生媒体读取，播放进度由测试用内存端口承接。

## 验证结果与边界

- `tool/check.ps1 -SkipPub` 全部通过：根应用 736、`bili_api` 236、`bili_player` 16、`bili_danmaku` 23，共 1011 项；四部分格式检查和静态分析通过。计数包含工作区当时已有的其他并行修改。日志：`artifacts/pgc-dense-final-check.log`。
- 新协议测试覆盖 6000 / 6001 / 12801 项、各分钟的采样覆盖、首尾保留、无重复 ID，以及未保留项中的无效 UTF-8、末尾截断和原有字节上限。既有 isolate/取消/排队/weight 测试继续通过。
- 选集组件测试验证普通滚轮移动标签而不移动外层竖向列表、鼠标悬停显示底部条、拖动至后方分组并选集、移出后取消常显，以及销毁无异常。与既有影视页面测试一起通过 13 项，包括长剧集、排序/网格和 320px 双倍字号。实际 Flutter 组件预览 `artifacts/pgc-section-tabs-preview.png` 已检查，使用项目字体；不是真实账号或原生播放截图。
- 登录只读探针修复前复现首集 `protocol`，修复后首集保留 6000 条、第二集保留 5243 条。日志：`artifacts/pgc-saved-session-probe-before.log`、`artifacts/pgc-saved-session-probe-after.log`。
- `tool/test-windows-content.ps1 -Online -PgcEpisodeId 323085 -SavedSession` 两项通过：既有受控 HLS/FLV 原生回归，以及该登录首集 DASH 音视频解码、真实 `DanmakuOverlay.visibleCount>0` 和后续直播音视频解码。首集同时使用 640×360 视口、100px 底部避让、0.4 显示区域、0.85 字号、权重阈值 3 和重复合并。日志：`artifacts/pgc-episode-signed-in-online.log`。
- `flutter build windows --debug --no-pub --target lib/main.dart` 通过，恢复普通应用入口，产物 `build/windows/x64/runner/Debug/bilisail.exe`，日志 `artifacts/pgc-dense-windows-build.log`。本轮未替换已安装的 MSIX。

Android/macOS 实机、所有番剧与会员/地区权益组合、长时间播放和 profile 性能未验证。本轮没有执行发送、投币、点赞或云端进度上报。
