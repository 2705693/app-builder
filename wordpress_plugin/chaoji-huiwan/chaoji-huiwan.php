<?php
/**
 * Plugin Name: 钞机汇玩 - 全网无水印视频与图集提取神器
 * Plugin URI: https://www.sd0739.top
 * Description: 聚合抖音、快手、小红书、B站、TikTok、YouTube等12+主流平台无水印视频与图集极速提取，集成在线播放器、国内千兆流式下载、本地历史记录、额度管理与卡密兑换。
 * Version: 1.0.3
 * Author: 2705693
 * Author URI: https://www.sd0739.top
 * License: GPL v2 or later
 * Text Domain: chaoji-huiwan
 */

if (!defined('ABSPATH')) {
    exit;
}

define('CHAOJI_HW_VERSION', '1.0.3');
define('CHAOJI_HW_DIR', plugin_dir_path(__FILE__));
define('CHAOJI_HW_URL', plugin_dir_url(__FILE__));

class ChaojiHuiwanPlugin {
    private static $instance = null;

    public static function get_instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        add_action('admin_menu', [$this, 'add_admin_menu']);
        add_action('admin_init', [$this, 'register_settings']);
        add_shortcode('chaoji_video_parser', [$this, 'render_shortcode']);
        add_filter('category_description', 'do_shortcode');
        add_filter('term_description', 'do_shortcode');
        add_filter('widget_text', 'do_shortcode');
        add_action('wp_enqueue_scripts', [$this, 'register_assets']);
    }

    public function register_settings() {
        register_setting('chaoji_hw_settings_group', 'chaoji_hw_api_base');
        register_setting('chaoji_hw_settings_group', 'chaoji_hw_title');
        register_setting('chaoji_hw_settings_group', 'chaoji_hw_subtitle');
        register_setting('chaoji_hw_settings_group', 'chaoji_hw_announcement');
        register_setting('chaoji_hw_settings_group', 'chaoji_hw_ad_code');
    }

    public function add_admin_menu() {
        add_options_page(
            '钞机解析设置',
            '钞机视频解析',
            'manage_options',
            'chaoji-huiwan-settings',
            [$this, 'render_admin_settings_page']
        );
    }

    public function render_admin_settings_page() {
        $api_base = get_option('chaoji_hw_api_base', 'https://sy.sd0739.top');
        $title = get_option('chaoji_hw_title', '一键提取，轻松保存');
        $subtitle = get_option('chaoji_hw_subtitle', '粘贴分享链接，保存视频或图集');
        $announcement = get_option('chaoji_hw_announcement', "仅可处理本人享有著作权或已取得权利人授权的素材。\n未经许可，不得删除他人作品的水印、作者标识或权利管理信息，不得搬运、传播或商用侵权内容。");
        $ad_code = get_option('chaoji_hw_ad_code', '');
        ?>
        <div class="wrap">
            <h1>🚀 钞机汇玩 - 视频解析设置</h1>
            <p>通过短代码 <code>[chaoji_video_parser]</code> 可以将完整功能的提取器插入任意页面或文章中。</p>
            <form method="post" action="options.php">
                <?php settings_fields('chaoji_hw_settings_group'); ?>
                <table class="form-table">
                    <tr>
                        <th scope="row"><label for="chaoji_hw_api_base">API 后端接口地址</label></th>
                        <td>
                            <input type="text" id="chaoji_hw_api_base" name="chaoji_hw_api_base" value="<?php echo esc_attr($api_base); ?>" class="regular-text" />
                            <p class="description">默认无需更改，指向云端智能分发调度网关：<code>https://sy.sd0739.top</code></p>
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="chaoji_hw_title">前台大标题</label></th>
                        <td>
                            <input type="text" id="chaoji_hw_title" name="chaoji_hw_title" value="<?php echo esc_attr($title); ?>" class="regular-text" />
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="chaoji_hw_subtitle">副标题描述</label></th>
                        <td>
                            <input type="text" id="chaoji_hw_subtitle" name="chaoji_hw_subtitle" value="<?php echo esc_attr($subtitle); ?>" class="large-text" />
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="chaoji_hw_announcement">顶部公告栏内容</label></th>
                        <td>
                            <input type="text" id="chaoji_hw_announcement" name="chaoji_hw_announcement" value="<?php echo esc_attr($announcement); ?>" class="large-text" />
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="chaoji_hw_ad_code">广告或自定义 HTML 代码</label></th>
                        <td>
                            <textarea id="chaoji_hw_ad_code" name="chaoji_hw_ad_code" rows="4" class="large-text"><?php echo esc_textarea($ad_code); ?></textarea>
                            <p class="description">可放置 Google AdSense 广告代码或横幅图片链接（显示在解析卡片下方）。</p>
                        </td>
                    </tr>
                </table>
                <?php submit_button('保存设置'); ?>
            </form>
        </div>
        <?php
    }

    public function register_assets() {
        wp_register_style(
            'chaoji-hw-css',
            CHAOJI_HW_URL . 'assets/css/chaoji-parser.css',
            [],
            CHAOJI_HW_VERSION
        );

        wp_register_script(
            'chaoji-hw-js',
            CHAOJI_HW_URL . 'assets/js/chaoji-parser.js',
            [],
            CHAOJI_HW_VERSION,
            true
        );
    }

    public function render_shortcode($atts) {
        wp_enqueue_style('chaoji-hw-css');
        wp_enqueue_script('chaoji-hw-js');

        $api_base = get_option('chaoji_hw_api_base', 'https://sy.sd0739.top');
        $title = get_option('chaoji_hw_title', '一键提取，轻松保存');
        $subtitle = get_option('chaoji_hw_subtitle', '');
        if (empty($subtitle) || strpos($subtitle, '12+主流平台') !== false || strpos($subtitle, 'web0739') !== false) {
            $subtitle = '粘贴分享链接，保存视频或图集';
        }

        $announcement = get_option('chaoji_hw_announcement', '');
        if (empty($announcement) || strpos($announcement, '个人学习研究') !== false) {
            $announcement = "仅可处理本人享有著作权或已取得权利人授权的素材。\n未经许可，不得删除他人作品的水印、作者标识或权利管理信息，不得搬运、传播或商用侵权内容。";
        }
        $ad_code = get_option('chaoji_hw_ad_code', '');

        $wp_user = wp_get_current_user();
        $wp_user_id = ($wp_user && $wp_user->ID) ? 'wp_u' . $wp_user->ID : '';

        wp_localize_script('chaoji-hw-js', 'ChaojiHwConfig', [
            'apiBase' => esc_url($api_base),
            'siteUrl' => esc_url(home_url()),
            'wpUserId' => esc_js($wp_user_id),
        ]);

        ob_start();
        include CHAOJI_HW_DIR . 'templates/parser-template.php';
        return ob_get_clean();
    }
}

ChaojiHuiwanPlugin::get_instance();
