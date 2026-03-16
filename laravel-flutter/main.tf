terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "coder" {}
provider "docker" {}

# ── Variables (secrets — set at template level) ──────────────────────────────

variable "git_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Git personal access token for cloning private repos"
}

# ── Parameters ───────────────────────────────────────────────────────────────

data "coder_parameter" "laravel_repo_url" {
  name         = "laravel_repo_url"
  display_name = "Laravel Repo URL"
  description  = "HTTPS URL of the Laravel backend repository"
  default      = ""
  mutable      = true
}

data "coder_parameter" "laravel_repo_branch" {
  name         = "laravel_repo_branch"
  display_name = "Laravel Branch"
  description  = "Branch to clone for the Laravel project"
  default      = "main"
  mutable      = true
}

data "coder_parameter" "flutter_repo_url" {
  name         = "flutter_repo_url"
  display_name = "Flutter Repo URL"
  description  = "HTTPS URL of the Flutter app repository"
  default      = ""
  mutable      = true
}

data "coder_parameter" "flutter_repo_branch" {
  name         = "flutter_repo_branch"
  display_name = "Flutter Branch"
  description  = "Branch to clone for the Flutter project"
  default      = "main"
  mutable      = true
}

data "coder_parameter" "project_base_path" {
  name         = "project_base_path"
  display_name = "Project Base Path (Host)"
  description  = "Absolute path on Coder server where projects are stored"
  default      = "/home/ubuntu/laravel-flutter-projects"
  mutable      = true
}

data "coder_parameter" "agent_arch" {
  name         = "agent_arch"
  display_name = "Agent Architecture"
  default      = "amd64"
  mutable      = false
  option {
    name  = "amd64 (Intel/AMD)"
    value = "amd64"
  }
  option {
    name  = "arm64 (Graviton)"
    value = "arm64"
  }
}

data "coder_parameter" "php_version" {
  name         = "php_version"
  display_name = "PHP Version"
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

data "coder_parameter" "flutter_channel" {
  name         = "flutter_channel"
  display_name = "Flutter Channel"
  default      = "stable"
  mutable      = false
  option {
    name  = "Stable"
    value = "stable"
  }
  option {
    name  = "Beta"
    value = "beta"
  }
  option {
    name  = "Dev"
    value = "dev"
  }
}

data "coder_parameter" "java_version" {
  name         = "java_version"
  display_name = "Java/JDK Version"
  default      = "17"
  mutable      = false
  option {
    name  = "JDK 17"
    value = "17"
  }
  option {
    name  = "JDK 21"
    value = "21"
  }
}

# ── Workspace ────────────────────────────────────────────────────────────────

data "coder_workspace"       "me" {}
data "coder_workspace_owner" "me" {}

# ── Random secret for phpMyAdmin ─────────────────────────────────────────────

resource "random_string" "blowfish_secret" {
  length  = 32
  special = false
}

# ── Docker network ────────────────────────────────────────────────────────────

resource "docker_network" "app_network" {
  name     = "laravel-flutter-${data.coder_workspace.me.id}"
  ipv6     = false
  internal = false
}

# ── Volumes ──────────────────────────────────────────────────────────────────

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_volume" "claude_config" {
  name = "claude-config-${data.coder_workspace.me.id}"
}

resource "docker_volume" "mysql_data" {
  name = "mysql-data-${data.coder_workspace.me.id}"
}

resource "docker_volume" "redis_data" {
  name = "redis-data-${data.coder_workspace.me.id}"
}

# ── MySQL ─────────────────────────────────────────────────────────────────────

resource "docker_container" "mysql" {
  count   = data.coder_workspace.me.start_count
  image   = "mysql:8.0"
  name    = "mysql-${data.coder_workspace.me.id}"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.app_network.name
  }

  env = [
    "MYSQL_ROOT_PASSWORD=laravel",
    "MYSQL_DATABASE=laravel",
    "MYSQL_USER=laravel",
    "MYSQL_PASSWORD=laravel",
  ]

  volumes {
    volume_name    = docker_volume.mysql_data.name
    container_path = "/var/lib/mysql"
  }
}

# ── Redis ─────────────────────────────────────────────────────────────────────

resource "docker_container" "redis" {
  count   = data.coder_workspace.me.start_count
  image   = "redis:7-alpine"
  name    = "redis-${data.coder_workspace.me.id}"
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.app_network.name
  }

  volumes {
    volume_name    = docker_volume.redis_data.name
    container_path = "/data"
  }
}

# ── Dev container ─────────────────────────────────────────────────────────────

resource "docker_image" "dev" {
  name = "laravel-flutter-dev-${data.coder_workspace.me.id}"
  build {
    context    = path.module
    dockerfile = "Dockerfile.dev"
    build_args = {
      PHP_VERSION     = data.coder_parameter.php_version.value
      FLUTTER_CHANNEL = data.coder_parameter.flutter_channel.value
      JAVA_VERSION    = data.coder_parameter.java_version.value
    }
  }
  triggers = {
    dockerfile      = filemd5("${path.module}/Dockerfile.dev")
    php_version     = data.coder_parameter.php_version.value
    flutter_channel = data.coder_parameter.flutter_channel.value
    java_version    = data.coder_parameter.java_version.value
  }
}

resource "docker_container" "dev" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.dev.image_id
  name     = "dev-${data.coder_workspace.me.id}"
  hostname = data.coder_workspace.me.name
  restart  = "unless-stopped"

  networks_advanced {
    name = docker_network.app_network.name
  }

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "MYSQL_HOST=mysql-${data.coder_workspace.me.id}",
    "REDIS_HOST=redis-${data.coder_workspace.me.id}",
    "GIT_TOKEN=${var.git_token}",
    "LARAVEL_REPO_URL=${data.coder_parameter.laravel_repo_url.value}",
    "LARAVEL_REPO_BRANCH=${data.coder_parameter.laravel_repo_branch.value}",
    "FLUTTER_REPO_URL=${data.coder_parameter.flutter_repo_url.value}",
    "FLUTTER_REPO_BRANCH=${data.coder_parameter.flutter_repo_branch.value}",
    "BLOWFISH_SECRET=${random_string.blowfish_secret.result}",
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # Persist entire home directory
  volumes {
    volume_name    = docker_volume.home_volume.name
    container_path = "/home/coder"
    read_only      = false
  }

  # Mount project from host path
  volumes {
    host_path      = data.coder_parameter.project_base_path.value
    container_path = "/home/coder/workspace"
  }

  # Claude Code config — persist login across restarts
  volumes {
    volume_name    = docker_volume.claude_config.name
    container_path = "/home/coder/.claude"
  }

  # Docker socket
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
}

# ── Coder agent ───────────────────────────────────────────────────────────────

resource "coder_agent" "main" {
  arch = data.coder_parameter.agent_arch.value
  os   = "linux"
  dir  = "/home/coder/workspace"

  startup_script = <<-EOT
#!/usr/bin/env bash
# NO set -e — script must survive errors or agent disconnects
set -uo pipefail

WORKSPACE="/home/coder/workspace"
LARAVEL_DIR="$WORKSPACE/backend"
FLUTTER_DIR="$WORKSPACE/mobile"

# Prepare user home with default files on first start
if [ ! -f ~/.init_done ]; then
  cp -rT /etc/skel ~ 2>/dev/null || true
  touch ~/.init_done
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Laravel + Flutter Full-Stack Workspace"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 0: Fix permissions on mounted volumes
sudo chown -R coder:coder "$WORKSPACE" 2>/dev/null || true
sudo chown -R coder:coder /home/coder/.claude 2>/dev/null || true

# Step 1: Docker socket permissions
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

# Step 2: Git config
git config --global user.email "dev@coder.local"
git config --global user.name  "Coder Dev"

if [ -n "$${GIT_TOKEN:-}" ]; then
  git config --global credential.helper store
  for URL in "$${LARAVEL_REPO_URL:-}" "$${FLUTTER_REPO_URL:-}"; do
    if [ -n "$URL" ]; then
      HOST=$(echo "$URL" | sed -E 's|https://([^/]+)/.*|\1|')
      grep -q "$HOST" ~/.git-credentials 2>/dev/null || \
        echo "https://oauth2:$${GIT_TOKEN}@$${HOST}" >> ~/.git-credentials
    fi
  done
  chmod 600 ~/.git-credentials 2>/dev/null || true
  echo "Git credentials configured"
fi

# ── Laravel Backend ──────────────────────────────────────────────────────────

LARAVEL_REPO_URL="$${LARAVEL_REPO_URL:-}"
LARAVEL_REPO_BRANCH="$${LARAVEL_REPO_BRANCH:-main}"

if [ -n "$LARAVEL_REPO_URL" ]; then
  mkdir -p "$LARAVEL_DIR"

  if [ ! -d "$LARAVEL_DIR/.git" ]; then
    echo "Cloning Laravel repo: $LARAVEL_REPO_URL (branch: $LARAVEL_REPO_BRANCH)..."
    TMPDIR=$(mktemp -d)
    git clone --branch "$LARAVEL_REPO_BRANCH" --single-branch "$LARAVEL_REPO_URL" "$TMPDIR" 2>&1 | tail -5 || {
      echo "FAILED to clone Laravel repo"
      rm -rf "$TMPDIR"
    }
    if [ -d "$TMPDIR/.git" ]; then
      shopt -s dotglob
      mv "$TMPDIR"/* "$LARAVEL_DIR/" 2>/dev/null || true
      shopt -u dotglob
      rm -rf "$TMPDIR"
      echo "Laravel repo cloned"
    fi
  else
    CUR_BRANCH=$(git -C "$LARAVEL_DIR" branch --show-current 2>/dev/null || echo "detached")
    echo "Pulling latest Laravel ($CUR_BRANCH)..."
    git -C "$LARAVEL_DIR" pull --ff-only 2>&1 | tail -3 || echo "Pull failed (may have local changes)"
  fi

  # Composer install
  if [ -f "$LARAVEL_DIR/composer.json" ]; then
    echo "Running composer install (backend)..."
    (cd "$LARAVEL_DIR" && composer install --no-interaction --prefer-dist -q 2>&1 | tail -5) || true
  fi

  # NPM install
  if [ -f "$LARAVEL_DIR/package.json" ]; then
    echo "Running npm install (backend)..."
    (cd "$LARAVEL_DIR" && npm install --silent 2>&1 | tail -5) || true
  fi

  # Laravel .env setup
  if [ -f "$LARAVEL_DIR/.env.example" ] && [ ! -f "$LARAVEL_DIR/.env" ]; then
    echo "Copying .env.example to .env..."
    cp "$LARAVEL_DIR/.env.example" "$LARAVEL_DIR/.env"

    sed -i "s|^DB_HOST=.*|DB_HOST=$${MYSQL_HOST}|"           "$LARAVEL_DIR/.env"
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=laravel|"           "$LARAVEL_DIR/.env"
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=laravel|"           "$LARAVEL_DIR/.env"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=laravel|"           "$LARAVEL_DIR/.env"
    sed -i "s|^REDIS_HOST=.*|REDIS_HOST=$${REDIS_HOST}|"     "$LARAVEL_DIR/.env"
    sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=redis|"          "$LARAVEL_DIR/.env" 2>/dev/null || true
    sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|"      "$LARAVEL_DIR/.env" 2>/dev/null || true

    echo ".env configured"
  fi

  # Generate app key if missing
  if [ -f "$LARAVEL_DIR/artisan" ]; then
    APP_KEY=$(grep "^APP_KEY=" "$LARAVEL_DIR/.env" 2>/dev/null | cut -d= -f2)
    if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "" ]; then
      echo "Generating application key..."
      (cd "$LARAVEL_DIR" && php artisan key:generate --force) || true
    fi
  fi
else
  echo "No Laravel repo URL configured — skipping backend setup"
fi

# ── Wait for MySQL ───────────────────────────────────────────────────────────
echo ""
echo "Waiting for MySQL ($${MYSQL_HOST:-localhost})..."
T=0
until mysqladmin ping -h"$${MYSQL_HOST:-localhost}" -u laravel -plaravel --silent 2>/dev/null; do
  T=$((T+1)); [ $T -ge 30 ] && echo "MySQL timeout" && break; sleep 3
done
echo "MySQL ready"

# Run migrations
if [ -f "$LARAVEL_DIR/artisan" ]; then
  echo "Running migrations..."
  (cd "$LARAVEL_DIR" && php artisan migrate --force 2>&1 | tail -5) || true
fi

# ── Flutter Mobile ───────────────────────────────────────────────────────────

FLUTTER_REPO_URL="$${FLUTTER_REPO_URL:-}"
FLUTTER_REPO_BRANCH="$${FLUTTER_REPO_BRANCH:-main}"

if [ -n "$FLUTTER_REPO_URL" ]; then
  mkdir -p "$FLUTTER_DIR"

  if [ ! -d "$FLUTTER_DIR/.git" ]; then
    echo "Cloning Flutter repo: $FLUTTER_REPO_URL (branch: $FLUTTER_REPO_BRANCH)..."
    TMPDIR=$(mktemp -d)
    git clone --branch "$FLUTTER_REPO_BRANCH" --single-branch "$FLUTTER_REPO_URL" "$TMPDIR" 2>&1 | tail -5 || {
      echo "FAILED to clone Flutter repo"
      rm -rf "$TMPDIR"
    }
    if [ -d "$TMPDIR/.git" ]; then
      shopt -s dotglob
      mv "$TMPDIR"/* "$FLUTTER_DIR/" 2>/dev/null || true
      shopt -u dotglob
      rm -rf "$TMPDIR"
      echo "Flutter repo cloned"
    fi
  else
    CUR_BRANCH=$(git -C "$FLUTTER_DIR" branch --show-current 2>/dev/null || echo "detached")
    echo "Pulling latest Flutter ($CUR_BRANCH)..."
    git -C "$FLUTTER_DIR" pull --ff-only 2>&1 | tail -3 || echo "Pull failed (may have local changes)"
  fi

  # Flutter pub get
  if [ -f "$FLUTTER_DIR/pubspec.yaml" ]; then
    echo "Running flutter pub get..."
    (cd "$FLUTTER_DIR" && flutter pub get 2>&1 | tail -5) || true
  fi
else
  echo "No Flutter repo URL configured — skipping mobile setup"
fi

# Flutter doctor
echo ""
echo "Running flutter doctor..."
flutter doctor 2>&1 || true

# ── CLAUDE.md ────────────────────────────────────────────────────────────────
CLAUDE_MD="$WORKSPACE/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ]; then
  {
    echo "# Claude Code - Laravel + Flutter Workspace"
    echo ""
    echo "## Project Structure"
    echo "- \`backend/\` — Laravel API (PHP)"
    echo "- \`mobile/\` — Flutter app (Dart)"
    echo ""
    echo "## Services"
    echo "- MySQL: $${MYSQL_HOST} (user: laravel, pass: laravel, db: laravel)"
    echo "- Redis: $${REDIS_HOST}"
    echo ""
    echo "## Backend Commands (cd backend/)"
    echo '```'
    echo "php artisan serve --host=0.0.0.0 --port=8000"
    echo "php artisan migrate"
    echo "php artisan tinker"
    echo "php artisan test"
    echo "composer require <package>"
    echo "npm run dev"
    echo '```'
    echo ""
    echo "## Mobile Commands (cd mobile/)"
    echo '```'
    echo "flutter pub get"
    echo "flutter run"
    echo "flutter build apk"
    echo "flutter test"
    echo "flutter analyze"
    echo "dart format ."
    echo '```'
  } > "$CLAUDE_MD"
  echo "CLAUDE.md generated"
fi

# ── Start Laravel dev server ─────────────────────────────────────────────────
if [ -f "$LARAVEL_DIR/artisan" ]; then
  echo "Starting Laravel dev server on port 8000..."
  (cd "$LARAVEL_DIR" && php artisan serve --host=0.0.0.0 --port=8000 >/tmp/laravel-serve.log 2>&1) &
fi

# ── Start VS Code ────────────────────────────────────────────────────────────
echo "Starting VS Code..."
code-server \
  --bind-addr 127.0.0.1:8081 \
  --auth none \
  --disable-telemetry \
  "$WORKSPACE" >/tmp/code-server.log 2>&1 &

# ── Start phpMyAdmin ─────────────────────────────────────────────────────────
echo "Starting phpMyAdmin..."
sudo tee /opt/phpmyadmin/config.inc.php >/dev/null <<PMAEOF
<?php
\$cfg['Servers'][1]['host']      = getenv('MYSQL_HOST') ?: 'localhost';
\$cfg['Servers'][1]['user']      = 'laravel';
\$cfg['Servers'][1]['password']  = 'laravel';
\$cfg['Servers'][1]['auth_type'] = 'config';
\$cfg['blowfish_secret']         = '$${BLOWFISH_SECRET:-coder-dev-fallback-secret}';
PMAEOF
php -S 127.0.0.1:8082 -t /opt/phpmyadmin/ >/tmp/phpmyadmin.log 2>&1 &

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DONE — use app buttons in Coder dashboard"
echo ""
echo "  Laravel API:  http://localhost:8000"
echo "  VS Code:      http://localhost:8081"
echo "  phpMyAdmin:   http://localhost:8082"
echo "  Claude:       claude"
echo ""
echo "  backend/  — Laravel API"
echo "  mobile/   — Flutter app"
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
    display_name = "Laravel Version"
    key          = "laravel_version"
    script       = "cd /home/coder/workspace/backend && php artisan --version 2>/dev/null || echo 'not installed'"
    interval     = 60
    timeout      = 10
  }

  metadata {
    display_name = "Flutter Version"
    key          = "flutter_version"
    script       = "flutter --version | head -1"
    interval     = 60
    timeout      = 10
  }

  metadata {
    display_name = "Dart Version"
    key          = "dart_version"
    script       = "dart --version 2>&1"
    interval     = 60
    timeout      = 5
  }
}

# ── Apps ──────────────────────────────────────────────────────────────────────

resource "coder_app" "laravel" {
  agent_id     = coder_agent.main.id
  slug         = "laravel"
  display_name = "Laravel API"
  url          = "http://127.0.0.1:8000"
  icon         = "/icon/php.svg"
  share        = "owner"
  subdomain    = true
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://127.0.0.1:8081?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  share        = "owner"
  subdomain    = true
}

resource "coder_app" "phpmyadmin" {
  agent_id     = coder_agent.main.id
  slug         = "phpmyadmin"
  display_name = "phpMyAdmin"
  url          = "http://127.0.0.1:8082"
  icon         = "/icon/database.svg"
  share        = "owner"
  subdomain    = true
}
