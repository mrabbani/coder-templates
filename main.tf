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

data "coder_parameter" "plugin_name" {
  name         = "plugin_name"
  display_name = "Plugin Name"
  description  = "Your WordPress plugin's name (e.g. My Awesome Plugin)"
  default      = "My WordPress Plugin"
  mutable      = true
}

data "coder_parameter" "plugin_slug" {
  name         = "plugin_slug"
  display_name = "Plugin Slug"
  description  = "Lowercase, hyphenated plugin slug (e.g. my-wordpress-plugin)"
  default      = "my-wordpress-plugin"
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
  image   = "wordpress:${data.coder_parameter.wp_version.value}-php${data.coder_parameter.php_version.value}-apache"
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

  volumes {
    host_path      = "/home/${data.coder_workspace_owner.me.name}/workspace/plugin"
    container_path = "/var/www/html/wp-content/plugins/${data.coder_parameter.plugin_slug.value}"
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
    "PLUGIN_NAME=${data.coder_parameter.plugin_name.value}",
    "PLUGIN_SLUG=${data.coder_parameter.plugin_slug.value}",
    "WP_HOST=wp-${data.coder_workspace.me.id}",
    "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY",
  ]

  volumes {
    host_path      = "/home/${data.coder_workspace_owner.me.name}/workspace"
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
  startup_script = file("${path.module}/scripts/startup.sh")

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
