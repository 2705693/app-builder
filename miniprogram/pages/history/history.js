const userUtil = require('../../utils/user')

Page({
  data: {
    list: []
  },

  onShow() {
    this.loadHistory()
  },

  loadHistory() {
    const list = userUtil.getHistory()
    this.setData({ list })
  },

  handleClear() {
    wx.showModal({
      title: '确认清空',
      content: '确定要清空手机本地历史吗？不会删除服务器日志，也不会影响剩余次数。',
      confirmColor: '#127c44',
      success: (res) => {
        if (res.confirm) {
          userUtil.clearHistory()
          this.setData({ list: [] })
          wx.showToast({ title: '本地历史已清空', icon: 'success' })
        }
      }
    })
  },

  copyLink(e) {
    let url = e.currentTarget.dataset.url
    if (!url) return
    if (url.includes('/api/proxy?') || url.includes('/api/wechat_proxy?')) {
      if (!/[?&]download=1(?:&|$)/.test(url)) {
        url += (url.includes('?') ? '&' : '?') + 'download=1'
      }
    }
    wx.setClipboardData({
      data: url,
      success: () => {
        wx.showToast({ title: '下载链接已复制', icon: 'success' })
      }
    })
  },

  saveToAlbum(e) {
    const item = e.currentTarget.dataset.item
    if (item.type === 'images' && item.images && item.images.length > 0) {
      wx.showLoading({ title: '正在保存图集...' })
      let successCount = 0
      const saveNext = (idx) => {
        if (idx >= item.images.length) {
          wx.hideLoading()
          wx.showToast({ title: `成功保存 ${successCount} 张图片`, icon: 'success' })
          return
        }
        wx.downloadFile({
          url: item.images[idx],
          success: (dlRes) => {
            wx.saveImageToPhotosAlbum({
              filePath: dlRes.tempFilePath,
              success: () => { successCount++ },
              complete: () => { saveNext(idx + 1) }
            })
          },
          fail: () => { saveNext(idx + 1) }
        })
      }
      saveNext(0)
    } else if (item.videoUrl) {
      wx.showLoading({ title: '准备下载视频...', mask: true })
      const dlTask = wx.downloadFile({
        url: item.videoUrl,
        success: (dlRes) => {
          if (dlRes.statusCode === 200 && dlRes.tempFilePath) {
            const sys = wx.getSystemInfoSync()
            if (sys.platform === 'devtools') {
              wx.hideLoading()
              wx.showModal({
                title: '下载成功 (模拟器提示)',
                content: 'PC开发者工具缺少手机真实相册，请在真机测试保存相册，或点击【复制下载链接】在浏览器打开。',
                showCancel: false,
                confirmColor: '#127c44'
              })
              return
            }

            wx.showLoading({ title: '正在存入相册...', mask: true })
            let isDone = false
            const timer = setTimeout(() => {
              if (!isDone) {
                isDone = true
                wx.hideLoading()
                wx.showToast({ title: '相册保存响应超时', icon: 'none' })
              }
            }, 15000)

            wx.saveVideoToPhotosAlbum({
              filePath: dlRes.tempFilePath,
              success: () => {
                if (isDone) return
                isDone = true
                clearTimeout(timer)
                wx.hideLoading()
                wx.showToast({ title: '已存入相册', icon: 'success' })
              },
              fail: () => {
                if (isDone) return
                isDone = true
                clearTimeout(timer)
                wx.hideLoading()
                wx.showToast({ title: '保存相册失败', icon: 'none' })
              }
            })
          } else {
            wx.hideLoading()
            wx.showToast({ title: '下载失败(' + dlRes.statusCode + ')', icon: 'none' })
          }
        },
        fail: () => {
          wx.hideLoading()
          wx.showToast({ title: '网络异常，下载失败', icon: 'none' })
        }
      })

      if (dlTask && dlTask.onProgressUpdate) {
        dlTask.onProgressUpdate(res => {
          if (res.progress >= 0 && res.progress < 100) {
            wx.showLoading({ title: `下载中 ${res.progress}%`, mask: true })
          }
        })
      }
    }
  },

  goToParse() {
    wx.switchTab({
      url: '/pages/video-helper/video-helper'
    })
  }
})
