# 一贴取影 Android APP

这是“一贴取影”的 Android 客户端源码仓库，使用 Flutter 开发。

## 目录

- `android_app/`：Flutter 应用源码
- `.github/workflows/build_apk.yml`：GitHub Actions APK 构建流程

## 自动构建 APK

推送到 `main` 分支后，GitHub Actions 会自动构建 Release APK。

1. 打开仓库的 **Actions** 页面。
2. 进入最新的 **Build Android APK** 成功任务。
3. 在 **Artifacts** 下载 `yitie-quying-release-apk`。
4. 解压后得到 `app-release.apk`。

## 隐私与安全

- 不要提交密码、Cookie、Token、SMTP 授权码、私钥或服务器配置。
- 运行时服务地址位于 `android_app/lib/services/api_service.dart`。
- 本仓库仅保留 Android APP 构建所需文件。

## 维护文档

完整的功能、隐私、安全与发布记录见 [`android_app/MAINTENANCE_SUMMARY.md`](android_app/MAINTENANCE_SUMMARY.md)。
