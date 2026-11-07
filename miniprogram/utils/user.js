const API_BASE = 'https://sy.sd0739.top'

function generateUUID() {
  const chars = '0123456789abcdef'
  let id = 'u_'
  for (let i = 0; i < 8; i++) {
    id += chars[Math.floor(Math.random() * chars.length)]
  }
  return id
}

function getUserId() {
  let uid = wx.getStorageSync('vhelper_user_id')
  if (!uid) {
    uid = generateUUID()
    wx.setStorageSync('vhelper_user_id', uid)
  }
  return uid
}

function fetchUserInfo() {
  const uid = getUserId()
  return new Promise((resolve) => {
    wx.request({
      url: `${API_BASE}/api/user/info`,
      method: 'POST',
      data: { user_id: uid },
      header: { 'content-type': 'application/json' },
      timeout: 10000,
      success: (res) => {
        if (res.statusCode === 200 && res.data && res.data.code === 0) {
          const info = res.data.data
          wx.setStorageSync('vhelper_user_info', info)
          resolve(info)
        } else {
          resolve(wx.getStorageSync('vhelper_user_info') || {
            user_id: uid,
            total_quota: 10,
            daily_quota: 10,
            bonus_quota: 0,
            is_vip: false
          })
        }
      },
      fail: () => {
        resolve(wx.getStorageSync('vhelper_user_info') || {
          user_id: uid,
          total_quota: 10,
          daily_quota: 10,
          bonus_quota: 0,
          is_vip: false
        })
      }
    })
  })
}

function redeemCard(cardKey) {
  const uid = getUserId()
  return new Promise((resolve) => {
    wx.request({
      url: `${API_BASE}/api/user/redeem`,
      method: 'POST',
      data: { user_id: uid, card_key: cardKey },
      header: { 'content-type': 'application/json' },
      timeout: 15000,
      success: (res) => {
        if (res.statusCode === 200 && res.data) {
          resolve(res.data)
        } else {
          resolve({ code: 1, message: '网络请求异常，请稍后重试' })
        }
      },
      fail: () => {
        resolve({ code: 1, message: '连接服务器失败，请检查网络' })
      }
    })
  })
}

// 历史记录存储
const HISTORY_KEY = 'vhelper_parse_history'

function getHistory() {
  return wx.getStorageSync(HISTORY_KEY) || []
}

function addHistory(record) {
  const list = getHistory()
  // 去重 (相同 url 移至最前)
  const filtered = list.filter(item => item.videoUrl !== record.videoUrl)
  const item = {
    id: Date.now().toString(),
    title: record.title || '提取的媒体',
    coverUrl: record.coverUrl || '',
    videoUrl: record.videoUrl || '',
    images: record.images || [],
    platform: record.platform || '短视频',
    type: record.type || 'video',
    createdAt: new Date().toLocaleString()
  }
  filtered.unshift(item)
  // 最多保存 50 条
  wx.setStorageSync(HISTORY_KEY, filtered.slice(0, 50))
}

function clearHistory() {
  wx.removeStorageSync(HISTORY_KEY)
}

module.exports = {
  API_BASE,
  getUserId,
  fetchUserInfo,
  redeemCard,
  getHistory,
  addHistory,
  clearHistory
}
