# 空间头部、隐私内容与主页操作修复

后续同日已将本记录中的官方网页举报入口替换为[应用内举报表单](profile-report-2026-11-05.md)，以下保留本轮原始实施和验证记录。

日期：2026-11-05。用户要求仅做代码、自动测试与提交，构建及实机验收由用户完成。

## 参考与实际范围

只读参考相邻 PiliPlus `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/pages/member/view.dart`、`member/controller.dart`、`member/widget/user_info_card.dart`、`common/widgets/pendant_avatar.dart`、`common/widgets/dialog/report_member.dart`、`http/member.dart`、`http/api.dart` 和 `models_new/space/space/images.dart`。参考头图/头像挂件/认证及会员标识的层次、黑名单的确认操作和官方举报入口；独立编写 Flutter/Riverpod 与 Dart 实现，没有复制 GPLv3 应用源码、资源或 schema，没有改动相邻仓库或增加依赖。

还只读核对了当前[官方空间脚本](https://s1.hdslb.com/bfs/static/shanks/fresh-space/assets/index-c5b07bd7.js)：`privacy.fav_video`、`privacy.bangumi` 控制访客内容是否公开，空间本人可查看自己的列表；`top_photo_v2.l_img` 为新版头图字段。未采用其代码。

本轮以游客 GET 请求核对公开 `/x/web-interface/card?mid=2&photo=true`，实际返回 `data.space.l_img`、`card.pendant.image`、`vip.status/type` 与 `vip.label` 的静态图片字段；没有读取或复制本机账号凭据，没有执行真实账号写入。该只读响应验证不代表用户设备界面验收，也不保证其他用户一定具有全部装扮字段。

## 改动

- 基本用户名片请求增加 `photo=true`，用返回的 `space.l_img`（缺失时尝试 `s_img`）显示对应空间图片。这样扩展资料的 WBI 请求受限时仍可使用基本名片提供的头图；扩展资料成功时优先 `top_photo_v2.l_img`，兼容旧 `top_photo`。预览使用同一有效头图地址。
- 头像叠加用户返回的挂件图片，右下显示既有个人/机构认证徽章，未认证的有效大会员显示会员标识；名称区域保留等级，会员标签优先服务端提供的静态图片，没有有效图片时使用服务端会员文字。只有 `vip.status=1` 显示会员标识，过期会员标签不再出现。图片仍通过既有有界缓存加载，错误不会改变头像加载语义。
- 头图、挂件、会员图片缺失或地址不合法时不编造用户装扮：头图保留既有中性背景，挂件缺失直接省略。没有引入 App token 或 App 空间端点；PiliPlus 的夜间/合集皮肤与佩戴直播粉丝勋章等 App 专属信息未在本轮实现。
- 更多菜单支持加入/移出黑名单，游客先登录。Web `/x/relation` 读取 `attribute` 的黑名单位，`/x/relation/modify` 显式 POST `act=5/6`、`re_src=11` 并沿用 Cookie/CSRF。确认弹窗绑定当前用户、仓储实例、账号 scope、session epoch 与已读状态快照；进行中的操作不重复提交。结果不明时清除已知状态，必须先刷新核对，禁止自动重放。关闭空间和账号变化取消请求，迟到结果不再更新状态；成功后失效共享关注状态，避免拉黑后的关注按钮显示旧值。
- 举报菜单明确标为“举报（打开官方页面）”，使用现有公共网页打开端口前往 `https://account.bilibili.com/h5/account-h5/gr/report?navhide=1&targetmid=<mid>`；不向外部浏览器注入本机 Cookie，也不假装完成举报。浏览器登录、提交及受理仍由官方页面处理。
- 访问他人收藏夹/追番/追剧前读取 `/x/space/setting` 的对应公开标记，隐藏时返回既有 `ProfilePage.hidden`，显示“该用户未公开…列表”，停止分页。本人跳过访客隐私判断；认证、风控、网络、协议及真实内容错误仍保持错误语义，不将所有 `-403/-404` 误判为隐藏。
- 左上角增加空间页内返回，加载中、资料失败时也可使用。先退出已打开的收藏夹/合集详情，再交给既有工作区返回；移除旧 shell 独立返回行，避免窄屏重复。修正桌面双标签浏览页的导航回调目标，空间返回不再误操作分离播放窗。

## 验证

- `dart test test/profile_client_test.dart test/profile_fixes_client_test.dart`：40 项通过；`dart analyze` 对本轮 API 源码与新增测试无问题。
- `flutter test --no-pub test/features/profile test/app/windowed_workspace_test.dart test/app/workspace_router_test.dart`：320 项通过。回归包含会员有效期/真实图片字段、收藏/追番/追剧隐藏与本人权限、真实错误保留、黑名单确认/取消/不确定结果/重复点击、账号切换和关闭后迟到读写、官方举报目标、加载/失败返回。
- 真实路由测试分别确认单标签、双标签从视频进入空间后，页内返回先关闭收藏夹详情，再返回工作区历史，保留原 `VideoScreen`、分 P、`PlaybackSession` 与 engine。分离窗口回归以 fake window 验证浏览页返回不关闭播放窗口；不是原生窗口实机验收。
- 根检查脚本由主会话汇总执行并记录最终结果；本轮未执行构建、安装、热重载或真实账号黑名单/举报写入。

实机待用户确认：不同账号真实头图与挂件/会员图片的显示、各类隐私空间及本人列表、官方举报页面的浏览器登录与提交、单/双/多标签下返回及播放保持，以及 Android/macOS/Windows 的实际界面。
