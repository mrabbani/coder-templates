<?php
/**
 * Core plugin class.
 *
 * @package {{PLUGIN_CLASS}}
 */

namespace {{PLUGIN_CLASS}};

/**
 * Class Plugin
 *
 * Maintains the plugin version, unique identifier, and hooks together
 * the admin and public-facing functionality.
 */
class Plugin {

	/** @var string Plugin slug. */
	protected string $plugin_slug;

	/** @var string Plugin version. */
	protected string $version;

	/**
	 * Constructor.
	 */
	public function __construct() {
		$this->plugin_slug = {{PLUGIN_CLASS}}_SLUG;
		$this->version     = {{PLUGIN_CLASS}}_VERSION;
	}

	/**
	 * Register all hooks for admin and public areas.
	 */
	public function run(): void {
		$this->load_dependencies();
		$this->set_locale();
		$this->define_admin_hooks();
		$this->define_public_hooks();
	}

	/**
	 * Load required classes.
	 */
	private function load_dependencies(): void {
		// Dependencies are autoloaded via Composer.
	}

	/**
	 * Register i18n hooks.
	 */
	private function set_locale(): void {
		add_action( 'init', function () {
			load_plugin_textdomain(
				$this->plugin_slug,
				false,
				dirname( plugin_basename( {{PLUGIN_CLASS}}_FILE ) ) . '/languages/'
			);
		} );
	}

	/**
	 * Register admin-facing hooks.
	 */
	private function define_admin_hooks(): void {
		if ( ! is_admin() ) {
			return;
		}

		$admin = new Admin\AdminController( $this->plugin_slug, $this->version );
		add_action( 'admin_enqueue_scripts', [ $admin, 'enqueue_styles' ] );
		add_action( 'admin_enqueue_scripts', [ $admin, 'enqueue_scripts' ] );
		add_action( 'admin_menu',            [ $admin, 'add_menu_pages' ] );
	}

	/**
	 * Register public-facing hooks.
	 */
	private function define_public_hooks(): void {
		$front = new Frontend\FrontendController( $this->plugin_slug, $this->version );
		add_action( 'wp_enqueue_scripts', [ $front, 'enqueue_styles' ] );
		add_action( 'wp_enqueue_scripts', [ $front, 'enqueue_scripts' ] );
	}
}
