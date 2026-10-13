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
