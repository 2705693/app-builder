const userUtil = require('../../utils/user')

Page({
  data: {
    userInfo: {
      user_id: '',
      daily_quota: 10,
      bonus_quota: 0,
      total_quota: 10,
      is_vip: false,
      vip_expire_at: ''
    },
    cardKey: '',
    redeeming: false,
    showPrivacyModal: false,
    showTutorialModal: false,
    showPlatformsModal: false,
    showRedeemModal: false,
    showFeedbackModal: false,
    feedbackText: '',
    feedbackContact: '',
    feedbackSubmitting: false
  },

  onShow() {
    this.refreshUser()
  },

  async refreshUser() {
    try {
      const info = await userUtil.fetchUserInfo()
      if (info) {
        this.setData({ userInfo: info })
      }
    } catch (e) {
      console.error('Fetch user info error:', e)
    }
  },

  // 广告奖励提示
  onTapAdReward() {
    wx.showToast({
      title: '广告激励功能暂未开通，敬请期待',
      icon: 'none',
      duration: 2000
    })
  },

  // 弹窗控制
  openPrivacyModal() {
    this.setData({ showPrivacyModal: true })
  },

  closePrivacyModal() {
    this.setData({ showPrivacyModal: false })
  },

  openTutorialModal() {
    this.setData({ showTutorialModal: true })
  },

  closeTutorialModal() {
    this.setData({ showTutorialModal: false })
  },

  openPlatformsModal() {
    this.setData({ showPlatformsModal: true })
  },

  closePlatformsModal() {
    this.setData({ showPlatformsModal: false })
  },

  openFeedbackModal() {
    this.setData({ showFeedbackModal: true })
  },

  closeFeedbackModal() {
    if (this.data.feedbackSubmitting) return
    this.setData({ showFeedbackModal: false })
  },

  onFeedbackInput(e) {
    this.setData({ feedbackText: e.detail.value })
  },

  onFeedbackContactInput(e) {
    this.setData({ feedbackContact: e.detail.value })
  },

  submitFeedback() {
    const content = this.data.feedbackText.trim()
    if (this.data.feedbackSubmitting) return
    if (content.length < 2) {
      wx.showToast({ title: '请填写问题或建议', icon: 'none' })
      return
    }
    this.setData({ feedbackSubmitting: true })
    const system = wx.getSystemInfoSync()
    wx.request({
      url: 'https://sy.sd0739.top/api/feedback',
      method: 'POST',
      timeout: 30000,
      header: { 'content-type': 'application/json' },
      data: {
        user_id: userUtil.getUserId(),
        content,
        contact: this.data.feedbackContact.trim(),
        client_info: `${system.platform || ''} / ${system.system || ''} / 微信${system.version || ''}`
      },
      success: res => {
        this.setData({ feedbackSubmitting: false })
        if (res.statusCode === 200 && res.data && res.data.code === 0) {
          this.setData({ showFeedbackModal: false, feedbackText: '', feedbackContact: '' })
          wx.showModal({
            title: '提交成功',
            content: '感谢你的反馈，我们已经收到。',
            showCancel: false,
            confirmColor: '#127c44'
          })
        } else {
          const message = res.data && (res.data.detail || res.data.message)
          wx.showToast({ title: message || '提交失败，请稍后重试', icon: 'none' })
        }
      },
      fail: () => {
        this.setData({ feedbackSubmitting: false })
        wx.showToast({ title: '网络异常，请稍后重试', icon: 'none' })
      }
    })
  },

  openRedeemModal() {
    this.setData({ showRedeemModal: true })
  },

  closeRedeemModal() {
    this.setData({ showRedeemModal: false })
  },

  preventBubble() {
    // 阻止模态框点击冒泡关闭
  },

  // 复制隐私政策联系邮箱
  copyEmail() {
    wx.setClipboardData({
      data: 'sd0739@sd0739.top',
      success: () => {
        wx.showToast({ title: '邮箱已复制', icon: 'success' })
      }
    })
  },

  copyUserId() {
    const userId = this.data.userInfo.user_id
    if (!userId) return
    wx.setClipboardData({
      data: userId,
      success: () => wx.showToast({ title: '专属ID已复制', icon: 'success' })
    })
  },

  // 清空历史记录 (图1功能)
  onClearHistory() {
    wx.showModal({
      title: '清空历史记录',
      content: '确定要清空手机本地保存的全部历史记录吗？此操作无法撤销，不会影响服务器日志和剩余次数。',
      confirmColor: '#e02020',
      cancelColor: '#8f959e',
      confirmText: '确认清空',
      success: (res) => {
        if (res.confirm) {
          userUtil.clearHistory()
          wx.showToast({ title: '本地历史已清空', icon: 'success' })
        }
      }
    })
  },

  // 卡密输入与兑换
  onInputCardKey(e) {
    this.setData({ cardKey: e.detail.value.trim() })
  },

  async handleRedeem() {
    const { cardKey } = this.data
    if (!cardKey) {
      wx.showToast({ title: '请输入卡密兑换码', icon: 'none' })
      return
    }

    this.setData({ redeeming: true })
    const res = await userUtil.redeemCard(cardKey)
    this.setData({ redeeming: false })

    if (res.code === 0) {
      this.setData({ cardKey: '', showRedeemModal: false })
      wx.showModal({
        title: '兑换成功',
        content: res.message || '额度已即时到账！',
        showCancel: false,
        confirmColor: '#127c44',
        success: () => {
          this.refreshUser()
        }
      })
    } else {
      wx.showModal({
        title: '兑换失败',
        content: res.message || '卡密无效，请检查后重试',
        showCancel: false,
        confirmColor: '#127c44'
      })
    }
  },

  // 分享给好友
  onShareAppMessage() {
    return {
      title: '一贴取影 - 短视频与图集内容提取助手',
      path: '/pages/video-helper/video-helper'
    }
  },

  // 分享到朋友圈
  onShareTimeline() {
    return {
      title: '一贴取影 - 短视频与图集内容提取助手'
    }
  }
})
