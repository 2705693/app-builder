const { categories, tools } = require('../../data/content')

Page({
  data: {
    categories: [],
    tools: []
  },
  onLoad() {
    this.setData({ categories, tools })
  },
  onTapCategory(e) {
    const id = e.currentTarget.dataset.id
    wx.navigateTo({ url: `/pages/list/list?categoryId=${id}` })
  },
  onTapTool(e) {
    const id = e.currentTarget.dataset.id
    const tool = tools.find(item => item.id === id)
    wx.navigateTo({ url: tool && tool.path ? tool.path : `/pages/tools/tools?type=${id}` })
  },
  onShareAppMessage() {
    return { title: '一链取影', path: '/pages/index/index' }
  }
})
