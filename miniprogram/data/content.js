const tools = [
  { id: 'filename', icon: '名', name: '文件命名器', desc: '快速生成统一文件名', color: '#e8f3ec' },
  { id: 'plan', icon: '计', name: '每日计划', desc: '记录今天的重要任务', color: '#e8f1fb' },
  { id: 'photo', icon: '照', name: '照片整理清单', desc: '按步骤整理手机相册', color: '#fff4df' },
  { id: 'repair', icon: '修', name: '图片局部修复', desc: '框选或涂抹需要修复的区域', color: '#f0ecfb', path: '/pages/image-repair/image-repair' },
  { id: 'video', icon: '播', name: '视频链接助手', desc: '识别并保存授权视频直链', color: '#eaf6ef', path: '/pages/video-helper/video-helper' }
]

const categories = [
  {
    id: 'articles',
    name: '图文技巧',
    icon: '学',
    color: '#e8f3ec',
    items: [
      {
        id: 'a1',
        title: '手机照片整理的 5 个步骤',
        subtitle: '手机 · 整理技巧',
        cover: 'https://picsum.photos/seed/photo-organize/600/400',
        tag: '手机技巧',
        summary: '定期整理照片，让相册更清爽、更容易查找。',
        content: '照片越来越多时，可以按照下面的步骤整理：\n\n1. 删除模糊、重复和无用的照片。\n2. 按旅行、家人、工作等主题创建相册。\n3. 给重要照片添加收藏标记。\n4. 将需要长期保存的照片备份到电脑或可靠的存储设备。\n5. 每月固定整理一次，避免照片越积越多。\n\n删除照片前，请先确认重要内容已经备份。'
      },
      {
        id: 'a2',
        title: '文件命名的实用方法',
        subtitle: '效率 · 整理技巧',
        cover: 'https://picsum.photos/seed/file-organize/600/400',
        tag: '效率提升',
        summary: '用统一的名称管理文件，查找资料更省时间。',
        content: '清晰的文件名可以帮助你快速找到资料。\n\n1. 使用“日期 + 主题 + 版本”的格式。\n2. 日期建议写成四位年份、两位月份和两位日期。\n3. 不使用“最新”“最终版”等容易混淆的词。\n4. 同类文件放进同一个文件夹。\n5. 修改后的版本依次标记为 V1、V2、V3。\n\n示例：20261020_旅行计划_V2。'
      },
      {
        id: 'a3',
        title: '三步做好每日计划',
        subtitle: '生活 · 时间管理',
        cover: 'https://picsum.photos/seed/daily-plan/600/400',
        tag: '时间管理',
        summary: '每天花几分钟安排任务，让工作和生活更有条理。',
        content: '简单的每日计划不需要列很多任务。\n\n1. 写下今天必须完成的一件事。\n2. 再选择两件有时间就完成的事情。\n3. 晚上回顾完成情况，并把未完成的任务重新安排。\n\n给每项任务预留合理时间，中间安排短暂休息，更容易坚持。'
      }
    ]
  },
  {
    id: 'media',
    name: '视频技巧',
    icon: '播',
    color: '#e8f1fb',
    items: [
      {
        id: 'v1',
        title: '手机安全小课堂',
        subtitle: '15 秒 · 实用视频',
        cover: 'https://picsum.photos/seed/mobile-safety-class/600/400',
        tag: '视频示例',
        summary: '保护隐私、核实来源、谨慎分享，让科技使用更安心。',
        // 视频内容模板：后续只需替换 src、poster 和 duration。
        // poster 必须使用 HTTPS 图片地址；src 可换成本地小视频或 HTTPS 视频地址。
        video: {
          src: '/assets/videos/mobile-safety-demo.mp4',
          poster: 'https://picsum.photos/seed/mobile-safety-class/600/400',
          duration: '00:15'
        },
        content: '这是一条图文视频内容模板。\n\n视频介绍三个安全使用原则：保护个人隐私、核实信息来源、谨慎分享内容。\n\n以后新增视频时，可以复制这条内容，只修改标题、封面、摘要、视频地址和正文。'
      }
    ]
  }
]

const legal = {
  copyrightNotice: '仅可处理本人享有著作权或已取得权利人授权的素材。未经许可，不得删除他人作品的水印、作者标识或权利管理信息，不得搬运、传播或商用侵权内容。',
  userAgreement: [
    '使用本服务前，您承诺对所处理的图片、视频享有著作权，或已经取得权利人的合法授权。',
    '不得利用本服务处理未获授权的第三方素材，不得擅自删除、遮盖他人作品上的水印、作者标识或权利管理信息，也不得传播、搬运或商用侵权内容。',
    '因用户处理无合法权属的素材而侵犯著作权、商标权、肖像权等权益的，相应责任由用户承担。',
    '本服务仅提供内容处理技术，不对素材权属进行实质审查。请仅处理本人或已获授权的内容。',
    '权利人投诉请发送权属证明、侵权位置等材料至 sd0739@sd0739.top。收到合格通知后，我们将依法核查并采取必要措施。'
  ],
  privacySummary: [
    '仅在您主动点击粘贴、选择素材或保存结果时调用剪贴板、相册等必要能力。',
    '服务使用微信登录标识记录额度，不要求手机号、头像、昵称、通讯录或地理位置。',
    '图片修复等云端任务会将您主动选择的素材加密传输至服务器临时处理；视频号链接会发送给腾讯元宝完成处理。素材临时文件最多保存24小时。',
    '我们不会将您的素材用于AI训练、对外展示或分发，法律法规另有要求或您另行授权的除外。',
    '您可以撤回系统权限或清空本地历史；相关问题请联系 sd0739@sd0739.top。'
  ]
}

module.exports = { categories, tools, legal }
