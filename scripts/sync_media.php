<?php
// Script để import media an toàn, không trùng lặp
if ( 'cli' !== php_sapi_name() ) {
    die('This script can only be run via WP-CLI.');
}

require_once( ABSPATH . 'wp-admin/includes/media.php' );
require_once( ABSPATH . 'wp-admin/includes/file.php' );
require_once( ABSPATH . 'wp-admin/includes/image.php' );

$staging_dir = '/var/www/html/wp-content/uploads/wp_media_staging';

if (!is_dir($staging_dir)) {
    die("Staging directory not found: $staging_dir\n");
}

$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($staging_dir));
$imported_count = 0;
$skipped_count = 0;

global $wpdb;

foreach ($iterator as $file) {
    if ($file->isFile()) {
        $filepath = $file->getPathname();
        $filename = $file->getFilename();
        
        $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
        if (!in_array($ext, ['jpg', 'jpeg', 'png', 'gif', 'mp4', 'webp', 'svg'])) {
            continue;
        }

        // Kiểm tra xem filename này đã có trong database chưa
        $query = $wpdb->prepare("SELECT post_id FROM {$wpdb->postmeta} WHERE meta_key = '_wp_attached_file' AND meta_value LIKE %s", '%' . $wpdb->esc_like($filename));
        $exists = $wpdb->get_var($query);

        if ($exists) {
            $skipped_count++;
            echo "SKIPPED (Already exists): $filename\n";
            unlink($filepath);
        } else {
            echo "IMPORTING: $filename...\n";
            
            $file_array = array(
                'name' => $filename,
                'tmp_name' => $filepath
            );

            // Sideload the image
            $id = media_handle_sideload( $file_array, 0 );

            if ( is_wp_error( $id ) ) {
                echo "ERROR importing $filename: " . $id->get_error_message() . "\n";
            } else {
                $imported_count++;
                echo "SUCCESS: $filename (ID: $id)\n";
            }
        }
    }
}

echo "\n--- SUMMARY ---\n";
echo "Imported: $imported_count files\n";
echo "Skipped: $skipped_count files\n";
