# 动态预约与取消预约

日期：2026-11-12；2026-11-13 补充组件主体点击隔离。

## 行为

- 首页、UP 主空间、话题及详情使用共享动态卡片；转发中的预约使用原动态 ID。按钮根据 `status == type` 判断已预约，不能将任意 `status=1` 视为已预约。
- 显式点击才提交预约／取消预约。游客点击进入既有登录提示；处理中禁用重复点击，成功后采用服务端返回的按钮状态、人数和说明，不在本地猜测人数。
- 点击预约组件的标题、说明或空白区域保留当前页面，也不触发外层动态详情；预约／取消预约及服务端明确的跳转按钮各自处理按钮操作。此规则同样适用于转发和预约元数据不完整的卡片。
- 已结束、禁用的预约停止写入；带跳转地址的按钮沿用导航语义。预约身份、数量或按钮状态缺失／非法时保留只读卡片，不猜测写入参数。
- 同一预约 ID 共用账号内的状态和进行中请求，刷新后出现的结束／禁用／跳转能力优先于旧操作缓存。状态缓存及未知结果锁各有最多 512 项，账号 scope／session epoch 变化时清理。
- 网络、超时、HTTP 或响应格式异常视为结果不明，禁止重复提交；按钮改为“刷新预约状态”，只读请求对应动态详情，确认相同预约 ID 的有效状态后解除锁。页面关闭取消请求，未能观察到写入结果时保留刷新锁；迟到响应不能改变新账号或新请求状态。
- 静态布局测量仍使用无 Provider 订阅的卡片，不触发账号请求。

## 协议登记

| 能力 | host / method / path | 参数、鉴权与重试 |
| --- | --- | --- |
| 预约／取消预约 | `api.bilibili.com` POST `/x/dynamic/feed/reserve/click` | JSON：`reserve_id`、`cur_btn_status`、`dynamic_id_str`、`reserve_total`；Web Cookie 必需，query 注入 CSRF；无分页，只提交一次，无自动重试 |
| 状态确认 | `api.bilibili.com` GET `/x/polymer/web-dynamic/v1/detail` | 沿用动态详情 `id` 和 `features=itemOpusStyle`；只读有界重试，应用 deadline 与取消保持既有实现 |

预约 ID 和动态 ID 均保留十进制字符串，禁止经浮点数转换。写响应要求 `final_btn_status`、`reserve_update` 为非负整数，`desc_update` 为字符串；响应不完整不能当作成功。客户端不在 UI 层解析 JSON，也不记录凭据。

## 参考与许可

只读参考本机 PiliPlus 提交 `cab0114a21ce7fad5b90b9a4d788d35d313d25f9`：

- [附加卡片交互](../../../PiliPlus/lib/pages/dynamics/widgets/additional_panel.dart)：预约按钮判断、禁用、跳转以及响应更新职责。
- [HTTP 方法](../../../PiliPlus/lib/http/dynamics.dart) 与 [端点](../../../PiliPlus/lib/http/api.dart)：`dynReserve` 的 JSON 字段及 CSRF 位置；请求默认 JSON 另核对 [Request](../../../PiliPlus/lib/http/init.dart)。
- [预约卡片模型](../../../PiliPlus/lib/models/dynamics/result.dart) 与 [更新模型](../../../PiliPlus/lib/models_new/dynamic/dyn_reserve/data.dart)：按钮状态、人数、描述字段。

PiliPlus 应用为 GPLv3；本次只借鉴协议字段及交互职责，独立编写本项目 Dart／Flutter 实现和脱敏 fixture，未复制其源码或资源，未修改相邻仓库、引入其依赖或变更本项目固定媒体依赖。采用边界沿用[参考文档](../references.md)。

## 验证与边界

定向单元／组件测试覆盖协议、CSRF、长 ID、非法／不完整响应、单次写入、预约与取消、服务端人数、游客登录、禁用／结束／跳转、转发身份、未知结果只读确认、页面关闭和账号切换的取消／迟到隔离。

首轮 `tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界检查，以及根应用 5260、`bili_api` 917、`bili_player` 212、`bili_danmaku` 161、`bili_mux` 5 项测试。测试按配置另跳过根应用 13、播放器 1、mux 原生 10 项；mux 未配置 `BILI_MUX_LIBRARY`，不计为原生验证通过。文档相对链接及 `git diff --check` 通过。

2026-11-13 点击隔离补充：新增 4 项组件回归，覆盖普通／转发、有／无预约元数据下点击标题、说明和空白区域，不导航、不打开动态详情或提交预约；原有预约、取消及跳转按钮回归继续通过。定向 19 项测试通过，`tool/check.ps1 -SkipPub` 再次通过（根应用 5270 项通过，四包通过及跳过数量与首轮相同）。

按用户要求不构建，不操作真实账号预约，不进行实机测试；线上接口可用性与各平台实际交互留待用户构建后验收。普通检查未配置 `BILI_MUX_LIBRARY` 时跳过 mux 原生用例，不计为原生验证通过。
