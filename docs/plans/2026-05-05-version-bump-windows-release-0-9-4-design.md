# Windows 0.9.4 正式版发布设计

## 目标

把当前项目版本从 `0.9.3` 升级到 `0.9.4`，并重新生成 Windows `Release` 正式版产物，使以下几个版本信号保持一致：

- `pubspec.yaml` 中的源码版本
- Windows exe 的 `FileVersion` / `ProductVersion`
- 应用开屏欢迎弹窗中的版本号
- 关于页中的版本号

最终交付物是 Windows 下可直接使用的新版 `Release` 目录。

## 当前状态

当前源码版本在 `pubspec.yaml` 中为：

- `0.9.3`

当前项目的版本显示链路已经比较清晰：

- `pubspec.yaml` 是版本源头
- Flutter Windows 构建会把版本注入 Windows runner 版本宏
- `NavigationAppBar` 关于页直接显示 `packageInfo.version`
- `NavigationView` 开屏欢迎弹窗也直接显示 `packageInfo.version`

因此，只要版本号升级并重新构建，关于页和开屏理论上都会随版本更新而自动变化。

## 需求定义

本次要完成的是：

1. 把源码版本升级到 `0.9.4`
2. 重新构建 Windows `Release` 正式版
3. 验证 exe 文件属性版本变为 `0.9.4`
4. 验证开屏显示版本为 `0.9.4`
5. 验证关于页显示版本为 `0.9.4`

## 备选方案

### 方案一：只改版本号，不重建 Windows Release

优点：

- 改动最快

缺点：

- 已有 `Release` 目录不会变成新版
- exe 文件属性仍可能是旧版本
- 用户运行到的仍可能是旧构建

### 方案二：升级版本并重建 Windows Release（选中）

优点：

- 版本号与实际产物一致
- Windows 文件属性同步更新
- 开屏和关于页会读取到新的版本号
- 用户可以直接把 `build/windows/x64/runner/Release` 当正式版目录使用

缺点：

- 需要等待一次完整 Windows Release 构建

### 方案三：升级版本并额外修改 UI 文案显示“正式版”

优点：

- 用户更容易分辨

缺点：

- 增加额外 UI 改动
- 超出本次最小目标

## 选中方案

采用方案二：

- 只升级版本号到 `0.9.4`
- 不额外改版本展示 UI 逻辑
- 通过重新构建 Windows `Release` 让现有版本显示链路自动更新

## 版本显示链路

### 源码版本

版本源头在 `pubspec.yaml`：

- `version: 0.9.3` -> `version: 0.9.4`

### Windows 文件属性版本

`windows/runner/CMakeLists.txt` 中通过 Flutter 注入的版本宏参与构建：

- `FLUTTER_VERSION`
- `FLUTTER_VERSION_MAJOR`
- `FLUTTER_VERSION_MINOR`
- `FLUTTER_VERSION_PATCH`
- `FLUTTER_VERSION_BUILD`

因此不需要手工修改 `Runner.rc`，只需要重新执行 Windows Release 构建。

### 开屏欢迎弹窗版本

`NavigationView` 中开屏标题使用：

- 应用名
- `packageInfo.version`

并且弹窗是否显示由 `settings.welcomeMessageVersion` 控制：

- 如果缓存值等于当前版本，则不再显示
- 如果当前版本变为 `0.9.4`，而旧缓存还是 `0.9.3` 或更早，则欢迎弹窗会再次出现，并显示新版本

因此这次不需要改开屏逻辑，但需要把“欢迎弹窗显示 `0.9.4`”纳入验证。

### 关于页版本

`NavigationAppBar` 的关于页同样读取 `packageInfo.version`，因此只要新构建成功，关于页也会显示 `0.9.4`。

## Windows 正式版交付物

本次正式版目录为：

- `build/windows/x64/runner/Release`

运行入口为：

- `build/windows/x64/runner/Release/NAI_CasRand.exe`

但 exe 不能脱离目录单独使用，必须保留整个 `Release` 目录，包括：

- `data/`
- `flutter_windows.dll`
- 同目录下的插件 dll

## 测试与验证策略

本次主要是构建与版本验证，不新增业务逻辑测试。

重点验证：

1. `pubspec.yaml` 版本已变为 `0.9.4`
2. `flutter build windows --release` 成功
3. `build/windows/x64/runner/Release/NAI_CasRand.exe` 存在
4. exe 的 `FileVersion` / `ProductVersion` 为 `0.9.4`
5. 开屏欢迎弹窗显示 `0.9.4`
6. 关于页显示 `0.9.4`

## 非目标

本次不做：

- 不新增安装包制作流程
- 不改欢迎弹窗文案内容
- 不新增“正式版”标签
- 不处理自动更新逻辑

## 实现结论

对当前项目来说，最小且正确的正式版发布方式就是：

- 把版本号升级到 `0.9.4`
- 重建 Windows `Release`
- 验证开屏、关于页和 exe 文件属性都显示 `0.9.4`

这样交付出来的 `build/windows/x64/runner/Release` 才能被视为这次更新后的 Windows 正式版。
