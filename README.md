# 钞机汇玩 · 内容展示小程序

一个可直接运行的原生微信小程序：首页提供文件命名器、每日计划、照片整理清单，并保留图文技巧和视频技巧两个独立栏目。工具数据只保存在用户本机，无需登录。

## 目录结构

```
miniprogram/
├── app.js / app.json / app.wxss   # 入口、全局配置、全局样式
├── sitemap.json                    # 搜索索引
├── data/
│   └── content.js                  # 内容数据（分类 + 条目，改这里就能换内容）
└── pages/
    ├── index/                      # 首页：工具入口 + 使用指南
    ├── tools/                      # 文件命名、每日计划、照片清单
    ├── list/                       # 列表页：图文卡片
    └── detail/                     # 详情页：封面 + 正文
```

## 运行步骤

1. 打开 [微信开发者工具](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html)
2. 新建项目 → 目录选 `F:\微信小程序\miniprogram` → AppID 填你的（没有就选「测试号」）→ 框架选「不使用」
3. 编译即可预览；点击首页卡片 → 列表 → 任意条目，体验完整流程

## 换成你自己的内容

只改一个文件：`data/content.js`

```js
{
  id: 'poems',            // 分类唯一 id
  name: '古诗词',          // 分类名（显示在首页）
  icon: '诗',              // 首页卡片上的字
  color: '#e8f3ec',        // 分类主题色
  items: [
    {
      id: 'p1',            // 条目唯一 id
      title: '静夜思',      // 标题
      subtitle: '唐 · 李白', // 副标题
      cover: 'https://...',  // 封面图（当前用 picsum 占位图，换成你自己的 URL 即可）
      tag: '五言绝句',        // 标签
      summary: '...',        // 列表页一句话摘要
      content: '...'         // 详情页正文（支持 \n 换行）
    }
  ]
}
```

- 图片建议先传到图床/OSS 后用 https 链接（小程序要求图片必须是 https）
- 发布前把 `app.json` 里的 `navigationBarTitleText` 改成你的小程序名

## 发布

开发者工具「上传」→ [小程序后台](https://mp.weixin.qq.com/)「版本管理」提交审核 → 通过后发布。

## 视频教程

- 带 `video` 字段的条目：列表页封面会显示 ▶ 播放角标 + 时长，详情页顶部内嵌 `<video>` 播放器
- 项目内置一条经过压缩的手机安全演示视频，用于验证播放器功能
- 上传较大的真实教程视频：把视频传到 OSS 或视频平台取得 https 链接，替换条目里的 `video.src` 和 `video.poster`（封面海报图）即可
- 建议格式：MP4（H.264）；很小的演示视频可放在代码包中，大视频使用 https 地址
- 预览或发布前，需在小程序后台将图片和视频所在域名加入对应的合法域名配置

## 后续可扩展

- 收藏功能：`wx.setStorageSync` 本地保存
- 搜索：列表页加 `<input>` 过滤
- 后台数据：接云开发（云数据库存内容，首页 `wx.cloud.callFunction` 拉取），改内容不用重新发版
- 下拉刷新 + 上拉加载：`onPullDownRefresh` / `onReachBottom`

## 系统核心架构与运维文档

- **运维与全量修复总结**：请参阅 [`PROJECT_MAINTENANCE_SUMMARY.md`](./PROJECT_MAINTENANCE_SUMMARY.md)
- **换机迁移与服务器部署手册**：请参阅 [`DEPLOYMENT_GUIDE.md`](./DEPLOYMENT_GUIDE.md)
- **AI 协作规范与工作区纪律**：请参阅 [`AGENTS.md`](./AGENTS.md)
