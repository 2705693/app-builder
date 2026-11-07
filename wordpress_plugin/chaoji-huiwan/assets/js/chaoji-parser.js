/**
 * 钞机汇玩 - WordPress 短视频/图集提取插件 核心交互逻辑
 */
(function () {
    'use strict';

    // 配置与状态
    const config = window.ChaojiHwConfig || {
        apiBase: 'https://sy.sd0739.top',
        siteUrl: window.location.origin
    };

    let currentUser = null;
    let currentResult = null;

    // 获取或初始化用户设备 ID
    function getUserId() {
        let uid = localStorage.getItem('chaoji_wp_user_id');
        if (!uid) {
            uid = 'wp_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8);
            localStorage.setItem('chaoji_wp_user_id', uid);
        }
        return uid;
    }

    // 轻量 Toast 提示
    function showToast(message, duration = 2500) {
        const toast = document.getElementById('chaoji-toast');
        if (!toast) return;
        toast.textContent = message;
        toast.style.display = 'block';
        clearTimeout(toast._timer);
        toast._timer = setTimeout(() => {
            toast.style.display = 'none';
        }, duration);
    }

    // 复制文本到剪贴板
    async function copyToClipboard(text, successMsg = '复制成功！') {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            try {
                await navigator.clipboard.writeText(text);
                showToast(successMsg);
                return;
            } catch (e) {}
        }
        // 兼容降级方案
        const input = document.createElement('textarea');
        input.value = text;
        input.style.position = 'fixed';
        input.style.opacity = '0';
        document.body.appendChild(input);
        input.select();
        try {
            document.execCommand('copy');
            showToast(successMsg);
        } catch (err) {
            showToast('复制失败，请手动长按复制');
        }
        document.body.removeChild(input);
    }

    // 获取并更新用户额度信息
    async function fetchUserInfo() {
        const uid = getUserId();
        try {
            const resp = await fetch(`${config.apiBase}/api/user/info?user_id=${encodeURIComponent(uid)}`);
            const json = await resp.json();
            if (json.code === 0 && json.data) {
                currentUser = json.data;
                const quotaEl = document.getElementById('chaoji-quota-count');
                const unitEl = document.getElementById('chaoji-quota-unit');
                const vipBadge = document.getElementById('chaoji-vip-badge');

                if (currentUser.is_vip) {
                    if (quotaEl) quotaEl.textContent = '∞';
                    if (unitEl) unitEl.textContent = '';
                    if (vipBadge) vipBadge.style.display = 'inline-block';
                } else {
                    if (quotaEl) quotaEl.textContent = currentUser.total_quota !== undefined ? currentUser.total_quota : currentUser.daily_quota;
                    if (unitEl) unitEl.textContent = '次';
                    if (vipBadge) vipBadge.style.display = 'none';
                }
            }
        } catch (e) {
            console.warn('[ChaojiHuiwan] 获取额度失败:', e);
        }
    }

    // 历史记录本地读写
    function getHistory() {
        try {
            const raw = localStorage.getItem('chaoji_history_list');
            return raw ? JSON.parse(raw) : [];
        } catch (e) {
            return [];
        }
    }

    function saveHistoryItem(item) {
        let list = getHistory();
        // 去重
        list = list.filter(i => i.url !== item.url);
        list.unshift(item);
        if (list.length > 20) list = list.slice(0, 20);
        localStorage.setItem('chaoji_history_list', JSON.stringify(list));
        renderHistory();
    }

    function renderHistory() {
        const container = document.getElementById('chaoji-history-list');
        if (!container) return;

        const list = getHistory();
        if (list.length === 0) {
            container.innerHTML = '<div class="chaoji-empty-history">暂无历史提取记录</div>';
            return;
        }

        container.innerHTML = list.map(item => `
            <div class="chaoji-history-item">
                <span class="chaoji-history-title" title="${escapeHtml(item.title)}">${escapeHtml(item.title || '提取的媒体')}</span>
                <button type="button" class="chaoji-btn-tool chaoji-btn-history-load" data-url="${escapeHtml(item.url)}">再次查看</button>
            </div>
        `).join('');

        container.querySelectorAll('.chaoji-btn-history-load').forEach(btn => {
            btn.addEventListener('click', () => {
                const url = btn.getAttribute('data-url');
                const input = document.getElementById('chaoji-input-url');
                if (input) input.value = url;
                doParse();
            });
        });
    }

    function escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // 执行解析提取
    async function doParse() {
        const input = document.getElementById('chaoji-input-url');
        const submitBtn = document.getElementById('chaoji-btn-submit');
        const btnText = submitBtn ? submitBtn.querySelector('.chaoji-btn-text') : null;
        const btnLoader = submitBtn ? submitBtn.querySelector('.chaoji-btn-loader') : null;

        if (!input) return;
        const text = input.value.trim();
        if (!text) {
            showToast('请先输入或粘贴分享链接！');
            input.focus();
            return;
        }

        // 加载态
        if (submitBtn) submitBtn.disabled = true;
        if (btnText) btnText.textContent = '正在极速解析中...';
        if (btnLoader) btnLoader.style.display = 'inline-block';

        try {
            const resp = await fetch(`${config.apiBase}/api/parse`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    text: text,
                    user_id: getUserId()
                })
            });

            const json = await resp.json();

            if (json.code !== 0) {
                showToast(json.message || '解析失败，请检查链接有效性');
                return;
            }

            currentResult = json.data;
            renderResult(currentResult, text);
            fetchUserInfo(); // 刷新剩余额度
        } catch (err) {
            showToast('网络请求异常，请稍后重试');
            console.error(err);
        } finally {
            if (submitBtn) submitBtn.disabled = false;
            if (btnText) btnText.textContent = '开始提取';
            if (btnLoader) btnLoader.style.display = 'none';
        }
    }

    // 渲染结果区域
    function renderResult(data, originText) {
        const box = document.getElementById('chaoji-result-box');
        const platformBadge = document.getElementById('chaoji-result-platform');
        const titleEl = document.getElementById('chaoji-result-title');
        const videoSection = document.getElementById('chaoji-video-section');
        const gallerySection = document.getElementById('chaoji-gallery-section');
        const player = document.getElementById('chaoji-video-player');

        if (!box) return;

        box.style.display = 'block';
        if (platformBadge) platformBadge.textContent = data.platform || '视频';
        if (titleEl) titleEl.textContent = data.title || '提取成功';

        // 写入本地历史
        saveHistoryItem({
            title: data.title || '无水印媒体',
            url: originText,
            platform: data.platform,
            time: new Date().toLocaleString()
        });

        // 视频类型处理
        if (data.type === 'video' || data.video_url) {
            if (videoSection) videoSection.style.display = 'block';
            if (gallerySection) gallerySection.style.display = 'none';

            let playUrl = data.video_url;
            if (playUrl.startsWith('/')) {
                playUrl = config.apiBase + playUrl;
            }

            if (player) {
                player.src = playUrl;
                if (data.cover_url) player.poster = data.cover_url;
                player.load();
            }

            // 绑定下载按钮 (走智能主备千兆代理)
            const downloadBtn = document.getElementById('chaoji-btn-download-video');
            if (downloadBtn) {
                downloadBtn.onclick = () => {
                    let dlUrl = playUrl;
                    if (dlUrl.includes('/api/proxy')) {
                        dlUrl += (dlUrl.includes('?') ? '&' : '?') + 'download=1';
                    }
                    // 新建隐藏 <a> 标签触发浏览器原生极速下载
                    const a = document.createElement('a');
                    a.href = dlUrl;
                    a.download = (data.title || 'video') + '.mp4';
                    a.target = '_blank';
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    showToast('已开始极速下载！');
                };
            }

            // 复制视频直链
            const copyVideoBtn = document.getElementById('chaoji-btn-copy-videourl');
            if (copyVideoBtn) {
                copyVideoBtn.onclick = () => copyToClipboard(playUrl, '视频直链已复制到剪贴板！');
            }
        }
        // 图集类型处理
        else if (data.images && data.images.length > 0) {
            if (videoSection) videoSection.style.display = 'none';
            if (gallerySection) gallerySection.style.display = 'block';

            const totalEl = document.getElementById('chaoji-gallery-total');
            const gridEl = document.getElementById('chaoji-gallery-grid');
            if (totalEl) totalEl.textContent = data.images.length;

            if (gridEl) {
                gridEl.innerHTML = data.images.map((imgUrl, idx) => `
                    <div class="chaoji-gallery-item">
                        <img src="${escapeHtml(imgUrl)}" loading="lazy" alt="图集 ${idx + 1}" />
                        <a href="${escapeHtml(imgUrl)}" target="_blank" download="image_${idx + 1}.jpg" class="chaoji-gallery-item-download">下载</a>
                    </div>
                `).join('');
            }

            // 复制所有图片链接
            const copyAllBtn = document.getElementById('chaoji-btn-copy-all-images');
            if (copyAllBtn) {
                copyAllBtn.onclick = () => copyToClipboard(data.images.join('\n'), '全部高清图片链接已复制！');
            }
        }

        // 顺滑滚动到结果卡片
        box.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }

    // 初始化事件绑定
    function initEvents() {
        // 粘贴按钮
        const pasteBtn = document.getElementById('chaoji-btn-paste');
        if (pasteBtn) {
            pasteBtn.addEventListener('click', async () => {
                if (navigator.clipboard && navigator.clipboard.readText) {
                    try {
                        const clipText = await navigator.clipboard.readText();
                        const input = document.getElementById('chaoji-input-url');
                        if (input) {
                            input.value = clipText;
                            showToast('已从剪贴板粘贴！');
                        }
                        return;
                    } catch (e) {}
                }
                showToast('请直接在输入框中按 Ctrl+V 或长按粘贴');
            });
        }

        // 清空按钮
        const clearBtn = document.getElementById('chaoji-btn-clear');
        if (clearBtn) {
            clearBtn.addEventListener('click', () => {
                const input = document.getElementById('chaoji-input-url');
                if (input) input.value = '';
                showToast('已清空输入框');
            });
        }

        // 提交解析按钮
        const submitBtn = document.getElementById('chaoji-btn-submit');
        if (submitBtn) {
            submitBtn.addEventListener('click', doParse);
        }

        // 复制标题按钮
        const copyTitleBtn = document.getElementById('chaoji-btn-copy-title');
        if (copyTitleBtn) {
            copyTitleBtn.addEventListener('click', () => {
                const titleEl = document.getElementById('chaoji-result-title');
                if (titleEl) copyToClipboard(titleEl.textContent, '标题已复制！');
            });
        }

        // 清空历史记录
        const clearHistBtn = document.getElementById('chaoji-btn-clear-history');
        if (clearHistBtn) {
            clearHistBtn.addEventListener('click', () => {
                if (confirm('确定要清空所有本地提取历史吗？')) {
                    localStorage.removeItem('chaoji_history_list');
                    renderHistory();
                    showToast('历史记录已清空');
                }
            });
        }

        // 卡密兑换弹窗打开/关闭
        const redeemModalBtn = document.getElementById('chaoji-btn-redeem-modal');
        const modalRedeem = document.getElementById('chaoji-modal-redeem');
        if (redeemModalBtn && modalRedeem) {
            redeemModalBtn.addEventListener('click', () => {
                modalRedeem.style.display = 'flex';
            });
        }

        document.querySelectorAll('.chaoji-modal-close').forEach(btn => {
            btn.addEventListener('click', () => {
                const target = btn.getAttribute('data-target');
                const modal = document.getElementById(target);
                if (modal) modal.style.display = 'none';
            });
        });

        // 卡密兑换提交
        const submitRedeemBtn = document.getElementById('chaoji-btn-submit-redeem');
        if (submitRedeemBtn) {
            submitRedeemBtn.addEventListener('click', async () => {
                const input = document.getElementById('chaoji-input-cardkey');
                if (!input || !input.value.trim()) {
                    showToast('请输入有效的卡密字符串！');
                    return;
                }

                submitRedeemBtn.disabled = true;
                submitRedeemBtn.textContent = '兑换中...';

                try {
                    const resp = await fetch(`${config.apiBase}/api/redeem`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            user_id: getUserId(),
                            card_key: input.value.trim()
                        })
                    });
                    const res = await resp.json();
                    if (res.code === 0) {
                        showToast(res.message || '🎉 恭喜，卡密兑换成功！');
                        if (modalRedeem) modalRedeem.style.display = 'none';
                        input.value = '';
                        fetchUserInfo();
                    } else {
                        showToast(res.message || '卡密无效或已被使用');
                    }
                } catch (e) {
                    showToast('网络错误，兑换失败');
                } finally {
                    submitRedeemBtn.disabled = false;
                    submitRedeemBtn.textContent = '立即兑换';
                }
            });
        }
    }

    // 页面初始化
    document.addEventListener('DOMContentLoaded', () => {
        fetchUserInfo();
        renderHistory();
        initEvents();
    });
})();
