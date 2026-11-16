# flutter_markdown_plus 本地移植

- 来源：[flutter_markdown_plus 1.0.12](https://pub.dev/packages/flutter_markdown_plus/versions/1.0.12)，[上游仓库](https://github.com/foresightmobile/flutter_markdown_plus)。
- Pub 归档 SHA-256：`fce641d6c2106cc495de1cd603f97a4f9d615a97a64011928ded380dbdade935`。
- 保留原始 `lib` 源码版权头和 BSD-3-Clause `LICENSE`。许可证随 Flutter notices 分发。
- 本地版本 `1.0.12+bilisail.1` 不发布；只使用本仓库 path，不修改 Pub 缓存或相邻仓库。
- 直接将 Material/Cupertino 导入迁移为独立 `material_ui` / `cupertino_ui`，同步 Flutter 3.50 / Dart 3.14 最低约束和精确依赖。保持 Markdown 解析、选择、链接、图片、表格及布局逻辑。
- 根静态分析与更新说明组件测试覆盖此移植，根检查脚本检查 `lib` 格式。后续上游完成迁移后可恢复托管依赖。

另移除两个图片 URI 帮助函数形参上的 `final` 修饰符，适配 Dart 3.14 的语法要求；不改变参数或图片处理行为。
