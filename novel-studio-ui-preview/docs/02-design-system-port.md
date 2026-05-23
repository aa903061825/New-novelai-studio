# 设计系统迁移到 Flutter

## 基本原则

预览使用的是参考目录里的 ZZZ Studio Design System。迁移到 Flutter 时不要照搬 CSS，而是把 token 转成 Dart 常量和 ThemeExtension。

核心风格：

- 暗色五层 surface。
- 黄色是唯一主 CTA 和全局选中态。
- 绿色只用于通过、在线、可用等状态。
- 按钮和标签是胶囊形。
- 卡片和装饰容器右下角尖锐。
- 中文正文不使用斜体。
- 高密度工具界面，不做营销式大卡堆叠。

## Flutter token 建议

建议新增：

```text
lib/ui/studio_core/theme/studio_tokens.dart
lib/ui/studio_core/theme/studio_theme.dart
```

`StudioTokens` 至少包含：

```dart
class StudioTokens {
  static const surfaceBase = Color(0xFF0A0A0A);
  static const surface1 = Color(0xFF111111);
  static const surface2 = Color(0xFF141414);
  static const surface3 = Color(0xFF1C1C1C);
  static const surface4 = Color(0xFF242424);

  static const primary = Color(0xFFFFE500);
  static const secondary = Color(0xFFA8E030);
  static const active = Color(0xFF4ADE80);
  static const danger = Color(0xFFFF4B4B);
  static const warning = Color(0xFFFF9A3C);
  static const info = Color(0xFF6EB9FF);

  static const radiusPill = BorderRadius.all(Radius.circular(999));
  static const radiusCard = BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(16),
    bottomRight: Radius.circular(4),
  );
}
```

生产代码里不一定要逐字照这个类，但必须有一个单一 token 来源，避免每个 widget 手写颜色和圆角。

## ThemeData 建议

- `scaffoldBackgroundColor`: `surface1`
- `cardColor`: `surface3`
- `colorScheme.primary`: `primary`
- `colorScheme.secondary`: `secondary`
- `colorScheme.error`: `danger`
- `textTheme`: 使用正体中文，数字/ID 可以局部使用 monospace。
- `filledButtonTheme`: 黄色主按钮，pill radius。
- `outlinedButtonTheme`: 黄色描边或默认边框，pill radius。
- `chipTheme`: pill radius，选中态黄色或黄绿。
- `cardTheme`: `radiusCard`，暗色容器，弱边框。

## 组件形状规则

| Flutter 元素 | 形状 |
|---|---|
| 主按钮 / 次按钮 / 图标按钮 | `radiusPill` |
| Chip / Badge / Tab | `radiusPill` |
| 页面 Panel / 素材卡 / 画廊卡 | 右下角 4 的 `radiusCard` |
| 输入框 / textarea / dropdown | 对称小圆角 |
| Dialog / BottomSheet | 对称大圆角 |

## 图标建议

Flutter 现有 Material Icons 足够第一版使用：

| 语义 | 建议 Icon |
|---|---|
| 主页 | `Icons.home_outlined` |
| 素材库 | `Icons.inventory_2_outlined` |
| 工作台 | `Icons.dashboard_customize_outlined` |
| 批量产线 | `Icons.account_tree_outlined` |
| 画廊 | `Icons.photo_library_outlined` |
| 设置 | `Icons.tune` |
| 导入 | `Icons.file_upload_outlined` |
| 导出 | `Icons.file_download_outlined` |
| 生成 | `Icons.auto_awesome` |
| 送回工作台 | `Icons.keyboard_return` |

## 文案规范

保留这类文案：

- `当前工作台还没有内容，可以先导入一份方案。`
- `准备好 Prompt 后，在这里生成第一张图。`
- `生成完成，结果已写入画廊。`
- `已送回工作台。`
- `输出目录不可写，无法保存图片。`

避免这类文案：

- 暴露三源迁移流程。
- 暴露 Workspace loader。
- 把内部诊断作为普通页面标题。
- 把产品描述成写作或章节管理工具。

## 视觉验收

每个主要页面完成后至少截图检查：

- 1440 宽桌面窗口：三栏工作台不拥挤。
- 1180 左右窗口：导航和内容仍可读。
- 900 以下窗口：能堆叠，不发生文字覆盖。
- 中文按钮不溢出。
- 主 CTA 永远是黄色。
- 状态通过/可用才使用绿色。
