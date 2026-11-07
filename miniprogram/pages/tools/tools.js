const photoSteps = [
  { id: 1, text: '删除模糊和重复照片', done: false },
  { id: 2, text: '按主题创建相册', done: false },
  { id: 3, text: '收藏重要照片', done: false },
  { id: 4, text: '备份需要长期保存的照片', done: false },
  { id: 5, text: '清空最近删除前再次确认', done: false }
]

Page({
  data: {
    type: 'filename',
    title: '文件命名器',
    date: '',
    topic: '',
    version: 'V1',
    filenameResult: '',
    tasks: ['', '', ''],
    savedPlan: [],
    photoSteps
  },
  onLoad(options) {
    const type = ['filename', 'plan', 'photo'].includes(options.type) ? options.type : 'filename'
    const titles = { filename: '文件命名器', plan: '每日计划', photo: '照片整理清单' }
    const now = new Date()
    const date = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`
    const savedPlan = wx.getStorageSync('dailyPlan') || []
    const savedPhotoSteps = wx.getStorageSync('photoSteps') || photoSteps
    wx.setNavigationBarTitle({ title: titles[type] })
    this.setData({ type, title: titles[type], date, savedPlan, photoSteps: savedPhotoSteps })
  },
  onFieldInput(e) {
    this.setData({ [e.currentTarget.dataset.field]: e.detail.value })
  },
  generateFilename() {
    const topic = this.data.topic.trim()
    if (!topic) {
      wx.showToast({ title: '请先输入文件主题', icon: 'none' })
      return
    }
    const cleanTopic = topic.replace(/[\\/:*?"<>|\s]+/g, '-')
    this.setData({ filenameResult: `${this.data.date}_${cleanTopic}_${this.data.version}` })
  },
  copyFilename() {
    if (!this.data.filenameResult) return
    wx.setClipboardData({ data: this.data.filenameResult })
  },
  onTaskInput(e) {
    const tasks = [...this.data.tasks]
    tasks[Number(e.currentTarget.dataset.index)] = e.detail.value
    this.setData({ tasks })
  },
  savePlan() {
    const savedPlan = this.data.tasks.map(x => x.trim()).filter(Boolean)
    if (!savedPlan.length) {
      wx.showToast({ title: '请至少填写一项任务', icon: 'none' })
      return
    }
    wx.setStorageSync('dailyPlan', savedPlan)
    this.setData({ savedPlan })
    wx.showToast({ title: '已保存到本机' })
  },
  togglePhotoStep(e) {
    const id = Number(e.currentTarget.dataset.id)
    const photoSteps = this.data.photoSteps.map(item => item.id === id ? { ...item, done: !item.done } : item)
    wx.setStorageSync('photoSteps', photoSteps)
    this.setData({ photoSteps })
  },
  resetPhotoSteps() {
    const steps = photoSteps.map(item => ({ ...item }))
    wx.setStorageSync('photoSteps', steps)
    this.setData({ photoSteps: steps })
  }
})
