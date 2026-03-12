terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "coder" {}
provider "docker" {}

# ── Parameters ──────────────────────────────────────────────────────────────

data "coder_parameter" "plugins" {
  name         = "plugins"
  display_name = "Plugins (JSON)"
  description  = <<-DESC
    JSON array of plugins to clone and activate. Each entry needs:
      url    — git repo URL
      slug   — folder name in wp-content/plugins/
      branch — (optional) git branch, defaults to main
    Example:
    [
      {"url":"https://github.com/org/plugin-one","slug":"plugin-one","branch":"main"},
      {"url":"https://github.com/org/plugin-two","slug":"plugin-two","branch":"develop"}
    ]
  DESC
  default = jsonencode([
    {
      url    = "https://github.com/your-org/plugin-one"
      slug   = "plugin-one"
      branch = "main"
    }
  ])
  mutable = true
}

data "coder_parameter" "plugins_base_path" {
  name         = "plugins_base_path"
  display_name = "Plugins Base Path (Host)"
  description  = "Absolute path on the Coder server where your plugin repos are cloned (e.g. /home/ubuntu/plugins)"
  default      = "/home/ubuntu/plugins"
  mutable      = true
}

data "coder_parameter" "php_version" {
  name         = "php_version"
  display_name = "PHP Version"
  description  = "PHP version to use"
  default      = "8.2"
  mutable      = false
  option {
    name  = "PHP 8.1"
    value = "8.1"
  }
  option {
    name  = "PHP 8.2"
    value = "8.2"
  }
  option {
    name  = "PHP 8.3"
    value = "8.3"
  }
}

data "coder_parameter" "wp_version" {
  name         = "wp_version"
  display_name = "WordPress Version"
  description  = "WordPress version to install"
  default      = "latest"
  mutable      = true
}

data "coder_parameter" "claude_code" {
  name         = "claude_code"
  display_name = "Install Claude Code"
  description  = "Install Claude Code CLI for AI-assisted development"
  default      = "true"
  mutable      = false
  option {
    name  = "Yes"
    value = "true"
  }
  option {
    name  = "No"
    value = "false"
  }
}

# ── Workspace ────────────────────────────────────────────────────────────────

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ── Docker network ───────────────────────────────────────────────────────────

resource "docker_network" "wp_network" {
  name = "wp-${data.coder_workspace.me.id}"
}

# ── MySQL container ──────────────────────────────────────────────────────────

resource "docker_container" "mysql" {
  count   = data.coder_workspace.me.start_count
  image   = "mysql:8.0"
  name    = "mysql-${data.coder_workspace.me.id}"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.wp_network.name
  }

  env = [
    "MYSQL_ROOT_PASSWORD=wordpress",
    "MYSQL_DATABASE=wordpress",
    "MYSQL_USER=wordpress",
    "MYSQL_PASSWORD=wordpress",
  ]

  volumes {
    volume_name    = docker_volume.mysql_data.name
    container_path = "/var/lib/mysql"
  }
}

resource "docker_volume" "mysql_data" {
  name = "mysql-data-${data.coder_workspace.me.id}"
}

# ── WordPress container ──────────────────────────────────────────────────────

resource "docker_container" "wordpress" {
  count   = data.coder_workspace.me.start_count
  image   = (
    data.coder_parameter.wp_version.value == "latest"
    ? "wordpress:php${data.coder_parameter.php_version.value}-apache"
    : "wordpress:${data.coder_parameter.wp_version.value}-php${data.coder_parameter.php_version.value}-apache"
  )
  name    = "wp-${data.coder_workspace.me.id}"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.wp_network.name
  }

  env = [
    "WORDPRESS_DB_HOST=mysql-${data.coder_workspace.me.id}",
    "WORDPRESS_DB_USER=wordpress",
    "WORDPRESS_DB_PASSWORD=wordpress",
    "WORDPRESS_DB_NAME=wordpress",
    "WORDPRESS_DEBUG=1",
    "WORDPRESS_CONFIG_EXTRA=define('WP_DEBUG_LOG', true); define('WP_DEBUG_DISPLAY', false); define('SAVEQUERIES', true);",
  ]

  # Mount each plugin from host directly into wp-content/plugins/
  dynamic "volumes" {
    for_each = jsondecode(data.coder_parameter.plugins.value)
    content {
      host_path      = "${data.coder_parameter.plugins_base_path.value}/${volumes.value.slug}"
      container_path = "/var/www/html/wp-content/plugins/${volumes.value.slug}"
    }
  }

  ports {
    internal = 80
    external = 8080
  }
}

# ── Dev container ────────────────────────────────────────────────────────────

resource "docker_image" "dev" {
  name = "wp-dev-${data.coder_workspace.me.id}"
  build {
    context    = "${path.module}"
    dockerfile = "Dockerfile.dev"
    build_args = {
      PHP_VERSION    = data.coder_parameter.php_version.value
      CLAUDE_CODE    = data.coder_parameter.claude_code.value
    }
  }
  triggers = {
    dockerfile = filemd5("${path.module}/Dockerfile.dev")
  }
}

resource "docker_container" "dev" {
  count   = data.coder_workspace.me.start_count
  image   = docker_image.dev.image_id
  name    = "dev-${data.coder_workspace.me.id}"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.wp_network.name
  }

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    # JSON array of {url, slug, branch} objects — from workspace parameter
    "PLUGINS_JSON=${data.coder_parameter.plugins.value}",
    "WP_HOST=wp-${data.coder_workspace.me.id}",
    # Anthropic auth token — set in Coder Secrets as ANTHROPIC_TOKEN
    "ANTHROPIC_TOKEN=$ANTHROPIC_TOKEN",
    # Git token for private repos — set in Coder Secrets as GIT_TOKEN
    "GIT_TOKEN=$GIT_TOKEN",
  ]

  # Mount the entire plugins base path as the workspace root in the dev container
  volumes {
    host_path      = data.coder_parameter.plugins_base_path.value
    container_path = "/home/coder/workspace"
  }

  command = ["/bin/bash", "-c", coder_agent.main.init_script]
}

resource "docker_volume" "workspace" {
  name = "workspace-${data.coder_workspace.me.id}"
}

# ── Coder agent ──────────────────────────────────────────────────────────────

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    WORKSPACE="/home/coder/workspace"
    PLUGINS_JSON='$${PLUGINS_JSON:-[]}'

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  WordPress Multi-Plugin Dev Workspace"
    echo "  Plugins mounted from host via Docker volume"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! command -v jq &>/dev/null; then
      sudo apt-get install -y jq -qq
    fi

    PLUGIN_COUNT=$(echo "$PLUGINS_JSON" | jq 'length')
    echo "📦 $PLUGIN_COUNT plugin(s) mounted"

    # ── Install deps for each plugin (already on disk via host mount) ─────────
    SLUGS=()
    for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
      PLUGIN_SLUG=$(echo "$PLUGINS_JSON" | jq -r ".[$i].slug")
      PLUGIN_DIR="$WORKSPACE/$PLUGIN_SLUG"
      SLUGS+=("$PLUGIN_SLUG")

      echo ""
      echo "── $PLUGIN_SLUG ─────────────────────────────────────"

      if [ ! -d "$PLUGIN_DIR" ]; then
        echo "   ⚠️  Directory not found: $PLUGIN_DIR"
        echo "   Make sure the repo is cloned on the host at:"
        echo "   Check the plugins_base_path you set in workspace parameters"
        continue
      fi

      # Show current git branch/commit
      if [ -d "$PLUGIN_DIR/.git" ]; then
        BRANCH=$(git -C "$PLUGIN_DIR" branch --show-current 2>/dev/null || echo "unknown")
        COMMIT=$(git -C "$PLUGIN_DIR" log --oneline -1 2>/dev/null || echo "unknown")
        echo "   🌿 Branch: $BRANCH  |  $COMMIT"
      fi

      if [ -f "$PLUGIN_DIR/composer.json" ]; then
        echo "   📦 composer install..."
        cd "$PLUGIN_DIR" && composer install --no-interaction --prefer-dist -q
      fi

      if [ -f "$PLUGIN_DIR/package.json" ]; then
        echo "   📦 npm install..."
        cd "$PLUGIN_DIR" && npm install --silent
      fi

      echo "   ✅ ready"
    done

    # ── Configure git for all plugin dirs ────────────────────────────────────
    git config --global user.email "dev@coder.local"
    git config --global user.name "Coder Dev"

    if [ -n "$${GIT_TOKEN:-}" ]; then
      git config --global credential.helper store
      echo "$PLUGINS_JSON" | jq -r '.[].url // empty' \
        | sed -E 's|https://([^/]+)/.*|\1|' | sort -u \
        | while read -r HOST; do
            echo "https://oauth2:$${GIT_TOKEN}@$${HOST}" >> ~/.git-credentials
          done
      chmod 600 ~/.git-credentials
      echo "🔑 Git credentials configured"
    fi

    # ── Wait for MySQL ────────────────────────────────────────────────────────
    echo ""
    echo "⏳ Waiting for MySQL..."
    until mysqladmin ping -h"$${WP_HOST:-localhost}" --silent 2>/dev/null; do
      sleep 2
    done
    echo "✅ MySQL ready"

    echo "⏳ Waiting for WordPress..."
    sleep 5

    # ── Configure WP-CLI ─────────────────────────────────────────────────────
    mkdir -p ~/.wp-cli
    cat > ~/.wp-cli/config.yml <<WPCLIEOF
    path: /var/www/html
    url: http://localhost:8080
    user: admin
    WPCLIEOF

    # ── Install WordPress ─────────────────────────────────────────────────────
    echo "⚙️  Configuring WordPress..."
    wp --path=/var/www/html core install \
      --url="http://localhost:8080" \
      --title="Multi-Plugin Dev" \
      --admin_user=admin \
      --admin_password=admin \
      --admin_email=dev@local.test \
      --skip-email 2>/dev/null || echo "ℹ️  Already installed"

    # ── Activate each plugin (already mounted by Docker) ─────────────────────
    echo ""
    echo "🔌 Activating plugins..."
    for SLUG in "$${SLUGS[@]}"; do
      wp --path=/var/www/html plugin activate "$SLUG" 2>/dev/null \
        && echo "   ✅ $SLUG" \
        || echo "   ⚠️  $SLUG — check /var/www/html/wp-content/debug.log"
    done

    # ── Anthropic auth token ──────────────────────────────────────────────────
    if [ -n "$${ANTHROPIC_TOKEN:-}" ]; then
      mkdir -p ~/.config/anthropic
      cat > ~/.config/anthropic/auth.json <<AUTHEOF
    {
      "type": "token",
      "token": "$${ANTHROPIC_TOKEN}"
    }
    AUTHEOF
      chmod 600 ~/.config/anthropic/auth.json
      echo "🔑 Anthropic auth token configured"
    fi

    # ── Generate CLAUDE.md ────────────────────────────────────────────────────
    CLAUDE_MD="$WORKSPACE/CLAUDE.md"
    if [ ! -f "$CLAUDE_MD" ]; then
      {
        echo "# Claude Code — Multi-Plugin Workspace"
        echo ""
        echo "## Active Plugins"
        echo ""
        for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
          SLUG=$(echo "$PLUGINS_JSON"   | jq -r ".[$i].slug")
          URL=$(echo "$PLUGINS_JSON"    | jq -r ".[$i].url // \"(local)\"")
          BRANCH=$(echo "$PLUGINS_JSON" | jq -r ".[$i].branch // \"main\"")
          DIR="$WORKSPACE/$SLUG"
          MAIN_PHP=$(find "$DIR" -maxdepth 1 -name "*.php" \
            -exec grep -l "Plugin Name:" {} \; 2>/dev/null | head -1 || true)
          NAME=$([ -n "$MAIN_PHP" ] \
            && grep -i "Plugin Name:" "$MAIN_PHP" | sed 's/.*Plugin Name:[[:space:]]*//' | tr -d '\r' \
            || echo "$SLUG")
          echo "### $NAME (\`$SLUG\`)"
          echo "- Repo: $URL  branch: \`$BRANCH\`"
          echo "- Dir:  \`$DIR\`"
          echo "- Composer: $([ -f "$DIR/composer.json" ] && echo yes || echo no) | npm: $([ -f "$DIR/package.json" ] && echo yes || echo no) | Tests: $([ -d "$DIR/tests" ] && echo yes || echo no)"
          echo ""
        done
        echo "## Environment"
        echo "- PHP $(php -r 'echo PHP_VERSION;') + WordPress $(wp --path=/var/www/html core version 2>/dev/null || echo latest)"
        echo "- Plugins mounted directly from Coder host — edits are live instantly"
        echo "- Debug log: \`tail -f /var/www/html/wp-content/debug.log\`"
        echo ""
        echo "## Git Workflow (per plugin)"
        echo "\`\`\`bash"
        for SLUG in "$${SLUGS[@]}"; do
          echo "cd ~/workspace/$SLUG"
          echo "git pull && git add . && git commit -m 'feat: ...' && git push"
          echo ""
        done
        echo "\`\`\`"
      } > "$CLAUDE_MD"
      echo "✅ CLAUDE.md generated"
    fi

    # ── Start VS Code ─────────────────────────────────────────────────────────
    echo "🚀 Starting VS Code..."
    code-server \
      --bind-addr 0.0.0.0:8081 \
      --auth none \
      --disable-telemetry \
      "$WORKSPACE" &

    # ── Start phpMyAdmin ──────────────────────────────────────────────────────
    echo "🚀 Starting phpMyAdmin..."
    cat > /opt/phpmyadmin/config.inc.php <<PMAEOF
    <?php
    \$cfg['Servers'][1]['host']      = getenv('WP_HOST') ?: 'localhost';
    \$cfg['Servers'][1]['user']      = 'wordpress';
    \$cfg['Servers'][1]['password']  = 'wordpress';
    \$cfg['Servers'][1]['auth_type'] = 'config';
    \$cfg['blowfish_secret']         = 'coder-dev-secret-change-me';
    PMAEOF
    php -S 0.0.0.0:8082 -t /opt/phpmyadmin/ &>/tmp/phpmyadmin.log &

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ Workspace ready!"
    echo ""
    echo "  🌐 WordPress:  http://localhost:8080"
    echo "  👤 WP Admin:   http://localhost:8080/wp-admin  (admin / admin)"
    echo "  💻 VS Code:    http://localhost:8081"
    echo "  🗄️  phpMyAdmin: http://localhost:8082"
    echo ""
    echo "  📂 Plugins (host-mounted, live editing):"
    for SLUG in "$${SLUGS[@]}"; do
      echo "     ~/workspace/$SLUG"
    done
    echo ""
    echo "  🤖 Claude:  claude  (from any plugin dir)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  EOT

  metadata {
    display_name = "PHP Version"
    key          = "php_version"
    script       = "php --version | head -1"
    interval     = 60
    timeout      = 5
  }

  metadata {
    display_name = "WP-CLI Version"
    key          = "wpcli_version"
    script       = "wp --version 2>/dev/null || echo 'not ready'"
    interval     = 60
    timeout      = 5
  }

  metadata {
    display_name = "Plugin Tests"
    key          = "test_status"
    script       = "cd ~/workspace/plugin && composer test 2>&1 | tail -1 || echo 'no tests yet'"
    interval     = 120
    timeout      = 30
  }
}

# ── Apps ─────────────────────────────────────────────────────────────────────

resource "coder_app" "wordpress" {
  agent_id     = coder_agent.main.id
  slug         = "wordpress"
  display_name = "WordPress Site"
  url          = "http://localhost:8080"
  icon         = "/icon/wordpress.svg"
  share        = "owner"
  subdomain    = true
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code (Browser)"
  url          = "http://localhost:8081?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  share        = "owner"
  subdomain    = true
}

resource "coder_app" "phpmyadmin" {
  agent_id     = coder_agent.main.id
  slug         = "phpmyadmin"
  display_name = "phpMyAdmin"
  url          = "http://localhost:8082"
  icon         = "/icon/database.svg"
  share        = "owner"
  subdomain    = true
}
