# Windows 版本号升级与 Release 重打设计

## 目标

将当前项目的应用版本从 `0.9.2` 升级到 `0.9.3`，并重新构建 Windows Release 产物，使用户能够通过开屏欢迎弹窗、关于页和可执行文件属性明确识别“这是更新后的版本”。

## 背景

当前项目的版本来源已经比较清晰：

- `pubspec.yaml` 中定义应用版本号
- `package_info_plus` 在启动时读取平台版本信息
- 欢迎弹窗显示 `packageInfo.version`
- 关于弹窗显示 `packageInfo.version`
- Windows 可执行文件资源版本也来自 Flutter 构建时注入的版本信息

当前源码中的版本为 `0.9.2`，并且现有 `build/windows/x64/runner/Release` 目录中的产物仍然是旧构建，不包含刚完成的全局替换更新。

因此，仅保留当前 Release 目录并不能让用户直接判断是否已经用了更新版。

## 备选方案

### 方案一：只修改源码版本号

只修改 `pubspec.yaml` 中的版本号，不重新构建 Windows Release。

优点：

- 改动最小
- 操作最快

缺点：

- 现有 `build/windows/x64/runner/Release` 目录不会自动变成新版
- 用户仍可能运行到旧构建

### 方案二：修改版本号并重新构建 Windows Release（选中）

把 `pubspec.yaml` 版本升级为 `0.9.3`，然后执行 Windows Release 构建，刷新 `build/windows/x64/runner/Release` 下的产物。

优点：

- 版本号和实际功能更新保持一致
- 欢迎弹窗、关于页、exe 文件属性都会显示新版本
- 用户可以直接使用新的 Release 目录，无需猜测哪个是新版

缺点：

- 需要等待一次 Windows Release 构建完成

### 方案三：额外添加显式内部版本标记

除了修改版本号外，再在欢迎弹窗或关于页中增加一个额外说明，例如“grouped replace update”。

优点：

- 识别度最高

缺点：

- 会增加 UI 文案和逻辑改动
- 超出本次“只要方便判断是否更新”的最小目标

## 选中方案

采用方案二：

- 将版本号升级到 `0.9.3`
- 保持现有版本展示逻辑不变
- 重新构建 Windows Release 目录

## 展示与使用方式

### 开屏欢迎弹窗

欢迎弹窗标题当前使用：

- 应用名
- `packageInfo.version`

因此，在版本升级后，开屏欢迎弹窗会自动显示新版本号，无需额外修改展示逻辑。

### 关于页

关于页同样读取 `packageInfo.version`，因此构建完成后会自动显示 `0.9.3`。

### Windows 可执行文件属性

Windows 的 `Runner.rc` 使用 Flutter 注入的版本宏，因此重新构建后：

- `FileVersion`
- `ProductVersion`

都会更新为 `0.9.3`。

## 构建产物约定

本次完成后，用户应使用以下目录中的新产物：

- `build/windows/x64/runner/Release`

直接运行的入口文件为：

- `build/windows/x64/runner/Release/NAI_CasRand.exe`

但该 exe 不能脱离目录单独使用，必须连同以下内容一起保留：

- `data/`
- 同目录所有插件 `.dll`
- `flutter_windows.dll`

因此，实际分发或自用时应整体保留整个 `Release` 目录。

## 数据流与职责划分

### 配置层

只修改 `pubspec.yaml` 中的版本号：

- `0.9.2` -> `0.9.3`

### 构建层

通过 Flutter 的 Windows Release 构建命令刷新产物：

- 重新生成 exe
- 重新生成 Flutter 资源
- 重新写入 Windows 版本信息

### 展示层

不改 UI 代码。

现有欢迎弹窗和关于页会自动展示新的 `packageInfo.version`。

## 验证策略

本次不需要新增业务逻辑测试，重点验证构建结果是否正确。

验证项包括：

- `pubspec.yaml` 中版本为 `0.9.3`
- Windows Release 构建成功
- `build/windows/x64/runner/Release/NAI_CasRand.exe` 存在
- exe 的 `FileVersion` / `ProductVersion` 为 `0.9.3`
- Release 目录中的 `assets/l10n` 资源与当前源码一致

如有需要，可再手动运行 exe，确认开屏或关于页显示 `0.9.3`。

## 非目标

本次不做以下扩展：

- 不新增额外版本标签或更新渠道文案
- 不修改欢迎弹窗的触发逻辑
- 不处理自动更新机制
- 不额外生成 zip 安装包，除非后续明确需要

## 实现结论

为了让用户能够明确判断“是否已经使用了更新后的版本”，最稳妥的做法是直接升级应用版本到 `0.9.3` 并重新构建 Windows Release。完成后，`build/windows/x64/runner/Release` 才会是可直接使用的新版目录。
