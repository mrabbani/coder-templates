<?php
/**
 * Fired during plugin activation.
 *
 * @package {{PLUGIN_CLASS}}
 */

namespace {{PLUGIN_CLASS}};

/**
 * Class Activator
 */
class Activator {

	/**
	 * Run on plugin activation.
	 *
	 * Create DB tables, set default options, flush rewrite rules, etc.
	 */
	public static function activate(): void {
		self::create_tables();
		self::set_defaults();
		flush_rewrite_rules();
	}

	/**
	 * Create custom database tables.
	 */
	private static function create_tables(): void {
		global $wpdb;

		$charset_collate = $wpdb->get_charset_collate();
		$table_name      = $wpdb->prefix . '{{PLUGIN_SLUG}}_data';

		$sql = "CREATE TABLE IF NOT EXISTS {$table_name} (
			id bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT,
			user_id bigint(20) UNSIGNED NOT NULL DEFAULT 0,
			data longtext NOT NULL,
			created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			KEY user_id (user_id)
		) {$charset_collate};";

		require_once ABSPATH . 'wp-admin/includes/upgrade.php';
		dbDelta( $sql );

		update_option( '{{PLUGIN_SLUG}}_db_version', {{PLUGIN_CLASS}}_VERSION );
	}

	/**
	 * Set default plugin options.
	 */
	private static function set_defaults(): void {
		$defaults = [
			'enabled'     => true,
			'setting_one' => 'default_value',
		];

		if ( ! get_option( '{{PLUGIN_SLUG}}_settings' ) ) {
			add_option( '{{PLUGIN_SLUG}}_settings', $defaults );
		}
	}
}
