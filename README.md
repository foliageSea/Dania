# Dania

基于 Flutter、Forui、Riverpod 的 Android 设备工具箱，当前版本暂不包含 USB OTG。

## 已实现

- Shizuku 运行状态、授权和本机 Shell 操作
- 无线 ADB 配对、TLS/TCP 连接和连接管理
- ADB 密钥使用 Android Keystore 加密保存
- 交互式终端：ADB / Shizuku PTY、持久 Shell、ANSI、全屏程序、软键盘和辅助按键
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

## 交互式终端

在工具页打开终端并选择设备，会自动启动持久 Shell。连续执行命令时保留工作目录和环境变量，可使用 Tab 补全、方向键历史、Ctrl+C、Ctrl+D，以及 top 等终端程序。软键盘、旋转及可用空间变化会更新远端终端行列数。

底部辅助栏提供 Esc、Tab、方向键、一次性 Ctrl 修饰键和 Enter。Ctrl+C 中断前台任务；“断开”结束整个 Shell；“清空显示”只清除本地屏幕。可长按选择文字后复制选区，未选择时复制缓冲区。快捷命令面板与最多 30 条本次历史仅插入内容，按 Enter 才执行，不从原始按键流记录交互输入。

同一时间使用一个活动会话。切换设备或离开终端页会关闭旧会话，切到系统后台时保留；系统杀死应用后不恢复。自然退出、连接失败或设备断线后手动重新连接，不自动重放输入。启动超时为 30 秒，运行中没有固定超时。

输出保留最多 5000 行，按 UTF-8 增量解码；输入队列最多 256 KiB，每批最多 16 KiB。原生输出使用 8 个确认额度限制在途数据。终端输入输出不写入应用日志。

Shizuku 终端使用随应用打包的 JNI PTY 库，以 Shizuku 的 shell/root 身份运行系统 Shell；ADB 使用 Shell v2 PTY。PTY 不可用时会报告失败，不降级为普通命令管道。其他工具仍使用原有单次命令接口。

真机集成测试需要已运行并授权 Dania 的 Shizuku。测试 ADB 时还需该设备已信任 Dania 的 ADB 密钥，并传入其无线连接端点：

```sh
fvm flutter test integration_test/terminal_integration_test.dart -d <device-id> \
  --dart-define=TERMINAL_ADB_HOST=<host> --dart-define=TERMINAL_ADB_PORT=<port>
```

集成测试检查身份、目录保持、中文连续输入、ANSI、补全、历史、Ctrl+C、top、窗口尺寸、自然退出和重连。测试会安装测试入口应用；Flutter 工具在安装失败时会自动尝试卸载重装，因此应使用专用测试设备。完成后需重新安装正常入口的构建。

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
