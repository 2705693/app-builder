const { categories } = require('../../data/content')

Page({
  data: {
    item: null
  },
  onLoad(options) {
    let found = null
    for (const c of categories) {
      const it = c.items.find(x => x.id === options.itemId)
      if (it) {
        found = { ...it, categoryName: c.name }
        break
      }
    }
    if (found) {
      wx.setNavigationBarTitle({ title: found.title })
    }
    this.setData({ item: found })
  },
  onShareAppMessage() {
    const item = this.data.item
    return {
      title: item ? `${item.title} - 一链取影` : '一链取影',
      path: item ? `/pages/detail/detail?itemId=${item.id}` : '/pages/index/index'
    }
  }
})
