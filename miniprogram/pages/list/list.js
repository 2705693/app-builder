const { categories } = require('../../data/content')

Page({
  data: {
    items: [],
    categoryName: '',
    color: '#e8f3ec'
  },
  onLoad(options) {
    const category = categories.find(c => c.id === options.categoryId) || categories[0]
    wx.setNavigationBarTitle({ title: category.name })
    this.setData({
      items: category.items,
      categoryName: category.name,
      color: category.color
    })
  },
  onTapItem(e) {
    const id = e.currentTarget.dataset.id
    wx.navigateTo({ url: `/pages/detail/detail?itemId=${id}` })
  },
  onShareAppMessage() {
    return { title: `一链取影 · ${this.data.categoryName}`, path: `/pages/index/index` }
  }
})
