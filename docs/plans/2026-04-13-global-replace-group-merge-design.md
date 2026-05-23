# 全局替换多词合并规则设计

## 目标

升级现有“全局替换”功能，使一条规则可以用逗号分隔的多个候选 tag 表达一组可互斥或可归并的提示词。

当 prompt 中命中同组内多个 tag 时，系统应：

- 以 prompt 中实际最早出现的命中项作为锚点位置
- 在该位置写入一个目标 `target`
- 删除同组中其余命中的 tag

这样可以把诸如 `black panties, white thighhighs, white strapless dress, short skirts, white rabbit tail` 这一组词，合并替换成一个新的目标词，同时自动清理组内其它已出现的词。

## 背景

当前项目已经具备完整的全局替换编辑能力：

- `PromptReplaceRule` 只包含 `source`、`target`、`enabled`
- UI 支持新增、复制、删除、排序、启停和批量录入
- 生成前替换逻辑集中在 `lib/data/use_cases/generate_payload_use_case.dart`

当前执行语义仍然偏向“单条短语替换”：

- `source` 会被视为一个整体短语
- 通过空白归一化构造正则后，在整段字符串上直接替换
- 不支持把一个 `source` 解释为逗号分隔的多个候选 tag

因此，现有实现无法表达用户所需的“命中多个词时，保留一个目标词并删除其它命中项”的合并替换语义。

## 备选方案

### 方案一：所有规则都改为 tag 级替换

把所有规则都解释为逗号分隔 tag 列表，在 tag 层级完成查找、替换和删除。

优点：

- 语义统一
- 更贴近逗号分隔 prompt 的常见使用方式

缺点：

- 会改变已有单条规则的行为
- 兼容风险高

### 方案二：仅在 `source` 含逗号时启用多词合并规则（选中）

保留旧规则语义不变；当 `source` 中包含 `,` 或 `，` 时，把该规则解释为一组候选 tag，并启用多词合并替换。

优点：

- 与用户的新需求精确对应
- 对现有单条替换规则兼容性最好
- 不需要新增模型字段和复杂 UI

缺点：

- 同一个规则系统会同时存在两种执行语义

### 方案三：新增规则类型字段

为 `PromptReplaceRule` 增加“普通替换 / 合并替换”等模式字段，由用户显式选择。

优点：

- 语义最清晰
- 可扩展性最好

缺点：

- 需要修改模型、存储、UI、交互和测试
- 对本次需求来说成本过高

## 选中方案

采用方案二：

- `source` 不含逗号时，继续沿用现有单条替换逻辑
- `source` 含逗号时，启用新的“多词合并替换”逻辑

该方案在满足新需求的同时，尽量避免破坏现有配置和使用习惯。

## 核心语义

### 规则识别

一条规则满足以下任一条件时，视为“多词合并替换规则”：

- `source` 包含英文逗号 `,`
- `source` 包含中文逗号 `，`

解析时：

- 按逗号拆分 `source`
- 对每个候选项做首尾空白裁剪
- 忽略空项
- 保留用户书写顺序，仅用于配置表达，不用于决定最终锚点位置

### Prompt 拆分

执行多词合并替换时，把待处理 prompt 视为逗号分隔的 tag 列表。

解析时：

- 按英文逗号拆分输出 prompt
- 对每个 tag 保留原始文本、裁剪后的文本和可比较的归一化文本
- 记录每个 tag 在 prompt 中的原始顺序

第一版假定 prompt 采用标准逗号分隔 tag 列表，不额外支持“tag 内部本身包含逗号”的复杂写法。

### 命中规则

每个候选 tag 都独立判断是否存在于 prompt 中。

匹配时使用归一化后的可比较文本，而不是直接比较原始字符串。这样可以兼容权重外壳和空白差异。

若同组内多个候选项命中，则：

- 按 prompt 中实际出现顺序选择最早出现的命中项作为锚点
- 在锚点位置放入 `target`
- 删除同组里其它命中的项

若只有一个候选项命中，则把该位置直接替换为 `target`。

若没有候选项命中，则该规则不生效。

### 重复命中

若同一组中的候选 tag 在 prompt 中出现多次，也统一折叠为一个 `target`，避免替换后仍残留重复项。

例如：

- 规则 `source`: `black panties, white thighhighs`
- 规则 `target`: `bunny outfit`
- prompt: `1girl, black panties, white thighhighs, black panties`

结果应为：

- `1girl, bunny outfit`

## 权重感知匹配

### 匹配归一化

第一版将以下形式视为“权重外壳”：

- 数字权重：`1::tag::`、`0.8::tag::`
- 花括号权重：`{tag}`、`{{tag}}`

匹配时会抽取其中的核心内容参与比较：

- `1::black panties::` 归一化后按 `black panties` 匹配
- `{white thighhighs}` 归一化后按 `white thighhighs` 匹配

因此，规则中写 `black panties, white thighhighs` 时，也可以命中 prompt 中的：

- `1::black panties::`
- `0.8::black panties::`
- `{white thighhighs}`
- `{{white thighhighs}}`

### 权重继承

当锚点位置本身带有权重外壳时，是否继承该权重，取决于 `target` 自身：

- 若 `target` 是普通文本，则继承锚点位置的权重外壳
- 若 `target` 自己已经带权重外壳，则不再继承锚点权重，直接使用 `target` 原样落位

示例一：

- prompt: `1::black panties::, white thighhighs`
- target: `bunny outfit`
- 结果: `1::bunny outfit::`

示例二：

- prompt: `1::black panties::, white thighhighs`
- target: `0.8::bunny outfit::`
- 结果: `0.8::bunny outfit::`

这样可以避免出现双层或嵌套的权重包裹结果。

## 输出重建

多词合并替换完成后，需要把 tag 列表重新拼接回 prompt 字符串。

重建原则：

- 自动移除被删除后产生的空项
- 统一用 `, ` 连接剩余 tag
- 不保留多余逗号和空白残留
- 未命中的 tag 保持原有相对顺序

## 数据流与职责划分

### 模型层

`PromptReplaceRule` 第一版不新增字段，仍使用现有结构。

是否进入多词合并替换模式，由 `source` 是否含逗号决定。

### Use Case 层

主要改动集中在 `lib/data/use_cases/generate_payload_use_case.dart`：

- 保留当前单条替换逻辑作为旧规则路径
- 新增多词合并替换路径
- 为 prompt tag 解析、比较归一化、权重识别、权重继承和结果重建提供私有辅助方法

### UI 层

第一版不要求新增界面字段或额外控件。

现有规则编辑器仍沿用：

- 用户在 `source` 中输入逗号分隔列表，即表示一组候选词
- `target` 填写合并后的目标词

必要时只补充说明文案，让用户知道“逗号分隔 source 会启用多词合并替换”。

## 错误处理与边界

- `source` 拆分后全为空：按无效规则处理，不执行替换
- `target` 为空：删除整组命中的项，不留占位
- prompt 中没有任何命中项：不做修改
- prompt 中已存在一个独立的 `target`：本次不自动去重，避免系统偷偷删词
- 第一版只识别本次明确约定的权重外壳；其它复杂语法暂按普通文本处理

## 测试策略

### Use Case 测试

在 `test/data/use_cases/generate_payload_use_case_global_replace_test.dart` 增加或扩展测试，覆盖：

- `source` 含逗号时启用多词合并替换
- 按 prompt 中实际出现顺序选择锚点
- 命中多个候选词后只保留一个 `target`
- 同组候选词多次出现时折叠为一个 `target`
- `1::...::` 能参与匹配
- `{...}` 能参与匹配
- `target` 无权重时继承锚点权重
- `target` 自带权重时不继承锚点权重
- `target=''` 时整组删除
- 单 source 旧规则仍保持兼容

### Widget / L10n 测试

若补充了规则说明文案，则同步更新：

- `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`
- `test/l10n/prompt_replace_l10n_keys_test.dart`

但本次需求的核心验证重点仍是 Use Case 层，而不是 UI 层。

## 非目标

本次不做以下扩展：

- 不新增独立规则类型字段
- 不在第一版支持更多复杂权重语法
- 不处理 tag 内部自带逗号的特殊语法
- 不自动去重 prompt 中原本就存在的独立 `target`
- 不修改 negative prompt / UC 的处理范围

## 实现结论

该需求可以在不重做现有规则编辑器的前提下完成。最小且稳妥的改法是：

- 保留旧规则路径，确保兼容
- 为 `source` 含逗号的规则增加 tag 级多词合并替换语义
- 在匹配中识别常见权重外壳，并在必要时继承锚点权重

这样既能满足“多个候选词命中后只保留一个目标词”的使用方式，也能兼顾已有配置和带权重 prompt 的实际使用场景。
