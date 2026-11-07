// video-helper.js
const { parseVideoText } = require('../../utils/video-link')
const userUtil = require('../../utils/user')
const { legal } = require('../../data/content')

const PARSE_SERVER_API = 'https://sy.sd0739.top/api/parse'

Page({
  data: {
    rawText: '',
    parsing: false,
    saving: false,
    downloading: false,
    downloadProgress: 0,
    downloadSizeText: '',
    downloadPhaseText: '',
    remainingQuota: 10,
    bonusQuota: 0,
    isVip: false,
    result: null,
    copyrightNotice: legal.copyrightNotice
  },

  onLoad() {
    if (!wx.getStorageSync('legal_agreement_accepted_v1')) {
      this.showLegalAgreement()
    }
  },

  onShow() {
    this.syncUserQuota()
  },

  onUnload() {
    if (this.currentDownloadTask) {
      try {
        this.currentDownloadTask.abort()
      } catch (e) {}
      this.currentDownloadTask = null
    }
  },

  // 同步云端用户额度
  async syncUserQuota() {
    const info = await userUtil.fetchUserInfo()
    this.setData({
      remainingQuota: info.total_quota,
      bonusQuota: info.bonus_quota,
      isVip: info.is_vip
    })
  },

  onInput(e) {
    this.setData({ rawText: e.detail.value })
  },

  // 一键读取剪贴板并填入
  pasteLink() {
    wx.getClipboardData({
      success: res => {
        const text = (res.data || '').trim()
        if (text) {
          this.setData({ rawText: text })
          wx.showToast({ title: '已粘贴文案', icon: 'none' })
        } else {
          wx.showToast({ title: '剪贴板为空', icon: 'none' })
        }
      },
      fail: () => {
        wx.showToast({ title: '读取剪贴板失败，请手动长按粘贴', icon: 'none' })
      }
    })
  },

  clearLink() {
    this.setData({ rawText: '', result: null })
  },

  showLegalAgreement() {
    wx.showModal({
      title: '重要版权提示',
      content: legal.copyrightNotice + '\n\n继续使用即表示您已阅读并同意“我的”页面中的《用户协议》和《隐私政策》。',
      confirmText: '同意并继续',
      cancelText: '暂不使用',
      confirmColor: '#127c44',
      success: res => {
        if (res.confirm) wx.setStorageSync('legal_agreement_accepted_v1', true)
      }
    })
  },

  ensureLegalAccepted() {
    if (wx.getStorageSync('legal_agreement_accepted_v1')) return true
    this.showLegalAgreement()
    return false
  },

  chooseLocalVideo() {
    if (!this.ensureLegalAccepted()) return
    wx.chooseMedia({
      count: 1,
      mediaType: ['video'],
      sourceType: ['album'],
      success: res => {
        const file = res.tempFiles && res.tempFiles[0]
        if (!file || !file.tempFilePath) return
        this.setData({
          result: {
            type: 'video',
            platform: '本地素材',
            title: '已选择本地视频',
            videoUrl: file.tempFilePath,
            coverUrl: file.thumbTempFilePath || '',
            isLocal: true
          }
        })
      }
    })
  },

  openImageRepair() {
    wx.navigateTo({ url: '/pages/image-repair/image-repair' })
  },

  repairGalleryImage(e) {
    const url = e.currentTarget.dataset.url
    if (!url) return
    const source = url.startsWith('https://sy.sd0739.top/')
      ? url
      : 'https://sy.sd0739.top/api/proxy?url=' + encodeURIComponent(url)
    wx.setStorageSync('imageRepairSource', source)
    wx.navigateTo({ url: '/pages/image-repair/image-repair?source=gallery' })
  },

  showQuotaTips() {
    const { isVip, remainingQuota, bonusQuota } = this.data
    const dailyRemaining = Math.max(0, remainingQuota - bonusQuota)
    let msg = `每日免费 10 次，今日剩余 ${dailyRemaining} 次；每日 00:00 自动恢复为 10 次。`
    if (isVip) {
      msg = '当前为不限次使用状态。'
    } else if (bonusQuota > 0) {
      msg = `每日免费 10 次，今日免费剩余 ${dailyRemaining} 次；另有额外 ${bonusQuota} 次，共剩余 ${remainingQuota} 次。额外次数不会每日增加。`
    }
    wx.showModal({
      title: isVip ? '不限次使用说明' : '使用额度说明',
      content: msg,
      showCancel: false,
      confirmText: '我知道了',
      confirmColor: '#127c44'
    })
  },

  // 开始提取核心流程
  startParse() {
    if (!this.ensureLegalAccepted()) return
    const { rawText, remainingQuota, isVip } = this.data
    if (!rawText.trim()) {
      wx.showToast({ title: '请先粘贴分享链接或文案', icon: 'none' })
      return
    }

    if (!isVip && remainingQuota <= 0) {
      wx.showModal({
        title: '额度已用完',
        content: '今日免费额度已用完，是否前往「我的」兑换授权卡密？',
        confirmText: '去兑换',
        cancelText: '取消',
        confirmColor: '#127c44',
        success: (res) => {
          if (res.confirm) {
            wx.switchTab({ url: '/pages/my/my' })
          }
        }
      })
      return
    }

    this.setData({ parsing: true, result: null })

    // 请求后端解析服务（带上用户 ID）
    this.requestBackendParse(rawText)
  },

  // 请求后端 FastAPI 解析接口
  requestBackendParse(urlText) {
    const uid = userUtil.getUserId()
    wx.request({
      url: PARSE_SERVER_API,
      method: 'POST',
      data: { url: urlText, text: urlText, user_id: uid },
      header: { 'content-type': 'application/json' },
      timeout: 60000,
      success: res => {
        this.setData({ parsing: false })
        if (res.statusCode === 200 && res.data && res.data.code === 0) {
          const data = res.data.data
          let vUrl = data.video_url || ''
          if (vUrl.startsWith('/')) {
            vUrl = 'https://sy.sd0739.top' + vUrl
          }
          let resType = data.type || 'video'
          if (resType === 'image') resType = 'images'
          const resultObj = {
            type: resType,
            platform: data.platform || '视频提取',
            title: data.title || '提取成功',
            videoUrl: vUrl,
            originUrl: data.origin_url || '',
            coverUrl: data.cover_url || data.cover || '',
            images: data.images || []
          }
          this.setData({ result: resultObj })

          // 自动加入历史记录
          userUtil.addHistory(resultObj)

          // 刷新用户最新额度
          this.syncUserQuota()

          wx.showToast({ title: '解析成功', icon: 'success' })
        } else if (res.data && res.data.code === 403) {
          wx.showModal({
            title: '额度提示',
            content: res.data.message || '今日额度已用完，请前往「我的」兑换卡密',
            confirmText: '去兑换',
            confirmColor: '#127c44',
            success: (m) => {
              if (m.confirm) wx.switchTab({ url: '/pages/my/my' })
            }
          })
        } else {
          wx.showModal({
            title: '解析提示',
            content: (res.data && (res.data.message || res.data.detail)) || '未能提取到视频，请检查链接',
            showCancel: false,
            confirmColor: '#127c44'
          })
        }
      },
      fail: err => {
        this.setData({ parsing: false })
        console.error('Request fail:', err)
        wx.showModal({
          title: '网络请求失败',
          content: '错误信息：' + ((err && err.errMsg) || '连接超时') + '\n\n提示：请在开发者工具右上角「详情」→「本地设置」中，勾选【不校验合法域名】',
          showCancel: false,
          confirmColor: '#127c44'
        })
      }
    })
  },

  // 停止 / 取消当前视频下载
  cancelDownload() {
    this.isUserAborted = true
    if (this.currentDownloadTask) {
      try {
        this.currentDownloadTask.abort()
      } catch (e) {
        console.warn('中止下载任务失败:', e)
      }
      this.currentDownloadTask = null
    }
    this.setData({
      saving: false,
      downloading: false,
      downloadProgress: 0,
      downloadSizeText: '',
      downloadPhaseText: ''
    })
    wx.hideLoading()
    wx.showToast({
      title: '已停止下载',
      icon: 'none',
      duration: 2000
    })
  },

  // 保存视频到相册（支持国内 CDN 直连极速加速 + VPS 代理无缝兜底）
  saveToAlbum() {
    const { result, saving, downloading } = this.data
    if (!result || !result.videoUrl) return
    if (result.isLocal) {
      wx.saveVideoToPhotosAlbum({
        filePath: result.videoUrl,
        success: () => wx.showToast({ title: '已保存到相册', icon: 'success' }),
        fail: err => {
          if (!String(err.errMsg || '').includes('cancel')) {
            wx.showToast({ title: '保存失败，请检查相册权限', icon: 'none' })
          }
        }
      })
      return
    }

    // 如果已经在下载中，再次点击直接触发停止
    if (downloading) {
      this.cancelDownload()
      return
    }

    if (saving) return

    this.isUserAborted = false
    this.setData({
      saving: true,
      downloading: true,
      downloadProgress: 0,
      downloadSizeText: '连接中...',
      downloadPhaseText: '正在建立连接...'
    })

    const startDownload = (targetUrl, isFallback) => {
      if (this.isUserAborted) return

      const downloadTask = wx.downloadFile({
        url: targetUrl,
        success: res => {
          this.currentDownloadTask = null
          if (this.isUserAborted) return

          if (res.statusCode !== 200 || !res.tempFilePath) {
            if (!isFallback && result.originUrl && result.videoUrl && targetUrl !== result.videoUrl) {
              startDownload(result.videoUrl, true)
              return
            }
            this.handleSaveFail('下载文件失败(状态码' + res.statusCode + ')，请检查网络或直链')
            return
          }

          // 智能判断运行环境：如果是 PC 开发者工具模拟器
          const sys = wx.getSystemInfoSync()
          if (sys.platform === 'devtools') {
            this.setData({ saving: false, downloading: false })
            wx.showModal({
              title: '下载成功 (模拟器提示)',
              content: '已成功下载到本地临时缓存！\n因电脑端开发者工具缺少手机真实相册，请点击工具栏【预览】使用手机微信测试存入相册，或点击下方【复制视频链接】在浏览器直接打开或保存。',
              showCancel: false,
              confirmText: '我知道了',
              confirmColor: '#127c44'
            })
            return
          }

          // 真机环境存入相册
          this.setData({
            downloadProgress: 100,
            downloadPhaseText: '下载完成，正在存入相册...'
          })
          let isDone = false

          // 设置 15 秒超时守护，防止系统相册 API 卡死
          const saveTimer = setTimeout(() => {
            if (!isDone) {
              isDone = true
              this.setData({ saving: false, downloading: false })
              wx.showModal({
                title: '相册保存超时',
                content: '写入相册响应较慢，请检查手机相册是否已生成该视频，或点击【复制视频链接】在手机浏览器中长按下载。',
                showCancel: false,
                confirmColor: '#127c44'
              })
            }
          }, 15000)

          wx.saveVideoToPhotosAlbum({
            filePath: res.tempFilePath,
            success: () => {
              if (isDone) return
              isDone = true
              clearTimeout(saveTimer)
              this.setData({ saving: false, downloading: false })
              wx.showToast({ title: '已成功保存相册！', icon: 'success' })
            },
            fail: err => {
              if (isDone) return
              isDone = true
              clearTimeout(saveTimer)
              this.handleSaveFail('保存相册失败')
              if (/auth deny|authorize|permission/i.test((err && err.errMsg) || '')) {
                wx.showModal({
                  title: '需要相册权限',
                  content: '保存失败，请在设置中允许微信访问手机相册权限',
                  confirmText: '去设置',
                  confirmColor: '#127c44',
                  success: m => { if (m.confirm) wx.openSetting() }
                })
              } else {
                wx.showModal({
                  title: '保存失败提示',
                  content: '未能写入相册：' + ((err && err.errMsg) || '格式不兼容') + '\n\n建议点击下方【复制视频链接】在手机浏览器中长按下载保存。',
                  showCancel: false,
                  confirmColor: '#127c44'
                })
              }
            }
          })
        },
        fail: err => {
          this.currentDownloadTask = null
          if (this.isUserAborted || (err && (err.errMsg || '').includes('abort'))) {
            this.setData({ saving: false, downloading: false })
            return
          }

          // 如果尝试国内直链被微信域名白名单限制，自动秒级切换至 VPS 代理通道
          if (!isFallback && result.originUrl && result.videoUrl && targetUrl !== result.videoUrl) {
            startDownload(result.videoUrl, true)
            return
          }
          this.handleSaveFail('下载失败：' + ((err && err.errMsg) || '网络异常'))
        }
      })

      this.currentDownloadTask = downloadTask

      // 监听实时下载进度（精确百分比 + MB大小）
      if (downloadTask && downloadTask.onProgressUpdate) {
        downloadTask.onProgressUpdate(res => {
          if (this.isUserAborted) return
          if (res.progress >= 0 && res.progress < 100) {
            const mbWritten = (res.totalBytesWritten / 1024 / 1024).toFixed(1)
            const mbTotal = (res.totalBytesExpectedToWrite / 1024 / 1024).toFixed(1)
            const sizeText = mbTotal > 0 ? `${mbWritten}MB / ${mbTotal}MB` : `${mbWritten}MB`
            this.setData({
              downloadProgress: res.progress,
              downloadSizeText: sizeText,
              downloadPhaseText: `正在下载视频 (${res.progress}%)`
            })
          } else if (res.progress >= 100) {
            this.setData({
              downloadProgress: 100,
              downloadPhaseText: '下载完成，正在存入相册...'
            })
          }
        })
      }
    }

    // 优先尝试国内千兆直链，若遇拦截自动回退 VPS
    const firstUrl = result.originUrl || result.videoUrl
    startDownload(firstUrl, false)
  },

  // 批量保存多张图集到相册
  saveAllImages() {
    const { result, saving } = this.data
    if (!result || !result.images || !result.images.length || saving) return

    this.setData({ saving: true })
    let count = 0
    const total = result.images.length
    wx.showLoading({ title: `正在保存 (0/${total})`, mask: true })

    const saveNext = index => {
      if (index >= total) {
        wx.hideLoading()
        this.setData({ saving: false })
        wx.showToast({ title: `全部 ${total} 张已保存`, icon: 'success' })
        return
      }
      wx.downloadFile({
        url: result.images[index],
        success: res => {
          if (res.tempFilePath) {
            wx.saveImageToPhotosAlbum({
              filePath: res.tempFilePath,
              success: () => {
                count++
                wx.showLoading({ title: `正在保存 (${count}/${total})`, mask: true })
                saveNext(index + 1)
              },
              fail: () => saveNext(index + 1)
            })
          } else {
            saveNext(index + 1)
          }
        },
        fail: () => saveNext(index + 1)
      })
    }

    saveNext(0)
  },

  previewSingleImage(e) {
    const current = e.currentTarget.dataset.url
    const urls = this.data.result.images || [current]
    wx.previewImage({ current, urls })
  },

  copyDirectLink() {
    const { result } = this.data
    let url = (result && (result.videoUrl || result.originUrl)) || ''
    if (!url) return
    if (url.includes('/api/proxy?') || url.includes('/api/wechat_proxy?')) {
      url += (url.includes('?') ? '&' : '?') + 'download=1'
    }
    wx.setClipboardData({
      data: url,
      success: () => wx.showToast({ title: '下载链接已复制', icon: 'success' })
    })
  },

  handleSaveFail(msg) {
    wx.hideLoading()
    this.setData({
      saving: false,
      downloading: false,
      downloadProgress: 0,
      downloadSizeText: '',
      downloadPhaseText: ''
    })
    wx.showToast({ title: msg, icon: 'none', duration: 2500 })
  }
})
