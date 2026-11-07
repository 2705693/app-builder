<?php if (!defined('ABSPATH')) exit; ?>

<div class="chaoji-parser-wrapper">
    <!-- 顶部标题与公告 -->
    <div class="chaoji-parser-header">
        <h2 class="chaoji-parser-title"><?php echo esc_html($title); ?></h2>
        <p class="chaoji-parser-subtitle"><?php echo esc_html($subtitle); ?></p>
        <?php if (!empty($announcement)): ?>
            <div class="chaoji-announcement-pill">
                <span class="chaoji-announcement-icon">ℹ️</span>
                <span class="chaoji-announcement-text"><?php echo esc_html($announcement); ?></span>
            </div>
        <?php endif; ?>
    </div>

    <!-- 12 平台彩色药丸标签 -->
    <div class="chaoji-platforms-container">
        <span class="chaoji-platform-badge badge-douyin">抖音</span>
        <span class="chaoji-platform-badge badge-xhs">小红书</span>
        <span class="chaoji-platform-badge badge-kuaishou">快手</span>
        <span class="chaoji-platform-badge badge-bilibili">B站</span>
        <span class="chaoji-platform-badge badge-tiktok">TikTok</span>
        <span class="chaoji-platform-badge badge-x">X(推特)</span>
        <span class="chaoji-platform-badge badge-youtube">YouTube</span>
        <span class="chaoji-platform-badge badge-jianying">剪映/即梦</span>
        <span class="chaoji-platform-badge badge-toutiao">今日头条</span>
        <span class="chaoji-platform-badge badge-doubao">豆包</span>
        <span class="chaoji-platform-badge badge-hongguo">红果/番茄</span>
        <span class="chaoji-platform-badge badge-channels">视频号</span>
    </div>

    <!-- 输入主卡片 -->
    <div class="chaoji-card chaoji-input-card">
        <div class="chaoji-textarea-wrapper">
            <textarea id="chaoji-input-url" placeholder="请将各大平台的分享文案或链接直接粘贴到这里...&#10;系统会自动智能过滤文本并识别链接"></textarea>
            <div class="chaoji-textarea-actions">
                <button type="button" id="chaoji-btn-paste" class="chaoji-btn-tool">📋 粘贴剪贴板</button>
                <button type="button" id="chaoji-btn-clear" class="chaoji-btn-tool">清空</button>
            </div>
        </div>
        <button type="button" id="chaoji-btn-submit" class="chaoji-btn-primary">
            <span class="chaoji-btn-text">开始提取</span>
            <span class="chaoji-btn-loader" style="display: none;"></span>
        </button>
    </div>

    <!-- 用户额度与卡密状态栏 -->
    <div class="chaoji-quota-bar">
        <div class="chaoji-quota-info">
            <span class="chaoji-user-badge">
                <span class="chaoji-user-label">用户ID:</span>
                <code id="chaoji-user-id-val" class="chaoji-user-id-val" title="点击快速复制">加载中...</code>
                <button type="button" id="chaoji-btn-copy-uid" class="chaoji-btn-mini-copy" title="复制我的用户ID">复制</button>
            </span>
            <span class="chaoji-bar-divider">|</span>
            <span class="chaoji-quota-label">当前剩余额度：</span>
            <span id="chaoji-quota-count" class="chaoji-quota-num">--</span>
            <span id="chaoji-quota-unit" class="chaoji-quota-unit">次</span>
            <span id="chaoji-vip-badge" class="chaoji-vip-badge" style="display:none;">VIP 无限次</span>
        </div>
        <button type="button" id="chaoji-btn-redeem-modal" class="chaoji-link-action">卡密兑换 &gt;</button>
    </div>

    <!-- 解析结果展示卡片 (动态显示) -->
    <div id="chaoji-result-box" class="chaoji-result-card" style="display: none;">
        <div class="chaoji-result-header">
            <span id="chaoji-result-platform" class="chaoji-result-badge">平台</span>
            <h3 id="chaoji-result-title" class="chaoji-result-title">视频标题</h3>
            <button type="button" id="chaoji-btn-copy-title" class="chaoji-btn-subtle" title="复制标题">复制标题</button>
        </div>

        <!-- 视频播放区域 -->
        <div id="chaoji-video-section" class="chaoji-video-wrapper" style="display: none;">
            <video id="chaoji-video-player" controls preload="metadata" playsinline webkit-playsinline></video>
            <div class="chaoji-video-actions">
                <button type="button" id="chaoji-btn-download-video" class="chaoji-btn-success">
                    ⬇️ 极速下载视频 (千兆直连)
                </button>
                <button type="button" id="chaoji-btn-copy-videourl" class="chaoji-btn-secondary">
                    🔗 复制无水印直链
                </button>
            </div>
        </div>

        <!-- 图集展示区域 -->
        <div id="chaoji-gallery-section" class="chaoji-gallery-wrapper" style="display: none;">
            <div class="chaoji-gallery-header">
                <span class="chaoji-gallery-count">共 <strong id="chaoji-gallery-total">0</strong> 张高清图片</span>
                <button type="button" id="chaoji-btn-copy-all-images" class="chaoji-btn-secondary chaoji-btn-sm">复制所有图片直链</button>
            </div>
            <div id="chaoji-gallery-grid" class="chaoji-gallery-grid"></div>
        </div>
    </div>

    <!-- 历史记录区域 -->
    <div class="chaoji-card chaoji-history-card">
        <div class="chaoji-history-header">
            <h4 class="chaoji-section-title">🕒 提取历史记录</h4>
            <button type="button" id="chaoji-btn-clear-history" class="chaoji-link-action chaoji-text-danger">清空历史</button>
        </div>
        <div id="chaoji-history-list" class="chaoji-history-list">
            <div class="chaoji-empty-history">暂无历史提取记录</div>
        </div>
    </div>

    <!-- 使用方法指南卡片 -->
    <div class="chaoji-card chaoji-guide-card">
        <h4 class="chaoji-section-title">📖 使用方法</h4>
        <div class="chaoji-steps-grid">
            <div class="chaoji-step-item">
                <div class="chaoji-step-circle">1</div>
                <div class="chaoji-step-text">打开抖音/小红书等平台，复制视频分享链接</div>
            </div>
            <div class="chaoji-step-item">
                <div class="chaoji-step-circle">2</div>
                <div class="chaoji-step-text">粘贴到上方文本框，点击「开始提取」</div>
            </div>
            <div class="chaoji-step-item">
                <div class="chaoji-step-circle">3</div>
                <div class="chaoji-step-text">在线预览或点击「极速下载」直接存入手机/电脑相册</div>
            </div>
        </div>
    </div>

    <!-- 自定义广告位 -->
    <?php if (!empty($ad_code)): ?>
        <div class="chaoji-ad-slot">
            <?php echo do_shortcode($ad_code); ?>
        </div>
    <?php endif; ?>

    <!-- 卡密兑换弹窗 -->
    <div id="chaoji-modal-redeem" class="chaoji-modal-overlay" style="display: none;">
        <div class="chaoji-modal-box">
            <div class="chaoji-modal-header">
                <h3>💎 兑换授权卡密</h3>
                <button type="button" class="chaoji-modal-close" data-target="chaoji-modal-redeem">&times;</button>
            </div>
            <div class="chaoji-modal-body">
                <p class="chaoji-modal-desc">
                    当前账号ID：<code id="chaoji-modal-uid" class="chaoji-modal-uid-highlight">加载中...</code><br>
                    输入管理员发放的卡密可立即解锁永久 VIP 或增加提取额度：
                </p>
                <input type="text" id="chaoji-input-cardkey" class="chaoji-input-field" placeholder="请输入卡密字符串..." />
                <button type="button" id="chaoji-btn-submit-redeem" class="chaoji-btn-primary chaoji-w-100">立即兑换</button>
            </div>
        </div>
    </div>

    <!-- 轻量消息提示 (Toast) -->
    <div id="chaoji-toast" class="chaoji-toast" style="display: none;"></div>
</div>
