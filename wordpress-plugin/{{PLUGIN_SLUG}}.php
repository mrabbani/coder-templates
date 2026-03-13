<?php
/**
 * Plugin Name:       {{PLUGIN_NAME}}
 * Plugin URI:        https://example.com/plugins/{{PLUGIN_SLUG}}
 * Description:       A WordPress plugin scaffold ready for development.
 * Version:           1.0.0
 * Requires at least: 6.0
 * Requires PHP:      8.1
 * Author:            Your Name
 * Author URI:        https://example.com
 * License:           GPL v2 or later
 * License URI:       https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain:       {{PLUGIN_SLUG}}
 * Domain Path:       /languages
 *
 * @package {{PLUGIN_CLASS}}
 */

// Prevent direct access.
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

// Plugin constants.
define( '{{PLUGIN_CLASS}}_VERSION', '1.0.0' );
define( '{{PLUGIN_CLASS}}_FILE',    __FILE__ );
define( '{{PLUGIN_CLASS}}_DIR',     plugin_dir_path( __FILE__ ) );
define( '{{PLUGIN_CLASS}}_URL',     plugin_dir_url( __FILE__ ) );
define( '{{PLUGIN_CLASS}}_SLUG',    '{{PLUGIN_SLUG}}' );

// Autoloader.
require_once {{PLUGIN_CLASS}}_DIR . 'vendor/autoload.php';

/**
 * Activation hook.
 */
function {{PLUGIN_SLUG}}_activate(): void {
	\{{PLUGIN_CLASS}}\Activator::activate();
}
register_activation_hook( __FILE__, '{{PLUGIN_SLUG}}_activate' );

/**
 * Deactivation hook.
 */
function {{PLUGIN_SLUG}}_deactivate(): void {
	\{{PLUGIN_CLASS}}\Deactivator::deactivate();
}
register_deactivation_hook( __FILE__, '{{PLUGIN_SLUG}}_deactivate' );

/**
 * Bootstrap the plugin.
 */
function {{PLUGIN_SLUG}}_run(): void {
	$plugin = new \{{PLUGIN_CLASS}}\Plugin();
	$plugin->run();
}
add_action( 'plugins_loaded', '{{PLUGIN_SLUG}}_run' );
