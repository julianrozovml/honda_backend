#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  🚀 honda-motoverso arrancando...     ${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ═══════════════════════════════════════════
# 0. Cliente MariaDB/MySQL sin SSL
#    Necesario para drush sqlc y conexiones
#    internas Docker cuando la BD no expone TLS
# ═══════════════════════════════════════════
cat > /root/.my.cnf << EOF
[client]
ssl-mode=DISABLED
EOF

chmod 600 /root/.my.cnf

echo -e "${GREEN}✅ Cliente MariaDB configurado sin SSL para red interna${NC}"

# ═══════════════════════════════════════════
# 1. SSH — Inyectar llaves públicas desde env
# ═══════════════════════════════════════════
mkdir -p /root/.ssh
chmod 700 /root/.ssh
> /root/.ssh/authorized_keys

KEY_COUNT=0

# Método 1: SSH_PUBLIC_KEYS con \n como separador
if [ -n "$SSH_PUBLIC_KEYS" ]; then
  while IFS= read -r KEY; do
    KEY=$(echo "$KEY" | tr -d '\r' | xargs)
    if [ -n "$KEY" ]; then
      echo "$KEY" >> /root/.ssh/authorized_keys
      KEY_COUNT=$((KEY_COUNT + 1))
    fi
  done < <(printf '%b\n' "$SSH_PUBLIC_KEYS")
fi

# Método 2: todas las variables que empiecen por SSH_KEY_
while IFS='=' read -r VAR_NAME VAR_VALUE; do
  if [[ "$VAR_NAME" == SSH_KEY_* ]] && [ -n "$VAR_VALUE" ]; then
    DEV_NAME="${VAR_NAME#SSH_KEY_}"
    KEY=$(echo "$VAR_VALUE" | tr -d '\r' | xargs)
    if [ -n "$KEY" ] && ! grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null; then
      echo "$KEY" >> /root/.ssh/authorized_keys
      KEY_COUNT=$((KEY_COUNT + 1))
      echo -e "${GREEN}✅ Llave SSH cargada: $DEV_NAME${NC}"
    fi
  fi
done < <(env)

# Método 3: compatibilidad hacia atrás
if [ -n "$SSH_PUBLIC_KEY" ]; then
  KEY=$(echo "$SSH_PUBLIC_KEY" | tr -d '\r' | xargs)
  if [ -n "$KEY" ] && ! grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$KEY" >> /root/.ssh/authorized_keys
    KEY_COUNT=$((KEY_COUNT + 1))
  fi
fi

chmod 600 /root/.ssh/authorized_keys

if [ -s /root/.ssh/authorized_keys ]; then
  TOTAL=$(grep -c 'ssh-' /root/.ssh/authorized_keys 2>/dev/null || echo 0)
  echo -e "${GREEN}✅ SSH configurado — $TOTAL llave(s) registrada(s)${NC}"
  /usr/sbin/sshd -p 2222
  echo -e "${GREEN}✅ SSH escuchando en 2222${NC}"
else
  echo -e "${YELLOW}⚠️ No se encontraron llaves SSH; acceso SSH deshabilitado${NC}"
fi

# ═══════════════════════════════════════════
# 2. Esperar base de datos
# ═══════════════════════════════════════════
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-drupal}"
DB_PASS="${DB_PASS:-drupal}"
DB_NAME="${DB_NAME:-drupal}"
DB_WAIT_RETRIES="${DB_WAIT_RETRIES:-60}"
DB_WAIT_DELAY="${DB_WAIT_DELAY:-2}"

echo -e "${YELLOW}⏳ Esperando base de datos en ${DB_HOST}:${DB_PORT}...${NC}"

for ((i=1; i<=DB_WAIT_RETRIES; i++)); do
  if mariadb-admin ping -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASS}" --silent >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Base de datos disponible${NC}"
    break
  fi

  if [ "$i" -eq "$DB_WAIT_RETRIES" ]; then
    echo -e "${RED}❌ No fue posible conectar a la base de datos${NC}"
    exit 1
  fi

  sleep "${DB_WAIT_DELAY}"
done

# ═══════════════════════════════════════════
# 3. Directorios persistentes
# ═══════════════════════════════════════════
FILES_DIR="/opt/drupal/web/sites/default/files"
mkdir -p "$FILES_DIR/translations"
mkdir -p "$FILES_DIR/private"
chown -R www-data:www-data "$FILES_DIR"
chmod -R 775 "$FILES_DIR"
echo -e "${GREEN}✅ Files listo: $FILES_DIR${NC}"

CONFIG_DIR="/opt/drupal/config/sync"
mkdir -p "$CONFIG_DIR"
chown -R www-data:www-data "$CONFIG_DIR"
chmod -R 775 "$CONFIG_DIR"
echo -e "${GREEN}✅ Config sync listo: $CONFIG_DIR${NC}"

# ═══════════════════════════════════════════
# 4. settings.php y settings.local.php
# ═══════════════════════════════════════════
SETTINGS="/opt/drupal/web/sites/default/settings.php"
DEFAULT_SETTINGS="/opt/drupal/web/sites/default/default.settings.php"
SETTINGS_LOCAL="/opt/drupal/web/sites/default/settings.local.php"

if [ ! -f "$SETTINGS" ] && [ -f "$DEFAULT_SETTINGS" ]; then
  cp "$DEFAULT_SETTINGS" "$SETTINGS"
  chmod 664 "$SETTINGS"
fi

if [ -f "$SETTINGS" ] && ! grep -q "settings.local.php" "$SETTINGS"; then
  cat >> "$SETTINGS" << 'SETTINGS_EOF'

// Incluir configuración generada desde variables de entorno.
if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
SETTINGS_EOF
fi

cat > "$SETTINGS_LOCAL" << EOF
<?php

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
  'namespace' => 'Drupal\\\\mysql\\\\Driver\\\\Database\\\\mysql',
  'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
];

\$settings['hash_salt'] = '${DRUPAL_HASH_SALT:-CHANGE_ME_HASH_SALT}';

\$settings['file_public_path'] = 'sites/default/files';
\$settings['file_private_path'] = 'sites/default/files/private';
\$settings['config_sync_directory'] = '../config/sync';

\$settings['trusted_host_patterns'] = ['.*'];

\$settings['cors.config'] = [
  'enabled' => TRUE,
  'allowedHeaders' => ['*'],
  'allowedMethods' => ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  'allowedOrigins' => array_filter(explode(',', '${CORS_ORIGINS:-http://localhost:3000}')),
  'exposedHeaders' => FALSE,
  'maxAge' => FALSE,
  'supportsCredentials' => FALSE,
];

\$settings['reverse_proxy'] = TRUE;
\$settings['reverse_proxy_addresses'] = ['127.0.0.1', '172.16.0.0/12', '10.0.0.0/8'];

define('APP_ENV', '${APP_ENV:-production}');
EOF

chmod 444 "$SETTINGS_LOCAL"
chown www-data:www-data "$SETTINGS_LOCAL"

echo -e "${GREEN}✅ settings.local.php generado${NC}"

# ═══════════════════════════════════════════
# 5. Instalación automática opcional
# ═══════════════════════════════════════════
INSTALL_SITE="${INSTALL_SITE:-false}"
INSTALL_FROM_CONFIG="${INSTALL_FROM_CONFIG:-false}"
INSTALL_PROFILE="${INSTALL_PROFILE:-standard}"
SITE_NAME="${SITE_NAME:-Drupal Site}"
SITE_MAIL="${SITE_MAIL:-admin@example.com}"
ACCOUNT_NAME="${ACCOUNT_NAME:-admin}"
ACCOUNT_MAIL="${ACCOUNT_MAIL:-admin@example.com}"
ACCOUNT_PASS="${ACCOUNT_PASS:-admin}"

cd /opt/drupal/web

DRUSH="/opt/drupal/vendor/bin/drush"

if [ "$INSTALL_SITE" = "true" ]; then
  if [ -f "$DRUSH" ]; then
    if ! $DRUSH status --fields=bootstrap --format=list 2>/dev/null | grep -q "Successful"; then
      echo -e "${YELLOW}🚀 Iniciando instalación automática de Drupal...${NC}"

      if [ "$INSTALL_FROM_CONFIG" = "true" ]; then
        $DRUSH site:install "${INSTALL_PROFILE}" \
          --existing-config \
          --account-name="${ACCOUNT_NAME}" \
          --account-pass="${ACCOUNT_PASS}" \
          --account-mail="${ACCOUNT_MAIL}" \
          --site-name="${SITE_NAME}" \
          --site-mail="${SITE_MAIL}" \
          -y
      else
        $DRUSH site:install "${INSTALL_PROFILE}" \
          --account-name="${ACCOUNT_NAME}" \
          --account-pass="${ACCOUNT_PASS}" \
          --account-mail="${ACCOUNT_MAIL}" \
          --site-name="${SITE_NAME}" \
          --site-mail="${SITE_MAIL}" \
          -y
      fi

      echo -e "${GREEN}✅ Drupal instalado automáticamente${NC}"
    else
      echo -e "${GREEN}✅ Drupal ya estaba instalado${NC}"
    fi
  else
    echo -e "${RED}❌ Drush no está disponible para instalar Drupal${NC}"
    exit 1
  fi
fi

# ═══════════════════════════════════════════
# 6. Permisos finales
# ═══════════════════════════════════════════
chown -R www-data:www-data /opt/drupal/web/sites/default
chmod -R 775 /opt/drupal/web/sites/default/files || true

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ honda-motoverso listo             ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exec "$@"