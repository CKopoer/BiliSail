# 主页卡片与富动态

日期：2026-10-05。参考用户提供的 UWP 投稿截图、本机已安装 UWP 的投稿/空间动态界面及相邻仓库，来源与采用边界见 [参考文档](../references.md)。

## 展示与数据边界

- 自己与其他 UP 主沿用同一用户空间。投稿改为横向封面卡，封面叠加时长，标题下方展示观看、弹幕与发布日期，保留既有搜索、排序、分页和点击播放。
- 首页“动态”和空间“动态”共用居中、限宽的动态卡；作者、时间、正文、媒体、转发引用及只读统计各自独立展示。视频动态频道保留已有专用视频列表。
- 富文本支持行内表情图片、普通文字、提及与话题；服务端未知节点或图片失败保留文本。表情读取随动态响应返回的节点，不请求发送表情面板、不新增发动态或账号写操作。
- 两个入口继续使用 `api.bilibili.com` 的 Web GET `/x/polymer/web-dynamic/v1/feed/all` 和 `/x/polymer/web-dynamic/v1/feed/space`，JSON、当前 Web Cookie、无 WBI/CSRF；显式请求 `features=itemOpusStyle` 获取图文正文/表情，分页保留 `offset` 原值与已有游标校验，沿用请求 deadline、有限重试、取消及账号隔离。
- 协议 DTO 留在 `bili_api`，共享领域模型不依赖 Flutter 或 JSON。每页最多解析 100 条，每条最多 256 个富文本节点、32,768 个正文字符、9 张图片及两层转发引用；更深引用提供官方查看提示。首页动态/视频动态每个列表最多保留 200 条，到达上限提示刷新；空间列表沿用 500 条上限。被删除和不支持的动态类型降级为提示/官方页面入口。

## 验证

Windows 实际界面检查暴露了两个协议兼容点：正常媒体也带有 `none: null` 联合字段，不能按 key 存在判断已删除；部分图文在默认请求中只有 `draw.items`、没有正文，带 `features=itemOpusStyle` 后返回 `opus.summary` 的文本/表情及 `opus.pics`。解析同时兼容空 `desc` 占位，并对上述场景添加两入口回归。

开发诊断 `tool/dynamic_schema_probe.dart` 仅在显式运行时使用应用现有安全会话，对首页动态做两次只读形态对比，输出字段名、类型和长度；不输出或保存正文、用户 ID、图片地址、Cookie、token。普通启动与 CI 不调用该工具。运行命令为 `flutter run -d windows --profile -t tool/dynamic_schema_probe.dart`；之后使用 `flutter build windows --profile -t lib/main.dart` 恢复正常应用构建。

2026-10-05 最终验证：

- `tool/check.ps1 -SkipPub` 通过：根应用 216、`bili_api` 76、`bili_player` 16、`bili_danmaku` 5 项测试，合计 313 项；根应用与三个包的格式、静态分析均通过。依赖未变更，复用已解析的锁定依赖。
- 行为测试覆盖富文本/表情解析、空联合字段与 `opus.summary` 兼容、图文标题保留、转发层数和图片上限、图片预览、长正文展开/收起、正文换行、四图两列/九图三列，以及窄屏/两倍文字缩放的组件排版。首页动态缓存上限及刷新重置有控制器测试。
- `flutter build windows --profile -t lib/main.dart` 成功，使用生成的 Profile 应用运行在线界面检查。普通窗口展示两列投稿卡，最大化后为三列；封面、时长、标题、播放/弹幕数和日期正常。首页动态及空间动态均确认真实图文正文换行、行内表情图片、单图、视频卡和统计显示；动态图片预览成功打开、加载和关闭，点击作者能进入对应空间。
- 检查日志保存在本机忽略目录 `artifacts/profile-dynamic-check.log` 与 `artifacts/profile-dynamic-build.log`。UI 检查不触发点赞、投币、关注、发送等账号写操作。

未验证部分：Android/macOS 构建与设备运行、本轮未采样到的动图表情动画效果；四图/九图和转发组合以脱敏协议/组件测试为验证依据。Windows Profile 界面结果不代表三端验收完成，本次没有进行性能结论或新增原生播放能力验收。
