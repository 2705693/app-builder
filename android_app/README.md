# 一贴取影 - 安卓 APP (Flutter 版)

本项目是微信小程序「一贴取影」配套的 Android 应用。

---

## 🌟 包含功能清单

1. **全平台无水印提取**：
   - 支持平台：抖音、快手、小红书（单视频/多图集）、B站、微信视频号、TikTok、X (推特)、YouTube、剪映/即梦、今日头条、豆包、红果/番茄；
   - 支持一键读取系统剪贴板、智能过滤多余文本；
   - 原生播放器内嵌预览播放，支持全屏、控制条与比例自适应；
   - 图集横向瀑布流滚动、全屏大图预览、一键从图集带入局部修复；
   - 复制高清无水印直链地址。

2. **原生极速下载与相册存入**：
   - 突破微信小程序限制，支持**真机实时下载进度条、MB 大小展示、秒级【停止下载】**；
   - 支持将 MP4 视频与 JPG/PNG 图集一键存入系统相册（DCIM/Photos 目录），自动刷新图库；
   - 自动适配 Android 13+ 细粒度媒体权限与旧版存储权限。

3. **图片局部修复画板**：
   - 原生画布手指涂抹、画笔粗细调节、撤销、清空；
   - 生成纯黑底白线 Mask 遮罩，对接云端 OpenCV Telea 修复引擎；
   - 修复结果实时对比与一键保存到手机相册。

4. **历史记录与用户中心**：
   - 本地持久化保存提取历史，随时再次查看与复制；
   - 每日免费 10 次额度管理；
   - 支持授权卡密兑换次数或不限次服务；
   - 提供隐私与使用说明，并可清空手机本地历史记录；
   - 原生意见反馈弹窗（直接对接服务器 SQLite 与邮件/企业微信通知）；
   - 使用教程与已支持平台列表。

---

## 🚀 方式一：免本地环境，一键云端自动打包生成 APK（最推荐）

您**完全不需要在本地电脑安装几 GB 的 Android Studio 和 Flutter 环境**，我们已经配置好了 GitHub Actions 自动化流水线：

1. **创建 GitHub 仓库并推送代码**：
   - 在您的 GitHub 上新建一个私有或公开仓库（例如 `chaoji-huiwan`）；
   - 将当前工作区代码推送（push）到该仓库的 `main` 分支。
2. **云端全自动编译**：
   - 代码推送后，点击 GitHub 仓库顶部的 **Actions** 标签页；
   - GitHub 的微软云端服务器会自动启动，安装 Flutter 3.24、JDK 17 与 Android 构建工具，在 2~3 分钟内自动编译生成 `app-release.apk`。
3. **下载并安装**：
   - 构建完成后，在页面下方的 **Artifacts** 处点击下载 `chaoji-huiwan-release-apk`；
   - 解压后把里面的 `app-release.apk` 发送到安卓手机（通过微信传输或数据线），直接点击即可在手机上安装使用！

---

## 🛠️ 方式二：本地电脑编译运行（适合未来安装了环境后）

1. 下载并安装 [Flutter SDK (3.24+)](https://flutter.dev/docs/get-started/install/windows)；
2. 安装 [Android Studio](https://developer.android.com/studio) 并配置好 Android SDK；
3. 打开命令行进入 `android_app` 目录：
   ```bash
   cd android_app
   flutter pub get
   flutter run
   ```
4. 打包 Release APK：
   ```bash
   flutter build apk --release
   ```
   生成的 APK 文件位于：`build/app/outputs/flutter-apk/app-release.apk`。
