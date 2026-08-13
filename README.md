# DevOrbit

DevOrbit 是一个面向 macOS 和 Windows 的轻量级开发工具轮盘。应用常驻系统托盘，通过全局快捷键在鼠标附近打开八槽轮盘，当前内置 JSON 格式化和文本翻译工具。

## 当前能力

- 全局快捷键、系统托盘、开机启动和单窗口模式切换
- 鼠标位置轮盘、八个固定槽位、数字键选择和屏幕边缘修正
- 工具箱主页、系统主题、快捷键与缩进设置
- 严格 JSON 校验、格式化、压缩、复制、打开、拖放和保存
- 文本级 JSON 转换，保留超大整数、重复键和原始数字写法
- DeepL API Free 文本翻译、语言自动检测、语言交换和快捷复制
- 翻译工具复用单一独立窗口，JSON 工具仍支持同时打开多个窗口
- DeepL API Key 通过 macOS Keychain 或 Windows 安全凭据存储保存
- 代码内 `ToolModule` 注册机制，便于继续增加开发工具

## 开发环境

- Flutter stable，Dart 3
- macOS 12+ 或 Windows 10/11
- macOS 构建需要完整 Xcode；Windows 构建需要 Visual Studio Desktop C++ 工具链
- macOS 版本按 DMG 直接分发，不启用 App Sandbox；开机启动通过当前用户的 `~/Library/LaunchAgents` 管理

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## 新增工具模块

1. 实现 `ToolModule`，提供 `ToolDescriptor`、页面和 `onLaunch`。
2. 为模块分配唯一 ID 与 `0-7` 之间的轮盘槽位。
3. 在 `main.dart` 创建模块并加入 `ToolRegistry`。

注册表会拒绝重复 ID、重复槽位和越界槽位。未注册的轮盘位置自动显示为禁用占位。

## 打包

Fastforge 配置位于 `distribute_options.yaml`：

```bash
dart pub global activate fastforge 0.6.12
fastforge release --name macos
fastforge release --name windows
```

`dmg` 打包还需要 Node.js 与 `appdmg`，`exe` 打包需要 Inno Setup 6。平台专属配置分别位于 `macos/packaging/dmg/make_config.yaml` 和 `windows/packaging/exe/make_config.yaml`。

GitHub Actions 会在版本标签或手动触发时分别生成未签名的 macOS DMG、Windows EXE 和 SHA-256 校验文件。
