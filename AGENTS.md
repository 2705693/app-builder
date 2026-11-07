# 钞机汇玩小程序（F:\微信小程序）

- 原生微信小程序，页面在 miniprogram/pages/（index 首页、list 列表、detail 详情），数据源是 miniprogram/data/content.js。
- 改内容只改 content.js；图片须用 https 链接（建议先传图床/OSS）。
- 发布流程：微信开发者工具「上传」→ mp.weixin.qq.com 版本管理提交审核。

## 上下文纪律（防超限）
- 本线程模型上下文约 65k tokens，请保持精简：
  - 不要一次性整读长文件，用 Select-String / 分段读取（每次 ≤200 行）。
  - 运行命令时截断冗长输出（如 | Select-Object -First 30）。
  - 工作区根目录的 screenshot*.png 是大图，除非任务需要，不要读取或引用。
  - 长任务分阶段推进，每阶段结束用几句话小结，避免重复输出已给过的代码。
