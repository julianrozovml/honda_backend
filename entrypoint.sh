#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "$1$2${NC}"; }
info() { log "$CYAN" "$1"; }
ok() { log "$GREEN" "$1"; }
warn() { log "$YELLOW" "$1"; }
fail() { log "$RED" "$1"; exit 1; }

APP_ROOT="/opt/drupal"
WEB_ROOT="$APP_ROOT/web"
SITE_DEFAULT="$WEB_ROOT/sites/default"
FILES_DIR="$SITE_DEFAULT/files"
SETTINGS="$SITE_DEFAULT/settings.php"
SETTINGS_LOCAL="$SITE_DEFAULT/settings.local.php"
CONFIG_DIR="$APP_ROOT/config/sync"
AUTHORIZED_KEYS="/root/.ssh/authorized_keys"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-drupal}"
DB_USER="${DB_USER:-drupal}"
DB_PASS="${DB_PASS:-drupal}"
APP_ENV="${APP_ENV:-production}"

mkdir -p /root/.ssh
chmod 700 /root/.ssh
: > "$AUTHORIZED_KEYS"

load_ssh_keys() {
  local key

  if [[ -n "${SSH_PUBLIC_KEYS:-}" ]]; then
    while IFS= read -r key; do
      key="$(echo "$key" | tr -d '\r' | xargs || true)"
      [[ -n "$key" ]] && echo "$key" >> "$AUTHORIZED_KEYS"
    done < <(printf '%b\n' "$SSH_PUBLIC_KEYS")
  fi

  while IFS='=' read -r var_name var_value; do
    if [[ "$var_name" == SSH_KEY_* ]] && [[ -n "$var_value" ]]; then
      key="$(echo "$var_value" | tr -d '\r' | xargs || true)"
      if [[ -n "$key" ]] && ! grep -qF "$key" "$AUTHORIZED_KEYS" 2>/dev/null; then
        echo "$key" >> "$AUTHORIZED_KEYS"
        ok "✅ SSH: ${var_name#SSH_KEY_}"
      fi
    fi
  done < <(env)

  if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
    key="$(echo "$SSH_PUBLIC_KEY" | tr -d '\r' | xargs || true)"
    [[ -n "$key" ]] && ! grep -qF "$key" "$AUTHORIZED_KEYS" 2>/dev/null && echo "$key" >> "$AUTHORIZED_KEYS"
  fi

  chmod 600 "$AUTHORIZED_KEYS"

  if [[ -s "$AUTHORIZED_KEYS" ]]; then
    local total
    total="$(grep -c 'ssh-' "$AUTHORIZED_KEYS" 2>/dev/null || echo 0)"
    ok "✅ SSH — $total llave(s) configurada(s)"
    /usr/sbin/sshd -p 2222
    ok "✅ SSH en puerto 2222"
  else
    warn "⚠️  Sin llaves SSH — acceso SSH deshabilitado"
  fi
}

prepare_directories() {
  mkdir -p "$FILES_DIR/translations" "$FILES_DIR/private" "$CONFIG_DIR"
  chown -R www-data:www-data "$FILES_DIR" "$CONFIG_DIR" || true
  chmod -R 775 "$FILES_DIR" "$CONFIG_DIR" || true
  ok "✅ Directorios persistentes listos"
}

ensure_settings() {
  chmod u+w "$SITE_DEFAULT" || true

  if [[ ! -f "$SETTINGS" ]] && [[ -f "$SITE_DEFAULT/default.settings.php" ]]; then
    cp "$SITE_DEFAULT/default.settings.php" "$SETTINGS"
    chmod 664 "$SETTINGS"
  fi

  if [[ -f "$SETTINGS" ]] && ! grep -q "settings.local.php" "$SETTINGS"; then
    chmod u+w "$SETTINGS" || true
    cat >> "$SETTINGS" <<'SETTINGS_INCLUDE'

if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
SETTINGS_INCLUDE
  fi

  cat > "$SETTINGS_LOCAL" <<EOF_LOCAL
<?php
/**
 * Auto-generado por entrypoint.sh.
 * No versionar este archivo.
 */

\$databases['default']['default'] = [
  'driver' => 'mysql',
  'database' => '${DB_NAME}',
  'username' => '${DB_USER}',
  'password' => '${DB_PASS}',
  'host' => '${DB_HOST}',
  'port' => '${DB_PORT}',
  'prefix' => '',
  'charset' => 'utf8mb4',
  'collation' => 'utf8mb4_general_ci',
  'namespace' => 'Drupal\\mysql\\Driver\\Database\\mysql',
  'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
];

\$settings['hash_salt'] = '${DRUPAL_HASH_SALT:-CHANGE_ME_IN_PRODUCTION}';
\$settings['file_public_path'] = 'sites/default/files';
\$settings['file_private_path'] = 'sites/default/files/private';
\$settings['config_sync_directory'] = '../config/sync';

\$settings['trusted_host_patterns'] = ['.*'];

\$settings['cors.config'] = [
  'enabled' => TRUE,
  'allowedHeaders' => ['*'],
  'allowedMethods' => ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  'allowedOrigins' => array_values(array_filter(array_map('trim', explode(',', '${CORS_ORIGINS:-http://localhost:3000}')))),
  'exposedHeaders' => FALSE,
  'maxAge' => FALSE,
  'supportsCredentials' => FALSE,
];

\$settings['reverse_proxy'] = TRUE;
\$settings['reverse_proxy_addresses'] = ['127.0.0.1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];

if ('${APP_ENV}' !== 'production') {
  \$settings['skip_permissions_hardening'] = TRUE;
}

define('APP_ENV', '${APP_ENV}');
EOF_LOCAL

  chmod 444 "$SETTINGS_LOCAL"
  ok "✅ settings.local.php generado"
}

wait_for_db() {
  local retries="${DB_WAIT_RETRIES:-60}"
  local delay="${DB_WAIT_DELAY:-2}"
  local i=1

  info "⏳ Esperando base de datos en ${DB_HOST}:${DB_PORT}..."
  until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --silent >/dev/null 2>&1; do
    if (( i >= retries )); then
      fail "❌ La base de datos no respondió después de ${retries} intentos"
    fi
    sleep "$delay"
    ((i++))
  done
  ok "✅ Base de datos disponible"
}

site_is_installed() {
  mysql -N -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
    -e "SHOW TABLES LIKE 'key_value';" 2>/dev/null | grep -q "key_value"
}

run_site_install() {
  local install_site="${INSTALL_SITE:-false}"
  local install_from_config="${INSTALL_FROM_CONFIG:-false}"
  local install_profile="${INSTALL_PROFILE:-standard}"
  local site_name="${SITE_NAME:-Honda Motoverso}"
  local site_mail="${SITE_MAIL:-admin@example.com}"
  local account_name="${ACCOUNT_NAME:-admin}"
  local account_mail="${ACCOUNT_MAIL:-admin@example.com}"
  local account_pass="${ACCOUNT_PASS:-admin123456}"

  if [[ "$install_site" != "true" ]]; then
    info "ℹ️  INSTALL_SITE=false — se omite instalación automática"
    return 0
  fi

  if site_is_installed; then
    ok "✅ Drupal ya está instalado"
    return 0
  fi

  info "🚀 Instalando Drupal automáticamente..."

  if [[ "$install_from_config" == "true" ]] && find "$CONFIG_DIR" -mindepth 1 -type f | read -r _; then
    vendor/bin/drush site:install --existing-config -y \
      --account-name="$account_name" \
      --account-pass="$account_pass" \
      --account-mail="$account_mail"
  else
    vendor/bin/drush site:install "$install_profile" -y \
      --site-name="$site_name" \
      --site-mail="$site_mail" \
      --account-name="$account_name" \
      --account-pass="$account_pass" \
      --account-mail="$account_mail"
  fi

  vendor/bin/drush cr -y || true
  ok "✅ Drupal instalado"
}

print_banner() {
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}  🚀 honda-motoverso arrancando...       ${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_banner
load_ssh_keys
prepare_directories
ensure_settings
wait_for_db
run_site_install

ok "✅ Entorno ${APP_ENV} listo"
exec "$@"
