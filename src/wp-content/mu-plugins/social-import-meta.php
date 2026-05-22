<?php
/**
 * Plugin Name: Social Import Infrastructure
 * Description: Custom Post Type + Meta fields cho Social Media → WordPress auto-sync.
 *              Đăng ký CPT "social_post" với REST API support, meta fields cho duplicate
 *              prevention, và custom query parameter cho n8n workflow.
 * Version:     1.0.0
 * Author:      LaunchPad WP Stack
 * License:     MIT
 */

declare(strict_types=1);

// Prevent direct access.
defined('ABSPATH') || exit;

// Removed Custom Post Type: social_post. We now use standard "post".

// =============================================================================
// 2. Meta Fields (REST-accessible, for duplicate prevention)
// =============================================================================

add_action('rest_api_init', function (): void {
    /** @var array<string, array{type: string, desc: string, sanitize: string}> */
    $meta_fields = [
        '_social_original_id' => [
            'type'     => 'string',
            'desc'     => 'Original post ID from the social platform',
            'sanitize' => 'sanitize_text_field',
        ],
        '_social_platform' => [
            'type'     => 'string',
            'desc'     => 'Source platform: facebook | instagram',
            'sanitize' => 'sanitize_text_field',
        ],
        '_social_source_url' => [
            'type'     => 'string',
            'desc'     => 'Permalink to the original post on the social platform',
            'sanitize' => 'esc_url_raw',
        ],
        '_social_imported_at' => [
            'type'     => 'string',
            'desc'     => 'ISO 8601 timestamp of when this post was imported',
            'sanitize' => 'sanitize_text_field',
        ],
        '_social_media_count' => [
            'type'     => 'integer',
            'desc'     => 'Number of images imported with this post',
            'sanitize' => 'absint',
        ],
    ];

    foreach ($meta_fields as $key => $config) {
        register_post_meta('post', $key, [
            'show_in_rest'      => true,
            'single'            => true,
            'type'              => $config['type'],
            'description'       => $config['desc'],
            'sanitize_callback' => $config['sanitize'],
            'auth_callback'     => function (): bool {
                return current_user_can('edit_posts');
            },
        ]);
    }

    // -----------------------------------------------------------------
    // Convenience REST field: source_info (aggregates all social meta)
    // GET /wp/v2/posts → each item includes "source_info" object
    // -----------------------------------------------------------------
    register_rest_field('post', 'source_info', [
        'get_callback' => function (array $post): array {
            $id = $post['id'];
            return [
                'original_id' => get_post_meta($id, '_social_original_id', true),
                'platform'    => get_post_meta($id, '_social_platform', true),
                'source_url'  => get_post_meta($id, '_social_source_url', true),
                'imported_at' => get_post_meta($id, '_social_imported_at', true),
                'media_count' => (int) get_post_meta($id, '_social_media_count', true),
            ];
        },
        'schema' => [
            'type'        => 'object',
            'description' => 'Aggregated social media source information',
            'properties'  => [
                'original_id' => ['type' => 'string'],
                'platform'    => ['type' => 'string'],
                'source_url'  => ['type' => 'string'],
                'imported_at' => ['type' => 'string'],
                'media_count' => ['type' => 'integer'],
            ],
        ],
    ]);
});

// =============================================================================
// 3. Custom REST Query: ?social_original_id=XXX (for duplicate checking)
// =============================================================================

add_filter('rest_post_query', function (array $args, WP_REST_Request $request): array {
    $social_id = $request->get_param('social_original_id');

    if (is_string($social_id) && $social_id !== '') {
        $args['meta_query'] = [
            [
                'key'   => '_social_original_id',
                'value' => sanitize_text_field($social_id),
            ],
        ];
    }

    return $args;
}, 10, 2);

// Register the query param so WP REST validates it.
add_filter('rest_post_collection_params', function (array $params): array {
    $params['social_original_id'] = [
        'description' => 'Filter by original social media post ID (for duplicate checking)',
        'type'        => 'string',
        'required'    => false,
    ];
    return $params;
});

// =============================================================================
// 4. Auto-cleanup attached media when post is deleted
// =============================================================================

add_action('before_delete_post', function (int $post_id): void {
    // Only target posts that were imported from social platforms
    $original_id = get_post_meta($post_id, '_social_original_id', true);
    if (!empty($original_id)) {
        $attachments = get_attached_media('', $post_id);
        if (!empty($attachments)) {
            foreach ($attachments as $attachment) {
                // Force delete the attachment (true skips trash and deletes the physical file)
                wp_delete_attachment($attachment->ID, true);
            }
        }
    }
});

// =============================================================================
// 5. Fix Flatsome Customizer Icon Layout Compatibility with WP 6.7+
// =============================================================================

add_action('customize_controls_print_styles', function (): void {
    ?>
    <style id="flatsome-customizer-wp67-fix">
        /* 1. Ensure parent container is relative */
        #customize-theme-controls > ul > li > h3.accordion-section-title,
        #customize-theme-controls > ul > li .panel-meta.customize-info,
        #customize-theme-controls > ul > li .accordion-section-title {
            position: relative !important;
        }

        /* 2. Position the before-pseudo-elements (icons) absolutely */
        #customize-theme-controls > ul > li > h3.accordion-section-title:before,
        #customize-theme-controls > ul > li .panel-meta.customize-info .panel-title:before,
        #customize-theme-controls > ul > li .accordion-section-title:before,
        #customize-theme-controls > ul > li .panel-title:before {
            position: absolute !important;
            left: 14px !important;
            top: 50% !important;
            transform: translateY(-50%) !important;
            z-index: 10 !important;
            margin: 0 !important;
            pointer-events: none !important;
            line-height: 1 !important;
            display: inline-block !important;
            opacity: 0.7 !important;
            transition: opacity 0.2s ease-in-out !important;
        }

        /* 3. Increase padding-left on the buttons/titles to fit the icon */
        #customize-theme-controls > ul > li > h3.accordion-section-title button.accordion-trigger,
        #customize-theme-controls > ul > li .panel-meta.customize-info .panel-title,
        #customize-theme-controls > ul > li .accordion-section-title button.accordion-trigger,
        #customize-theme-controls > ul > li .panel-title {
            padding-left: 42px !important;
        }

        /* 4. Hover effect on list items should make icons more opaque */
        #customize-theme-controls > ul > li:hover > h3.accordion-section-title:before,
        #customize-theme-controls > ul > li:hover .panel-title:before {
            opacity: 1 !important;
        }
    </style>
    <?php
}, 99);


