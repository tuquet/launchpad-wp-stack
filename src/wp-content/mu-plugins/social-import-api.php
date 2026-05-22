<?php
/**
 * Plugin Name: Social Sync API
 * Description: REST API endpoint for n8n to push individual social media posts.
 * Author: Antigravity
 * Version: 1.0
 */

if (!defined('ABSPATH')) {
    exit;
}

add_action('rest_api_init', function () {
    register_rest_route('social-sync/v1', '/import-post', [
        'methods'             => 'POST',
        'callback'            => 'social_sync_import_post',
        'permission_callback' => function () {
            // Require application password or basic auth
            return current_user_can('publish_posts');
        }
    ]);
});

function social_sync_attach_media($url, $post_id) {
    require_once(ABSPATH . 'wp-admin/includes/media.php');
    require_once(ABSPATH . 'wp-admin/includes/file.php');
    require_once(ABSPATH . 'wp-admin/includes/image.php');

    // Do NOT strip stp parameter as it invalidates Facebook CDN URL signature and returns 403
    // $url = preg_replace('/stp=[^&]*&?/', '', $url);

    $tmp = download_url($url);
    if (is_wp_error($tmp)) return $tmp;

    $file_array = [];
    $parsed = wp_parse_url($url, PHP_URL_PATH);
    $filename = basename($parsed);
    
    if (strpos($url, '.mp4') !== false) {
        if (!preg_match('/\.mp4$/i', $filename)) $filename .= '.mp4';
    } else {
        if (!preg_match('/\.(jpe?g|png|gif|webp)$/i', $filename)) $filename .= '.jpg';
    }

    $file_array['name'] = $filename;
    $file_array['tmp_name'] = $tmp;

    $attachment_id = media_handle_sideload($file_array, $post_id);
    if (!is_wp_error($attachment_id)) {
        wp_update_post([
            'ID'          => $attachment_id,
            'post_author' => 1,
        ]);
    }
    return $attachment_id;
}

function social_sync_import_post(WP_REST_Request $request) {
    $platform    = sanitize_text_field($request->get_param('platform'));
    $original_id = sanitize_text_field($request->get_param('original_id'));
    $url         = esc_url_raw($request->get_param('url'));
    $text        = $request->get_param('text');
    $media_urls  = $request->get_param('media_urls'); // Array of URLs
    $post_date   = sanitize_text_field($request->get_param('post_date'));

    if (empty($original_id) || empty($platform)) {
        return new WP_Error('missing_params', 'Platform and original_id are required.', ['status' => 400]);
    }

    // Check duplicate
    $existing = get_posts([
        'post_type'      => 'post',
        'meta_key'       => '_social_original_id',
        'meta_value'     => $original_id,
        'posts_per_page' => 1,
        'post_status'    => 'any',
    ]);

    if (!empty($existing)) {
        return rest_ensure_response([
            'status' => 'skipped',
            'message' => 'Post already exists',
            'post_id' => $existing[0]->ID
        ]);
    }

    // Set lock transient to prevent race conditions during concurrent imports
    $lock_key = 'social_import_lock_' . md5($original_id);
    if (get_transient($lock_key)) {
        return new WP_Error('import_locked', 'Another import process is currently handling this post.', ['status' => 409]);
    }
    set_transient($lock_key, '1', 180); // Lock for 3 minutes

    // Category
    $cat_name = ucfirst($platform);
    $cat_slug = strtolower($platform);
    $term = term_exists($cat_slug, 'category');
    if (!$term) {
        $term = wp_insert_term($cat_name, 'category', ['slug' => $cat_slug]);
    }
    $cat_id = is_wp_error($term) ? 0 : (int) $term['term_id'];

    // Title & Content
    $title_str = strtok($text, "\n");
    $title_str = trim($title_str);
    $title = mb_strlen($title_str) > 100 ? mb_substr($title_str, 0, 100) . '…' : $title_str;
    if (empty($title)) $title = '(No caption)';

    $escaped = esc_html($text);
    $paragraphs = preg_split('/\n{2,}/', $escaped);
    $content = '';
    foreach ($paragraphs as $p) {
        $p = nl2br(trim($p));
        if (!empty($p)) $content .= "<p>$p</p>\n";
    }

    $post_args = [
        'post_type'    => 'post',
        'post_title'   => $title,
        'post_content' => $content,
        'post_status'  => 'publish',
        'post_author'  => get_current_user_id(),
        'post_category'=> [$cat_id],
        'meta_input'   => [
            '_social_original_id' => $original_id,
            '_social_platform'    => $platform,
            '_social_source_url'  => $url,
            '_social_imported_at' => date('c'),
            '_social_media_count' => is_array($media_urls) ? count($media_urls) : 0,
        ],
    ];

    if (!empty($post_date)) {
        $post_args['post_date'] = date('Y-m-d H:i:s', strtotime($post_date));
    }

    $post_id = wp_insert_post($post_args);
    if (is_wp_error($post_id)) {
        delete_transient($lock_key);
        return $post_id;
    }

    wp_set_post_categories($post_id, [$cat_id]);

    // Handle Media
    $featured_set = false;
    $gallery_html = '';
    $downloaded_count = 0;

    if (is_array($media_urls) && !empty($media_urls)) {
        foreach ($media_urls as $media_url) {
            $att_id = social_sync_attach_media($media_url, $post_id);
            if (!is_wp_error($att_id)) {
                $downloaded_count++;
                if (!$featured_set && wp_attachment_is_image($att_id)) {
                    set_post_thumbnail($post_id, $att_id);
                    $featured_set = true;
                } else {
                    if (wp_attachment_is_image($att_id)) {
                        $gallery_html .= wp_get_attachment_image($att_id, 'full') . "\n";
                    } else {
                        $gallery_html .= wp_video_shortcode(['src' => wp_get_attachment_url($att_id)]) . "\n";
                    }
                }
            }
        }
        if ($gallery_html) {
            wp_update_post([
                'ID' => $post_id,
                'post_content' => $content . "\n\n<div class='social-gallery'>\n" . $gallery_html . "</div>"
            ]);
        }
    }

    delete_transient($lock_key);

    return rest_ensure_response([
        'status' => 'success',
        'message' => 'Post created successfully',
        'post_id' => $post_id,
        'media_downloaded' => $downloaded_count
    ]);
}
