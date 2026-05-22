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
