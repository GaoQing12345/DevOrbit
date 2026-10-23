# DevOrbit

DevOrbit 是一个面向 macOS 的轻量级开发工具轮盘。应用常驻系统托盘，通过全局快捷键在鼠标附近打开八槽轮盘，当前内置 JSON 格式化、文本翻译、文本对比、时间戳转换和 SQL 日志转换工具。

## 当前能力

- 全局快捷键、系统托盘、开机启动和单窗口模式切换
- 鼠标位置轮盘、八个固定槽位、数字键选择和屏幕边缘修正
- 工具箱主页、系统主题、快捷键与缩进设置
- 严格 JSON 校验、格式化、压缩、复制、打开、拖放和保存
- 文本级 JSON 转换，保留超大整数、重复键和原始数字写法
- DeepL API Free 文本翻译、语言自动检测、语言交换和快捷复制
- 文本对比、时间戳转换和 SQL 日志转换
- 翻译、对比、时间戳和 SQL 日志工具复用单一独立窗口，JSON 工具支持同时打开多个窗口
- DeepL API Key 通过 macOS Keychain 保存
- 代码内 `ToolModule` 注册机制，便于继续增加开发工具

## 开发环境

- Flutter stable，Dart 3
- macOS 12+，构建需要完整 Xcode
- 按 DMG 直接分发，不启用 App Sandbox；开机启动通过当前用户的 `~/Library/LaunchAgents` 管理

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
```

`dmg` 打包还需要 Node.js 与 `appdmg`，配置位于 `macos/packaging/dmg/make_config.yaml`。

打包流程通过 `hooks` 自动签名与公证，所需环境变量为空时两步都会跳过，本机打包仍然产出未签名的 DMG：

| 变量 | 用途 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书（`.p12` 的 base64 单行文本） |
| `MACOS_CERTIFICATE_PASSWORD` | 上述 `.p12` 的密码 |
| `MACOS_SIGN_IDENTITY` | 签名身份，默认 `Developer ID Application` |
| `MACOS_NOTARY_APPLE_ID` / `MACOS_NOTARY_PASSWORD` / `MACOS_NOTARY_TEAM_ID` | `notarytool` 公证凭据（App 专用密码） |

GitHub Actions 会在版本标签或手动触发时生成 macOS DMG 和 SHA-256 校验文件。配置了签名证书时，DMG 会在打包后自动公证并 staple，未配置时输出未签名产物。
