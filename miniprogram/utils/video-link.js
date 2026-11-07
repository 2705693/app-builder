const PLATFORM_HOSTS = [
  { name: '抖音', hosts: ['douyin.com', 'iesdouyin.com'] },
  { name: '小红书', hosts: ['xiaohongshu.com', 'xhslink.com'] },
  { name: '快手', hosts: ['kuaishou.com', 'gifshow.com'] },
  { name: 'B 站', hosts: ['bilibili.com', 'b23.tv'] },
  { name: '视频号', hosts: ['weixin.qq.com', 'channels.weixin.qq.com'] }
]

function hostMatches(host, allowed) {
  return host === allowed || host.endsWith(`.${allowed}`)
}

function getHost(url) {
  const match = /^https:\/\/([^/?#:]+)/i.exec(url)
  return match ? match[1].toLowerCase() : ''
}

function parseVideoText(text) {
  const source = typeof text === 'string' ? text.trim() : ''
  if (!source) return { kind: 'empty', message: '请先粘贴视频链接或分享文案' }

  const urls = source.match(/https:\/\/[^\s<>"'，。；;）)\]]+/gi) || []
  if (!urls.length) return { kind: 'invalid', message: '没有找到 HTTPS 链接' }

  const candidates = urls.map(url => url.replace(/[,.!?，。！？]+$/, ''))
  const direct = candidates.find(url => /\.mp4$/i.test(url.split(/[?#]/)[0]))
  if (direct) {
    return {
      kind: 'direct',
      url: direct,
      message: '已识别 MP4 文件直链，可预览并尝试保存'
    }
  }

  const url = candidates[0]
  const host = getHost(url)
  if (!host || host.includes('@')) return { kind: 'invalid', message: '链接格式不正确' }
  const platform = PLATFORM_HOSTS.find(item => item.hosts.some(allowed => hostMatches(host, allowed)))
  if (platform) {
    return {
      kind: 'platform',
      platform: platform.name,
      url,
      message: `${platform.name}分享页不是视频文件地址；需平台授权的接口，当前不能直接保存`
    }
  }

  return {
    kind: 'web',
    url,
    message: '这是网页地址，不是 MP4 文件直链；请提供已授权的视频文件地址'
  }
}

module.exports = { parseVideoText }
