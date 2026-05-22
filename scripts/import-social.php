<?php
/**
 * Social Media → WordPress Import Script
 * Chạy bằng: wp eval-file /var/www/html/wp-content/mu-plugins/import-social.php
 *
 * Import posts từ Apify JSON datasets vào CPT social_post
 * Tạo 2 category: Facebook, Instagram
 */

// ── Config ────────────────────────────────────────────────────────────
$fb_json_path = '/tmp/dataset_fb.json';
$ig_json_path = '/tmp/dataset_ig.json';

// ── Tạo categories ──────────────────────────────────────────────────
function ensure_category($name, $slug) {
    $term = term_exists($slug, 'category');
    if (!$term) {
        $result = wp_insert_term($name, 'category', ['slug' => $slug]);
        if (is_wp_error($result)) {
            echo "⚠️ Error creating category '$name': " . $result->get_error_message() . "\n";
            return 0;
        }
        echo "✅ Created category: $name (ID: {$result['term_id']})\n";
        return (int) $result['term_id'];
    }
    echo "ℹ️ Category '$name' already exists (ID: {$term['term_id']})\n";
    return (int) $term['term_id'];
}

$fb_cat_id = ensure_category('Facebook', 'facebook');
$ig_cat_id = ensure_category('Instagram', 'instagram');

// ── Helper: Extract title from text ─────────────────────────────────
function extract_title($text, $max = 100) {
    if (empty($text)) return '(No caption)';
    $first_line = strtok($text, "\n");
    $first_line = trim($first_line);
    if (mb_strlen($first_line) > $max) {
        $first_line = mb_substr($first_line, 0, $max) . '…';
    }
    return $first_line ?: '(No caption)';
}

// ── Helper: Convert text to HTML content ────────────────────────────
function text_to_html($text) {
    if (empty($text)) return '';
    $escaped = esc_html($text);
    $paragraphs = preg_split('/\n{2,}/', $escaped);
    $html = '';
    foreach ($paragraphs as $p) {
        $p = nl2br(trim($p));
        if (!empty($p)) {
            $html .= "<p>$p</p>\n";
        }
    }
    return $html;
}

// ── Helper: Check duplicate ─────────────────────────────────────────
function post_exists_by_original_id($original_id) {
    $existing = get_posts([
        'post_type'      => 'post',
        'meta_key'       => '_social_original_id',
        'meta_value'     => $original_id,
        'posts_per_page' => 1,
        'post_status'    => 'any',
    ]);
    return !empty($existing);
}

// ── Helper: Sideload Media ──────────────────────────────────────────
function attach_media_from_url($url, $post_id) {
    require_once(ABSPATH . 'wp-admin/includes/media.php');
    require_once(ABSPATH . 'wp-admin/includes/file.php');
    require_once(ABSPATH . 'wp-admin/includes/image.php');

    // Remove Facebook resolution limits (e.g. stp=dst-jpg_s590x590_tt6) to get the original high-res image
    $url = preg_replace('/stp=[^&]*&?/', '', $url);

    $tmp = download_url($url);
    if (is_wp_error($tmp)) {
        return $tmp;
    }

    $file_array = [];
    $parsed = wp_parse_url($url, PHP_URL_PATH);
    $filename = basename($parsed);
    
    // Guess extension if missing
    if (strpos($url, '.mp4') !== false) {
        if (!preg_match('/\.mp4$/i', $filename)) $filename .= '.mp4';
    } else {
        if (!preg_match('/\.(jpe?g|png|gif|webp)$/i', $filename)) $filename .= '.jpg';
    }

    $file_array['name'] = $filename;
    $file_array['tmp_name'] = $tmp;

    $attachment_id = media_handle_sideload($file_array, $post_id);
    return $attachment_id;
}

// ── Import Facebook Posts ───────────────────────────────────────────
echo "\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
echo "📘 IMPORTING FACEBOOK POSTS\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";

$fb_count = 0;
$fb_skip = 0;

if (file_exists($fb_json_path)) {
    $fb_data = json_decode(file_get_contents($fb_json_path), true);
    if (!$fb_data) {
        echo "❌ Failed to parse Facebook JSON\n";
    } else {
        echo "📊 Found " . count($fb_data) . " Facebook posts\n\n";

        foreach ($fb_data as $i => $post) {
            $text = $post['text'] ?? '';
            $url  = $post['url'] ?? '';

            // Generate unique ID from URL
            $original_id = 'fb_' . md5($url);

            // Skip duplicates
            if (post_exists_by_original_id($original_id)) {
                $fb_skip++;
                continue;
            }

            $title   = extract_title($text);
            $content = text_to_html($text);

            // Count media (skip first item which is mediaset_token)
            $media_items = [];
            if (!empty($post['media'])) {
                foreach ($post['media'] as $m) {
                    if (isset($m['image']['uri'])) {
                        $media_items[] = $m['image']['uri'];
                    }
                }
            }

            $post_id = wp_insert_post([
                'post_type'    => 'post',
                'post_title'   => $title,
                'post_content' => $content,
                'post_status'  => 'publish',
                'post_author'  => 1,
                'post_category'=> [$fb_cat_id],
                'meta_input'   => [
                    '_social_original_id' => $original_id,
                    '_social_platform'    => 'facebook',
                    '_social_source_url'  => $url,
                    '_social_imported_at' => date('c'),
                    '_social_media_count' => count($media_items),
                ],
            ]);

            if (is_wp_error($post_id)) {
                echo "  ❌ [{$i}] Error: " . $post_id->get_error_message() . "\n";
                continue;
            }

            // Assign category
            wp_set_post_categories($post_id, [$fb_cat_id]);

            // Download and attach media
            $featured_set = false;
            $gallery_html = '';
            if (!empty($media_items)) {
                foreach ($media_items as $media_url) {
                    $att_id = attach_media_from_url($media_url, $post_id);
                    if (!is_wp_error($att_id)) {
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

            $fb_count++;
            $short_title = mb_substr($title, 0, 50);
            echo "  ✅ [{$fb_count}] ID:{$post_id} — {$short_title}… (media: " . count($media_items) . ")\n";
        }
    }
} else {
    echo "⚠️ Facebook JSON not found at: $fb_json_path\n";
}

echo "\n📘 Facebook: {$fb_count} imported, {$fb_skip} skipped (duplicate)\n";

// ── Import Instagram Posts ──────────────────────────────────────────
echo "\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
echo "📸 IMPORTING INSTAGRAM POSTS\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";

$ig_count = 0;
$ig_skip = 0;

if (file_exists($ig_json_path)) {
    $ig_data = json_decode(file_get_contents($ig_json_path), true);
    if (!$ig_data) {
        echo "❌ Failed to parse Instagram JSON\n";
    } else {
        echo "📊 Found " . count($ig_data) . " Instagram posts\n\n";

        foreach ($ig_data as $i => $post) {
            $caption = $post['caption'] ?? '';
            $url     = $post['url'] ?? '';
            $ig_id   = $post['id'] ?? '';
            $type    = $post['type'] ?? 'Image';
            $ts      = $post['timestamp'] ?? '';

            $original_id = 'ig_' . $ig_id;

            // Skip duplicates
            if (post_exists_by_original_id($original_id)) {
                $ig_skip++;
                continue;
            }

            $title   = extract_title($caption);
            $content = text_to_html($caption);

            // Collect media URLs
            $media_items = [];
            if ($type === 'Sidecar' && !empty($post['childPosts'])) {
                foreach ($post['childPosts'] as $child) {
                    if (!empty($child['videoUrl'])) {
                        $media_items[] = $child['videoUrl'];
                    } elseif (!empty($child['displayUrl'])) {
                        $media_items[] = $child['displayUrl'];
                    }
                }
            } elseif ($type === 'Video' && !empty($post['videoUrl'])) {
                $media_items[] = $post['videoUrl'];
            } elseif (!empty($post['images'])) {
                $media_items[] = $post['images'][0]; // Just take first image if array
            } elseif (!empty($post['displayUrl'])) {
                $media_items[] = $post['displayUrl'];
            }
            $media_count = count($media_items);

            // Parse timestamp for post_date
            $post_date = '';
            if (!empty($ts)) {
                $dt = new DateTime($ts);
                $post_date = $dt->format('Y-m-d H:i:s');
            }

            $post_args = [
                'post_type'    => 'post',
                'post_title'   => $title,
                'post_content' => $content,
                'post_status'  => 'publish',
                'post_author'  => 1,
                'post_category'=> [$ig_cat_id],
                'meta_input'   => [
                    '_social_original_id' => $original_id,
                    '_social_platform'    => 'instagram',
                    '_social_source_url'  => $url,
                    '_social_imported_at' => date('c'),
                    '_social_media_count' => $media_count,
                ],
            ];

            if ($post_date) {
                $post_args['post_date']     = $post_date;
                $post_args['post_date_gmt'] = get_gmt_from_date($post_date);
            }

            $post_id = wp_insert_post($post_args);

            if (is_wp_error($post_id)) {
                echo "  ❌ [{$i}] Error: " . $post_id->get_error_message() . "\n";
                continue;
            }

            // Assign category
            wp_set_post_categories($post_id, [$ig_cat_id]);

            // Download and attach media
            $featured_set = false;
            $gallery_html = '';
            if (!empty($media_items)) {
                foreach ($media_items as $media_url) {
                    $att_id = attach_media_from_url($media_url, $post_id);
                    if (!is_wp_error($att_id)) {
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

            $ig_count++;
            $short_title = mb_substr($title, 0, 50);
            echo "  ✅ [{$ig_count}] ID:{$post_id} — {$short_title}… (type: {$type}, media: {$media_count})\n";
        }
    }
} else {
    echo "⚠️ Instagram JSON not found at: $ig_json_path\n";
}

echo "\n📸 Instagram: {$ig_count} imported, {$ig_skip} skipped (duplicate)\n";

// ── Summary ─────────────────────────────────────────────────────────
echo "\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
echo "🎉 IMPORT COMPLETE\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
echo "📘 Facebook:  {$fb_count} imported, {$fb_skip} skipped\n";
echo "📸 Instagram: {$ig_count} imported, {$ig_skip} skipped\n";
echo "📊 Total:     " . ($fb_count + $ig_count) . " new posts\n";
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n";
