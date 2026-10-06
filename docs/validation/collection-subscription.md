# 视频合集订阅按钮

日期：2026-10-06。

## 行为

视频合集标题和播放量右侧显示紧凑粉色描边“订阅合集”按钮。游客点击调用现有登录入口。登录后按当前视频读取所属合集对当前账号的订阅态，显示“订阅合集”或“已订阅”；点击后可订阅或取消订阅，成功时更新按钮并显示提示。读取失败、状态字段缺失以及写入结果不明时显示“刷新状态”，重新读取后才能再次操作，不将未知状态当作未订阅。

状态读取只访问当前视频的关系接口，不再遍历账号收藏列表。请求目标包含合集与视频身份，按账号 scope、session epoch 和页面代次隔离；离开页面或切换账号时取消旧请求。合集写入仍使用详情中的合集 ID。

## 端点与来源

| 能力 | Host／方法／Path | 参数与协议 |
| --- | --- | --- |
| 订阅状态 | `api.bilibili.com` GET `/x/web-interface/archive/relation` | Web Cookie，当前视频 `bvid`，存在有效 `aid` 时一起传入；JSON `data.season_fav` 必须为布尔值，表示当前视频所属 UGC 合集的订阅态；只读请求沿用有界重试、取消与 25 秒总 deadline，不需 App token 或额外签名 |
| 订阅 | `api.bilibili.com` POST `/x/v3/fav/season/fav` | Web Cookie／正文 CSRF，`season_id`、`platform=web`；表单 JSON，单次提交、不自动重放 |
| 取消订阅 | `api.bilibili.com` POST `/x/v3/fav/season/unfav` | 同上；与“我的收藏与订阅”已有取消端点一致 |

2026-10-06 从公开 B 站视频页的 `__INITIAL_STATE__.insertScripts[0]` 取得当前[官网静态脚本](https://s1.hdslb.com/bfs/static/jinkela/video/video.05af4e80b6081ba56c1b5b943d4c8e621df3f875.js)，只读核对到完整数据流：

1. `Pc` 对 `/x/web-interface/archive/relation` 发 GET，视频操作状态读取传当前 `videoData.aid`、`videoData.bvid`。
2. 返回的 `data.season_fav` 通过 `sectionsFavStateChange` 写入 `sectionsFavState`。
3. 合集按钮按 `sectionsFavState` 显示“已订阅”或“订阅合集”；点击时也按该值选择 `/x/v3/fav/season/unfav` 或 `/fav`，提交的 `season_id` 为 `sectionsInfo.id`。

GitHub 上的 [BiliKernel 响应模型](https://github.com/Richasy/bili-kernel/blob/e26f6dbd071e20d4220806fcff7bd675f3c29fc5/src/Services/Services.Media/Core/Models/ArchiveRelationResponse.cs#L6-L14) 和 [PlayerClient](https://github.com/Richasy/bili-kernel/blob/e26f6dbd071e20d4220806fcff7bd675f3c29fc5/src/Services/Services.Media/Core/PlayerClient.cs#L727-L740) 对应同一接口和字段；[PiliPlus 响应模型](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc/lib/models_new/video/video_relation/data.dart#L1-L25) 和 [请求方法](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc/lib/http/video.dart#L317-L329) 也分别映射 `season_fav` 和传视频 `aid`／`bvid`。PiliPlus 的 UGC 按钮当前未使用该字段，语义确认采用官网自身按钮逻辑，而非仅凭字段命名推断。

订阅／取消表单另参考 PiliPlus 的[合集操作](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc/lib/http/fav.dart)，取消端点也对应本地 [FavoriteAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FavoriteAPI.cs)。这些来源仅用于核对协议事实，Dart／Flutter 代码独立编写，未复制参考仓库源码、schema 或资源，未修改相邻仓库。

## 前序错误与验证边界

此前 GET `/x/space/fav/season/list` 的公开正常响应没有 `info.fav_state`，据此读取该字段会报协议错误。但公开未登录响应缺字段，不能推导出没有可用的订阅态接口。首轮修正采用当前账号收藏列表分页匹配，现由上述关系接口替换；缺失 `season_fav` 时也不回退为全列表扫描。

无 Cookie 的关系接口只读请求返回 `code=-101`，本轮没有读取真实账号凭据或自动执行订阅／取消写入。官网当前数据流和 GitHub 模型已核对，登录态具体响应与按钮操作由用户验收。按用户要求不新增或运行测试流程；Android／macOS 本轮未构建或运行。

根应用 `flutter analyze --no-pub`、`bili_api` 的 `dart analyze` 均通过，5 个改动 Dart 文件的格式检查和差异空白检查通过。为隔离同时进行的工作区编辑，从独立源码快照 `build/collection-relation-state-source` 构建，`flutter pub get --enforce-lockfile` 和 `flutter build windows --release --no-pub` 成功，Windows Release 构建耗时 78.8 秒。预先复用已校验 MD5 的锁定版本 libmpv／ANGLE 压缩包；仍有插件既有 CMake CMP0175 开发警告。

完整 Release 导出至 `artifacts/bilisail-collection-relation-state-windows-x64`，入口为 `bilisail.exe`。入口 SHA-256 为 `043C4DE53B330D3C6702C45FA4D8B126EBF0470D8F9E4ECB09183F22329D9C95`，`data/app.so` 为 `C34DD3F0D1AFCA7B5C464753E33CA548FB03E522F23450DE354D3029142AAEDE`；已核对导出与构建一致、快照中的合集源码／主入口／Windows 语义保护／根锁文件与当前工作区一致。日志位于忽略目录 `build/crash-diagnostics/collection-relation-*.log`。未自动启动新版；应从完整目录运行，真实登录订阅／取消和持续播放交由用户验收。
