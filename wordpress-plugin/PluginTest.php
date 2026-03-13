<?php
/**
 * Example plugin test.
 *
 * @package {{PLUGIN_CLASS}}\Tests
 */

namespace {{PLUGIN_CLASS}}\Tests;

use WP_Mock\Tools\TestCase;
use {{PLUGIN_CLASS}}\Plugin;

/**
 * Class PluginTest
 */
class PluginTest extends TestCase {

	public function setUp(): void {
		parent::setUp();
		\WP_Mock::setUp();
	}

	public function tearDown(): void {
		\WP_Mock::tearDown();
		parent::tearDown();
	}

	/** @test */
	public function plugin_class_exists(): void {
		$this->assertTrue( class_exists( Plugin::class ) );
	}

	/** @test */
	public function plugin_registers_hooks_on_run(): void {
		\WP_Mock::expectActionAdded( 'init', \WP_Mock\Functions::type( 'callable' ) );
		\WP_Mock::expectActionAdded( 'wp_enqueue_scripts', \WP_Mock\Functions::type( 'array' ) );

		$plugin = new Plugin();
		$plugin->run();

		$this->assertConditionsMet();
	}
}
