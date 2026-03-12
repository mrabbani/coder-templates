# WordPress Plugin Dev — Coder Workspace Template

A batteries-included [Coder](https://coder.com) workspace template for WordPress plugin development with **Claude Code** AI assistance.

---

## 🏗️ What's Included

| Service | URL | Purpose |
|---|---|---|
| WordPress | `http://localhost:8080` | Live dev site |
| WP Admin | `http://localhost:8080/wp-admin` | Dashboard (admin / admin) |
| VS Code | `http://localhost:8081` | Browser IDE |
| phpMyAdmin | `http://localhost:8082` | Database GUI |

### Tools pre-installed
- **PHP** (8.1 / 8.2 / 8.3 — your choice)
- **WP-CLI** — full WordPress management from the terminal
- **Composer** — PHP dependency management + PSR-4 autoloading
- **@wordpress/scripts** — official WP JS/CSS build toolchain
- **PHPUnit + WP_Mock** — unit testing
- **PHP_CodeSniffer + WPCS** — WordPress coding standards linting
- **Claude Code CLI** — AI pair-programmer in your terminal
- **code-server** — VS Code in the browser with PHP + WP extensions

---

## 🚀 Deploy to Coder

```bash
# 1. Clone this repo
git clone https://github.com/your-org/coder-wp-plugin-template
cd coder-wp-plugin-template

# 2. Push the template to your Coder instance
coder templates create wordpress-plugin \
  --directory . \
  --yes

# 3. Create a workspace
coder create my-plugin \
  --template wordpress-plugin \
  -p plugin_slug=my-awesome-plugin \
  -p plugin_name="My Awesome Plugin" \
  -p php_version=8.2

# 4. Open the workspace
coder open my-plugin
```

---

## 🤖 Claude Code Usage

Claude Code is available in the integrated terminal:

```bash
# Start interactive session
claude

# One-shot tasks
claude "add a REST API endpoint that returns all posts for this plugin"
claude "write a PHPUnit test for the Activator class"
claude "add a settings page with a text field and checkbox"
claude "implement WP_List_Table for my custom post type"

# Code review
claude "review my plugin for WordPress coding standards issues"
claude "check for security issues: missing nonces, unescaped output"
```

The `CLAUDE.md` file in your plugin root gives Claude context about your plugin's structure and conventions automatically.

---

## 📂 Plugin Structure

```
plugin/
├── {{PLUGIN_SLUG}}.php          # Main entry point & constants
├── composer.json                # PHP deps & scripts
├── package.json                 # JS/CSS build via @wordpress/scripts
├── phpunit.xml                  # Test configuration
├── CLAUDE.md                    # Claude Code project context  ← auto-generated
├── includes/                    # Core PHP (PSR-4 autoloaded)
│   ├── class-plugin.php         # Bootstraps hooks
│   ├── class-activator.php      # Activation: DB tables, defaults
│   └── class-deactivator.php    # Cleanup on deactivate
├── admin/
│   ├── class-admin.php          # Admin hooks, menus, settings
│   ├── views/                   # PHP templates for admin pages
│   ├── css/                     # Compiled admin CSS
│   └── js/                      # Compiled admin JS
├── public/
│   ├── class-public.php         # Front-end hooks
│   ├── css/
│   └── js/
├── src/                         # JS/SCSS source → compiled by wp-scripts
│   ├── index.js
│   └── style.scss
├── languages/                   # .pot / .po / .mo files
└── tests/                       # PHPUnit tests
    ├── bootstrap.php
    └── PluginTest.php
```

---

## 🛠️ Common Commands

```bash
# Asset development
npm run start          # Watch & rebuild on change
npm run build          # Production build

# Testing
composer test          # Run PHPUnit
composer lint          # Check WordPress coding standards
composer lint:fix      # Auto-fix coding standard issues

# WP-CLI
wp plugin list
wp post create --post_title="Test" --post_status=publish
wp user list
wp option get {{PLUGIN_SLUG}}_settings
wp cache flush

# Database
wp db export backup.sql
wp db import backup.sql
wp search-replace 'old-url' 'new-url'
```

---

## ⚙️ Template Parameters

| Parameter | Description | Default |
|---|---|---|
| `plugin_name` | Human-readable plugin name | My WordPress Plugin |
| `plugin_slug` | Lowercase hyphenated slug | my-wordpress-plugin |
| `php_version` | PHP version (8.1 / 8.2 / 8.3) | 8.2 |
| `wp_version` | WordPress version | latest |
| `claude_code` | Install Claude Code CLI | true |

---

## 🔑 Secrets / Environment Variables

Set these in your Coder deployment or workspace environment:

```bash
ANTHROPIC_API_KEY=sk-ant-...   # Required for Claude Code
```

In Coder admin: **Settings → Secrets** → add `ANTHROPIC_API_KEY`.

---

## 📋 WordPress Coding Standards Quick Reference

```php
// ✅ Always sanitize inputs
$value = sanitize_text_field( wp_unslash( $_POST['field'] ?? '' ) );
$id    = absint( $_GET['id'] ?? 0 );

// ✅ Always escape outputs  
echo esc_html( $title );
echo esc_url( $link );
echo esc_attr( $class );

// ✅ Use nonces for forms
wp_nonce_field( 'my-action', 'my-nonce' );
check_admin_referer( 'my-action', 'my-nonce' );

// ✅ Use $wpdb->prepare() for custom queries
$wpdb->get_results( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}my_table WHERE id = %d",
    $id
) );

// ✅ Prefix everything global
function my_plugin_helper() { ... }
add_action( 'init', 'my_plugin_helper' );
```

---

## 📄 License

GPL v2 or later — [https://www.gnu.org/licenses/gpl-2.0.html](https://www.gnu.org/licenses/gpl-2.0.html)
