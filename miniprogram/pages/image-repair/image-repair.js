const API_BASE = 'https://sy.sd0739.top'

Page({
  data: {
    sourcePath: '',
    resultUrl: '',
    mode: 'rect',
    brushSize: 24,
    canvasWidth: 320,
    canvasHeight: 320,
    imageRect: { x: 0, y: 0, w: 320, h: 320 },
    actions: [],
    currentAction: null,
    repairing: false
  },

  onLoad(options) {
    if (options.source === 'gallery') {
      const url = wx.getStorageSync('imageRepairSource')
      wx.removeStorageSync('imageRepairSource')
      if (url) this.downloadSource(url)
    }
  },

  chooseImage() {
    wx.chooseMedia({
      count: 1,
      mediaType: ['image'],
      sourceType: ['album', 'camera'],
      sizeType: ['compressed'],
      success: res => {
        const file = res.tempFiles && res.tempFiles[0]
        if (!file || !file.tempFilePath) return
        if (file.size && file.size > 15 * 1024 * 1024) {
          wx.showToast({ title: '图片不能超过15MB', icon: 'none' })
          return
        }
        this.loadImage(file.tempFilePath)
      }
    })
  },

  downloadSource(url) {
    wx.showLoading({ title: '正在读取图片' })
    wx.downloadFile({
      url,
      timeout: 60000,
      success: res => {
        wx.hideLoading()
        if (res.statusCode === 200 && res.tempFilePath) {
          this.loadImage(res.tempFilePath)
        } else {
          wx.showModal({ title: '读取失败', content: '该图片地址无法下载，请先保存到相册后再选择。', showCancel: false })
        }
      },
      fail: () => {
        wx.hideLoading()
        wx.showModal({ title: '读取失败', content: '图片域名可能未加入下载白名单，请先保存到相册后再选择。', showCancel: false })
      }
    })
  },

  loadImage(path) {
    wx.getImageInfo({
      src: path,
      success: info => {
        const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync()
        const maxWidth = Math.min(sys.windowWidth - 32, 460)
        const maxHeight = Math.min(sys.windowHeight * 0.52, 520)
        const scale = Math.min(maxWidth / info.width, maxHeight / info.height)
        const drawWidth = Math.max(1, Math.round(info.width * scale))
        const drawHeight = Math.max(1, Math.round(info.height * scale))
        this.setData({
          sourcePath: path,
          resultUrl: '',
          canvasWidth: drawWidth,
          canvasHeight: drawHeight,
          imageRect: { x: 0, y: 0, w: drawWidth, h: drawHeight },
          actions: [],
          currentAction: null
        }, () => this.drawCanvas())
      },
      fail: () => wx.showToast({ title: '无法读取图片', icon: 'none' })
    })
  },

  setMode(e) {
    this.setData({ mode: e.currentTarget.dataset.mode, currentAction: null })
    this.drawCanvas()
  },

  changeBrushSize(e) {
    this.setData({ brushSize: Number(e.detail.value) || 24 })
  },

  pointFromEvent(e) {
    const touch = e.touches[0] || e.changedTouches[0]
    return { x: touch.x, y: touch.y }
  },

  clampPoint(point) {
    const r = this.data.imageRect
    return {
      x: Math.max(r.x, Math.min(r.x + r.w, point.x)),
      y: Math.max(r.y, Math.min(r.y + r.h, point.y))
    }
  },

  touchStart(e) {
    const p = this.clampPoint(this.pointFromEvent(e))
    if (this.data.mode === 'rect') {
      this.setData({ currentAction: { type: 'rect', startX: p.x, startY: p.y, x: p.x, y: p.y, w: 0, h: 0 } })
    } else {
      this.setData({ currentAction: { type: 'stroke', size: this.data.brushSize, points: [p] } })
    }
  },

  touchMove(e) {
    const current = this.data.currentAction
    if (!current) return
    const p = this.clampPoint(this.pointFromEvent(e))
    if (current.type === 'rect') {
      current.x = Math.min(current.startX, p.x)
      current.y = Math.min(current.startY, p.y)
      current.w = Math.abs(p.x - current.startX)
      current.h = Math.abs(p.y - current.startY)
    } else {
      current.points.push(p)
    }
    this.setData({ currentAction: current })
    this.drawCanvas()
  },

  touchEnd() {
    const current = this.data.currentAction
    if (!current) return
    const valid = current.type === 'rect'
      ? current.w >= 4 && current.h >= 4
      : current.points.length > 0
    const actions = valid ? this.data.actions.concat([current]) : this.data.actions
    this.setData({ actions, currentAction: null })
    this.drawCanvas()
  },

  undo() {
    const actions = this.data.actions.slice(0, -1)
    this.setData({ actions, currentAction: null, resultUrl: '' })
    this.drawCanvas()
  },

  clearMask() {
    this.setData({ actions: [], currentAction: null, resultUrl: '' })
    this.drawCanvas()
  },

  drawCanvas() {
    if (!this.data.sourcePath) return
    const ctx = wx.createCanvasContext('repairCanvas', this)
    const r = this.data.imageRect
    ctx.clearRect(0, 0, this.data.canvasWidth, this.data.canvasHeight)
    ctx.drawImage(this.data.sourcePath, r.x, r.y, r.w, r.h)
    const actions = this.data.currentAction
      ? this.data.actions.concat([this.data.currentAction])
      : this.data.actions
    ctx.setStrokeStyle('rgba(222, 48, 65, 0.9)')
    ctx.setFillStyle('rgba(222, 48, 65, 0.28)')
    actions.forEach(action => {
      if (action.type === 'rect') {
        ctx.fillRect(action.x, action.y, action.w, action.h)
        ctx.strokeRect(action.x, action.y, action.w, action.h)
      } else if (action.points && action.points.length) {
        ctx.setLineWidth(action.size)
        ctx.setLineCap('round')
        ctx.setLineJoin('round')
        ctx.beginPath()
        ctx.moveTo(action.points[0].x, action.points[0].y)
        action.points.slice(1).forEach(p => ctx.lineTo(p.x, p.y))
        if (action.points.length === 1) ctx.lineTo(action.points[0].x + 0.1, action.points[0].y)
        ctx.stroke()
      }
    })
    ctx.draw(false)
  },

  submitRepair() {
    if (!this.data.actions.length || this.data.repairing) return
    this.setData({ repairing: true, resultUrl: '' })
    wx.showLoading({ title: '正在修复图片', mask: true })
    const mask = JSON.stringify({
      canvasWidth: this.data.canvasWidth,
      canvasHeight: this.data.canvasHeight,
      imageRect: this.data.imageRect,
      actions: this.data.actions
    })
    wx.uploadFile({
      url: API_BASE + '/api/image/inpaint',
      filePath: this.data.sourcePath,
      name: 'image',
      formData: { mask },
      timeout: 120000,
      success: res => {
        wx.hideLoading()
        this.setData({ repairing: false })
        let body
        try { body = JSON.parse(res.data) } catch (_) { body = null }
        if (res.statusCode === 200 && body && body.code === 0) {
          const path = body.data.url
          this.setData({ resultUrl: path.startsWith('/') ? API_BASE + path : path }, () => {
            wx.showToast({ title: '修复完成', icon: 'success' })
            setTimeout(() => {
              wx.pageScrollTo({ selector: '.result-card', duration: 300 })
            }, 150)
          })
        } else {
          const message = body && (body.detail || body.message)
          wx.showModal({ title: '修复失败', content: message || '服务器暂时无法处理该图片', showCancel: false })
        }
      },
      fail: err => {
        wx.hideLoading()
        this.setData({ repairing: false })
        wx.showModal({ title: '上传失败', content: (err && err.errMsg) || '请检查网络和上传域名配置', showCancel: false })
      }
    })
  },

  previewResult() {
    if (this.data.resultUrl) wx.previewImage({ current: this.data.resultUrl, urls: [this.data.resultUrl] })
  },

  saveResult() {
    if (!this.data.resultUrl) return
    wx.showLoading({ title: '正在保存' })
    wx.downloadFile({
      url: this.data.resultUrl,
      timeout: 120000,
      success: res => {
        if (res.statusCode !== 200 || !res.tempFilePath) {
          wx.hideLoading()
          wx.showToast({ title: '下载结果失败', icon: 'none' })
          return
        }
        wx.saveImageToPhotosAlbum({
          filePath: res.tempFilePath,
          success: () => {
            wx.hideLoading()
            wx.showToast({ title: '已保存到相册', icon: 'success' })
          },
          fail: () => {
            wx.hideLoading()
            wx.showModal({ title: '保存失败', content: '请在微信设置中允许访问相册。', showCancel: false })
          }
        })
      },
      fail: () => {
        wx.hideLoading()
        wx.showToast({ title: '下载结果失败', icon: 'none' })
      }
    })
  }
})
