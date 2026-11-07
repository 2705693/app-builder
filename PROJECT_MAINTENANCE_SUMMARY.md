# 钞机汇玩系统全量架构与运维开发总结文档

> **系统名称**：钞机汇玩（智能无水印多媒体提取与会员管理系统）  
> **管理后台**：https://sy.sd0739.top/admin  
> **管理员密码**：`Aa123450.`  
> **服务器 IP**：`107.172.229.216`  
> **核心代码**：云端 `/root/main.py` | 本地 `server/main.py` | 前端 `miniprogram/`

---

## 一、 系统支持平台矩阵（全平台实测已修复打通）

| 平台分类 | 支持平台及代表域名 | 提取方式与特点 |
| :--- | :--- | :--- |
| **短视频巨头** | 抖音、快手、小红书、B站 | 官方移动接口/原生逆向、免登录无水印提取、支持图集与高清原画 |
| **微信视频号** | `weixin.qq.com/sph/*`、`channels.weixin.qq.com` | FastAPI 调用本机 Go 服务；腾讯元宝会话解析；支持封面、标题、作者、H264 视频及 Range 流式保存 |
| **字节创作与AI生态** | 剪映 (`ulikecam.com`)、即梦 (`jimeng.jianying.com`) | 原生模板逆向提取真 1080P/720P 纯净 MP4 视频直链及封面海报 |
| **头条资讯与媒体** | 今日头条 (`m.toutiao.com`) | 原生 `playAuthTokenV2` 字节云 VOD 接口解密提取高清 MP4 |
| **大模型与AI视频** | 豆包 AI 视频 (`doubao.com`) | 豆包自研媒体分发接口提取完整生成视频直链 |
| **短剧与漫剧生态** | 红果短剧 (`novelquickapp.com`)、番茄短剧 (`changdunovel.com`) | 字节跳动底层媒体接口逆向，提取完整全集高清晰度 MP4 视频 |
| **国际主流平台** | TikTok、X (推特)、YouTube | 多重防风控、Deno 运行时解密、Invidious 备用流合并、高清中转 |

---

## 二、 服务器全量更新与升级一键指令

### 1. 更新前必须备份

当前 `/root/main.py` 包含视频号专用接入代码。下方历史更新命令会整体覆盖该文件，只有确认远端版本也包含 `parse_wechat_channels` 和 `/api/wechat_proxy` 时才能使用。

```bash
cp -a /root/main.py /root/main.py.backup-$(date +%Y%m%d-%H%M%S)
python3 -m py_compile /root/main.py
```

> 不再建议直接运行旧的 `curl ... -o /root/main.py` 覆盖命令，否则会丢失视频号接入、用户额度和其他后续修复。

### 2. 验证运行状态
```bash
systemctl status videoparser --no-pager
```

### 3. 查看实时解析日志
```bash
journalctl -u videoparser -f -n 50
```

---

## 三、视频号服务维护摘要（2026-11-07）

### 架构

```text
小程序 → sy.sd0739.top → main.py:8000 → wx-video-channel-download:2022
```

- 服务目录：`/opt/wx-video-channel-download`
- 服务名称：`wx-video-channel.service`
- 服务地址：`127.0.0.1:2022`，无需 Nginx 反代、域名或公网端口
- 登录配置：`config.yaml` 的 `sph_cookie`，需包含 `hy_user`、`hy_token`
- FastAPI 接入：`parse_wechat_channels()`、`/api/wechat_proxy`
- CDN 修复：保留完整媒体 URL 参数，并携带微信 UA、Referer、Origin、Range

### 日常检查

```bash
curl -sS http://127.0.0.1:2022/api/status
systemctl status wx-video-channel.service --no-pager -l
journalctl -u wx-video-channel.service -n 50 --no-pager
```

Cookie 过期时重新登录腾讯元宝，复制完整 Cookie，更新配置后执行：

```bash
chown wxsph:wxsph /opt/wx-video-channel-download/config.yaml
chmod 600 /opt/wx-video-channel-download/config.yaml
systemctl restart wx-video-channel.service
```

### 已完成验收

- 视频号分享链接解析：成功；
- 标题、作者、封面、H264 地址：成功；
- 2022 媒体代理：HTTP 206、`video/mp4`、Range 正常；
- 8000 统一解析接口：返回平台“视频号”和 `/api/wechat_proxy` 本站地址；
- 小程序继续使用原域名和 `/api/parse`，无需增加合法域名。

完整部署、源码修复和故障排查见 `DEPLOYMENT_GUIDE.md` 的“视频号解析服务”章节。

---

## 四、图片局部修复（2026-11-07）

- 页面：`miniprogram/pages/image-repair/`
- 入口：首页工具卡、提取页按钮、图集内每张图片的“局部修复”按钮
- 操作：矩形框选、画笔涂抹、撤销、清空、预览、保存相册
- 后端：`POST /api/image/inpaint`、`GET /api/image/result`
- 引擎：OpenCV Telea，不依赖付费 AI 服务
- 临时目录：`/root/image_repairs`，结果保留约 24 小时
- 限制：JPG/PNG/WebP，单张不超过 15MB，最大约 3600 万像素
- VPS 依赖：`python-multipart`、`opencv-python-headless`、`numpy`
- 微信域名：同一域名需配置 `request`、`uploadFile`、`downloadFile`

---

## 五、意见反馈（2026-11-07）

- 前端：“我的”页面自定义反馈弹窗，最多 1000 字，可选填邮箱或微信号；
- 后端：`POST /api/feedback`；
- 存储：SQLite `feedback` 表，通知失败也不会丢失；
- 管理：`/api/admin/data` 返回最近 200 条反馈；
- 邮件通知：通过 `FEEDBACK_SMTP_*` 环境变量配置；
- 微信通知：仅支持企业微信群机器人 `FEEDBACK_WECOM_WEBHOOK`，不支持直接推送到个人微信。

---

## 六、全量修复与 VPS 部署命令（2026-11-07 最新）

包含：
- **B站番剧 (Bangumi)**：修复 `Expecting value` 与 `无法提取BV/av`，完整提取 `ep` 剧集无水印直链；
- **小红书**：修复 `xhslink.cn` 新域名及新版 SSR `mediaV2` / `media` 视频提取；
- **TikTok**：新增 `tikwm` 极速免风控解析通道；
- **微信视频号**：保留原生视频号解析与 `/api/wechat_proxy` 流式代理；
- **YouTube**：Deno 解密与 yt-dlp 支持；
- **“我的”页面**：更新为绿色卡片现代设计，每日免费额度为 10 次，联系邮箱为 `sd0739@sd0739.top`；
- **下载 567 防护拦截修复**：代理流增加 Range 透传与兜底，彻底解决腾讯云 EdgeOne / CDN 防盗链拦截；
- **小程序实时下载进度与停止下载**：移除全屏死锁遮罩，提供百分比/MB进度弹窗与秒级【停止下载】能力。

### VPS 更新说明

旧的 `curl ... -o /root/main.py` 整体覆盖命令已停用。该命令会丢失视频号接入、操作审计和数据保留模块入口。现在更新前必须备份并对照本地最新版逐项合并：

```bash
cp -a /root/main.py /root/main.py.backup-$(date +%Y%m%d-%H%M%S)
python3 -m py_compile /root/main.py /root/retention_feature.py
systemctl restart videoparser.service
systemctl status videoparser.service --no-pager -l
```

---

## 七、流式代理与下载 567 报错修复（2026-11-07）

- **故障现象**：小程序端在保存部分 B站或外部视频时，提示 `下载文件失败(状态码567)，请检查网络或直链`，且网页提示 `请求已被站点的安全策略拦截。本站点已启用安全防护服务以抵御在线攻击`（腾讯云 EdgeOne WAF 策略拦截）。
- **根因分析**：B站 CDN（如 `upos-sz-mirrorcosov.bilivideo.com`）部署了腾讯云 EdgeOne 边缘安全防护。当爬虫/流媒体代理请求未携带 `Range` 分段下载请求头时，会被 EdgeOne 判定为全量抓取爬虫并直接阻断（返回 HTTP 567）。
- **解决方案**：
  - 在 `/root/main.py` 的 `/api/proxy` 流式代理接口中，透传客户端请求的 `Range` 头部；
  - 若客户端未携带 `Range`，则服务端主动注入 `headers["Range"] = "bytes=0-"` 进行兜底；
  - 针对分片请求返回 HTTP 206，全量下载或直连接口兼容返回 HTTP 200/206，完美绕过 CDN 防盗链风控，全网视频恢复极速流畅下载。

---

## 八、小程序下载控制与「停止下载」功能（2026-11-07）

- **痛点解决**：
  - **移除死锁遮罩**：原代码使用微信系统 `wx.showLoading({ mask: true })` 黑色全屏遮罩，导致用户在下载几十到上百兆的长视频（如 69 分钟的高清视频）时，屏幕被完全锁死无法取消或退出，只能强杀微信。现已彻底移除强阻塞遮罩。
- **新增功能特性**：
  - **实时进度弹窗**：触发下载时浮现沉浸式卡片，展示动态绿色进度条、百分比（如 `45%`）及下载大小（如 `35.2MB / 88.0MB`）。
  - **【停止下载】秒级中断**：利用微信底层 `wx.downloadFile` 返回的 `DownloadTask` 对象，点击【停止下载】按钮时立即调用 `downloadTask.abort()`，瞬间切断连接并释放手机缓存，界面轻提示*“已停止下载”*，恢复自由操作。
  - **双重停止入口**：除弹窗中央醒目的红色停止按钮外，底部主按钮同步变为 `正在下载 xx% · 点击停止`，随时可点击中止。
  - **页面退出自动防漏**：在 `onUnload` 页面销毁生命周期中自动执行 `abort()`，杜绝用户返回上一页后后台偷偷耗费流量和占用手机内存。
  - **长视频后台下载指引**：由于微信小程序底层不支持断点续传（仅支持 abort 取消），弹窗内置温馨提示引导用户长视频可点击停止后，使用「复制下载链接」到手机浏览器（Safari / Chrome）中进行后台下载与断点续传。

---

## 九、版权限制与错误提示优化（2026-11-07）

- **背景**：B站等平台对于特定番剧/电影（如 2 小时 23 分钟的电影《八仙！》等）具有严格的大陆地区版权保护（`geo restriction`）或大会员专享限制，境外海外云服务器请求时会被官方版权风控阻断。
- **优化**：
  - 后端在遇到版权限制异常时，自动过滤底层 Python 3.10 废弃告警等杂乱技术日志；
  - 转化为清晰友好的中文弹窗说明：`“该内容为 B站 地区版权保护或大会员专享影视（仅限中国大陆地区播放），境外云端服务器受官方版权限制无法提取，请提取常规视频”`，避免用户产生系统故障误解。

---

## 十、审计日志与隐私数据保留（2026-11-07）

### 操作审计

- 表：SQLite `audit_logs`；
- 后台：“操作日志”页面，最近 500 条，可按用户 ID、动作和详情搜索；
- 范围：新用户、提取成功/失败、卡密兑换、管理员调整次数、不限次状态、禁用/解禁和重置；
- 禁止写入完整卡密、Cookie、密码、SMTP 授权码等敏感数据。

### 自动清理

- VPS 模块：`/root/retention_feature.py`；
- 主程序入口：`/root/main.py` 末尾的 `install_retention_feature(...)`；
- 服务启动时立即执行，随后每 6 小时执行；
- 临时视频和图片文件最多保留 24 小时；
- `parse_logs`、`audit_logs`、`feedback` 数据库记录最多保留 30 天；
- 用户、额度、卡密和权益状态不删除；
- 反馈邮件/企业微信通知副本不由数据库清理任务删除。

### 本地历史与服务器日志

- 小程序“清空历史记录”只清除手机本地历史；
- 普通用户不能通过小程序删除服务器日志；
- 服务器日志统一保留最多 30 天后自动清理；
- 清空本地历史不影响专属 ID、每日免费 10 次、额外次数或其他权益。

验收命令：

```bash
journalctl -u videoparser.service -n 80 --no-pager \
  | grep -E '\[cleanup\]|Application startup'
```

验收标准：启动日志出现 `[cleanup] removed files=..., records=...`，且公开路由中不存在用户删除服务器日志接口。

### 小程序用户界面与审核表述

- 默认每日免费额度为 10 次，额外次数单独展示；
- 用户界面已去除“VIP、会员、充值、去水印、无水印”等表述；
- “开始解析”改为“开始提取”，“解析额度说明”改为“使用额度说明”；
- 使用教程已补充图片局部修复的矩形框选、画笔擦除、预览和保存步骤；
- 隐私说明明确：临时文件最多 24 小时、服务器提取与操作日志最多 30 天；“清空历史记录”仅删除手机本地历史。

