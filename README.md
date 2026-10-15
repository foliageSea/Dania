# Dania

基于 Flutter、Forui、Riverpod 的 Android 设备工具箱，当前版本暂不包含 USB OTG。

## 已实现

- Shizuku 运行状态、授权和本机 Shell 操作
- 无线 ADB 配对、TLS/TCP 连接和连接管理
- ADB 密钥使用 Android Keystore 加密保存
- 远端终端：实时输出、停止、历史和快捷命令
- 应用管理：搜索、详情、启停用、权限授予/撤销、卸载和 APK 安装
- 文件管理：目录浏览、上传、下载、另存为、新建目录、重命名和删除
- scrcpy 5.0.1：H.264 投屏、触控、返回/主页/最近任务/音量按键
- 中英文、主题、日志和运行环境页面
- MiSans 全局字体、按设备像素比适配的字号档位，以及字体与第三方开源声明

## 开发环境

- Flutter 3.47.6
- Android SDK 36
- Java 17
- Android 8.0 及以上

所有 Flutter 命令使用项目 FVM SDK：

```sh
fvm flutter pub get
fvm flutter run
```

构建 APK：

```sh
fvm flutter build apk --debug
```

检查：

```sh
fvm dart format lib test
fvm flutter test
fvm flutter analyze --no-fatal-infos
./android/gradlew -p android :app:testDebugUnitTest
```

## 使用前准备

1. 在 Android 设备上安装并启动 Shizuku。
2. 为 Dania 授予 Shizuku 权限。
3. 远端设备可通过 Android 无线调试配对后连接；连接和配对端口需要在同一局域网可达。
4. 投屏使用内置 scrcpy server，不需要在远端设备安装额外应用。

ADB shell 权限不等于 root，部分系统路径和应用私有数据仍不可访问。scrcpy 协议客户端和 server 固定为 5.0.1，升级时需要同步协议实现和内置 server。

## 模板同步

公共 UI 已同步至 `forui_app` 模板的 `6183168`，保留 Dania 的 Android-only 工程与业务功能，不引入模板的桌面窗口和示例页面。

应用使用 MiSans 字体（`assets/MiSans-Regular.ttf`），遵循《MiSans 字体知识产权许可协议》。设置页“关于”提供字体声明、协议链接和第三方开源许可入口。

字号档位保留“小 / 标准 / 大”的偏好值，再按设备像素比计算实际缩放，并与系统字体缩放叠加：

| 设备像素比 | 小 | 标准 | 大 |
| --- | --- | --- | --- |
| ≤ 1.5 | 65% | 80% | 100% |
| > 1.5 且 < 2.5 | 85% | 100% | 120% |
| ≥ 2.5 | 57% | 72% | 92% |

设置页各标签独立滚动；实时日志适配紧凑屏幕，窄屏支持长按复制单条日志。视图隐藏堆栈帧，搜索、复制和导出仍保留完整日志。
