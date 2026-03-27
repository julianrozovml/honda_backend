#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

APP_ROOT="/opt/drupal"
WEB_ROOT="${APP_ROOT}/web"
SITE_DIR="${WEB_ROOT}/sites/default"

SETTINGS="${SITE_DIR}/settings.php"
DEFAULT_SETTINGS="${SITE_DIR}/default.settings.php"
SETTINGS_LOCAL="${SITE_DIR}/settings.local.php"

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-drupal}"
DB_USER="${DB_USER:-drupal}"
DB_PASS="${DB_PASS:-drupal}"
DB_WAIT_RETRIES="${DB_WAIT_RETRIES:-60}"
DB_WAIT_DELAY="${DB_WAIT_DELAY:-2}"

DRUPAL_HASH_SALT="${DRUPAL_HASH_SALT:-CHANGE_ME_HASH_SALT}"
APP_ENV="${APP_ENV:-production}"
CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:3000}"

INSTALL_SITE="${INSTALL_SITE:-false}"
INSTALL_FROM_CONFIG="${INSTALL_FROM_CONFIG:-false}"
INSTALL_PROFILE="${INSTALL_PROFILE:-standard}"
SITE_NAME="${SITE_NAME:-Drupal Site}"
SITE_MAIL="${SITE_MAIL:-admin@example.com}"
ACCOUNT_NAME="${ACCOUNT_NAME:-admin}"
ACCOUNT_MAIL="${ACCOUNT_MAIL:-admin@example.com}"
ACCOUNT_PASS="${ACCOUNT_PASS:-admin123456}"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🚀 honda-motoverso arrancando...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ═══════════════════════════════════════════
# 0. Cliente MariaDB sin SSL para red interna
# ═══════════════════════════════════════════
# Fix SSL para root (drush, mysql directo)
printf '[client]\nssl-mode=DISABLED\nprotocol=TCP\n' > /root/.my.cnf
chmod 600 /root/.my.cnf

# Fix SSL para www-data (por si apache ejecuta comandos DB)
mkdir -p /var/www
printf '[client]\nssl-mode=DISABLED\nprotocol=TCP\n' > /var/www/.my.cnf
chmod 644 /var/www/.my.cnf

echo -e "${GREEN}✅ Cliente MariaDB configurado sin SSL para red interna${NC}"

# ═══════════════════════════════════════════
# 1. Preparar filesystem Drupal
# ═══════════════════════════════════════════
echo -e "${YELLOW}📝 Preparando filesystem Drupal...${NC}"

mkdir -p "${SITE_DIR}"
mkdir -p "${SITE_DIR}/files/translations"
mkdir -p "${SITE_DIR}/files/private"
mkdir -p "${APP_ROOT}/config/sync"

chown -R www-data:www-data "${SITE_DIR}/files" "${APP_ROOT}/config"
chmod -R 775 "${SITE_DIR}/files" "${APP_ROOT}/config"

echo -e "${GREEN}✅ Directorios persistentes preparados${NC}"

# ═══════════════════════════════════════════
# 2. Asegurar settings.php
# ═══════════════════════════════════════════
if [ ! -f "${SETTINGS}" ]; then
  echo -e "${YELLOW}📝 settings.php no existe, creando desde default.settings.php...${NC}"
  if [ ! -f "${DEFAULT_SETTINGS}" ]; then
    echo -e "${RED}❌ No existe ${DEFAULT_SETTINGS}${NC}"
    exit 1
  fi
  cp "${DEFAULT_SETTINGS}" "${SETTINGS}"
  chmod 664 "${SETTINGS}"
  chown www-data:www-data "${SETTINGS}"
  echo -e "${GREEN}✅ settings.php creado${NC}"
else
  echo -e "${GREEN}✅ settings.php ya existe${NC}"
fi

# ═══════════════════════════════════════════
# 3. Incluir settings.local.php
# ═══════════════════════════════════════════
if ! grep -q "settings.local.php" "${SETTINGS}"; then
  echo -e "${YELLOW}📝 Agregando include de settings.local.php en settings.php...${NC}"
  cat >> "${SETTINGS}" <<'EOF'

/**
 * Incluir configuración local generada dinámicamente.
 */
if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
EOF
  echo -e "${GREEN}✅ Include agregado en settings.php${NC}"
else
  echo -e "${GREEN}✅ settings.php ya incluye settings.local.php${NC}"
fi

# ═══════════════════════════════════════════
# 4. Crear settings.local.php SIEMPRE
# ═══════════════════════════════════════════
echo -e "${YELLOW}📝 Generando settings.local.php...${NC}"

cat > "${SETTINGS_LOCAL}" <<EOF
<?php

/**
 * Archivo generado automáticamente por entrypoint.sh
 * No editar manualmente dentro del contenedor.
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
  'namespace' => 'Drupal\\\\mysql\\\\Driver\\\\Database\\\\mysql',
  'autoload' => 'core/modules/mysql/src/Driver/Database/mysql/',
];

\$settings['hash_salt'] = '${DRUPAL_HASH_SALT}';

\$settings['file_public_path'] = 'sites/default/files';
\$settings['file_private_path'] = 'sites/default/files/private';
\$settings['config_sync_directory'] = '../config/sync';

\$settings['trusted_host_patterns'] = ['.*'];

\$settings['cors.config'] = [
  'enabled' => TRUE,
  'allowedHeaders' => ['*'],
  'allowedMethods' => ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  'allowedOrigins' => array_filter(explode(',', '${CORS_ORIGINS}')),
  'exposedHeaders' => FALSE,
  'maxAge' => FALSE,
  'supportsCredentials' => FALSE,
];

\$settings['reverse_proxy'] = TRUE;
\$settings['reverse_proxy_addresses'] = ['127.0.0.1', '172.16.0.0/12', '10.0.0.0/8'];

define('APP_ENV', '${APP_ENV}');
EOF

if [ ! -f "${SETTINGS_LOCAL}" ]; then
  echo -e "${RED}❌ No fue posible crear ${SETTINGS_LOCAL}${NC}"
  exit 1
fi

chmod 444 "${SETTINGS_LOCAL}"
chown www-data:www-data "${SETTINGS_LOCAL}"

echo -e "${GREEN}✅ settings.local.php generado${NC}"

# ═══════════════════════════════════════════
# 5. Validación fuerte de settings
# ═══════════════════════════════════════════
if ! grep -q "settings.local.php" "${SETTINGS}"; then
  echo -e "${RED}❌ settings.php no incluye settings.local.php${NC}"
  exit 1
fi

if [ ! -s "${SETTINGS_LOCAL}" ]; then
  echo -e "${RED}❌ settings.local.php no existe o está vacío${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Configuración de settings validada${NC}"
ls -lah "${SITE_DIR}" | sed 's/^/   /'

# ═══════════════════════════════════════════
# 6. Esperar base de datos
# ═══════════════════════════════════════════
echo -e "${YELLOW}⏳ Esperando base de datos en ${DB_HOST}:${DB_PORT}...${NC}"

DB_CONNECTED=false

for ((i=1; i<=DB_WAIT_RETRIES; i++)); do
  if mariadb \
      --host="${DB_HOST}" \
      --port="${DB_PORT}" \
      --user="${DB_USER}" \
      --password="${DB_PASS}" \
      --protocol=TCP \
      --connect-timeout=5 \
      --execute="SELECT 1;" >/dev/null 2>&1; then
    DB_CONNECTED=true
    echo -e "${GREEN}✅ Base de datos disponible${NC}"
    break
  fi

  echo -e "${YELLOW}⏳ Intento ${i}/${DB_WAIT_RETRIES} esperando DB...${NC}"
  sleep "${DB_WAIT_DELAY}"
done

if [ "${DB_CONNECTED}" != "true" ]; then
  echo -e "${RED}❌ No fue posible conectar a la base de datos${NC}"
  exit 1
fi

# ═══════════════════════════════════════════
# 7. Preparar Drush
# ═══════════════════════════════════════════
DRUSH="${APP_ROOT}/vendor/bin/drush"

if [ ! -x "${DRUSH}" ]; then
  echo -e "${RED}❌ Drush no está disponible en ${DRUSH}${NC}"
  exit 1
fi

cd "${WEB_ROOT}"

# ═══════════════════════════════════════════
# 8. Detectar si Drupal ya está instalado
# ═══════════════════════════════════════════
echo -e "${YELLOW}🔎 Verificando si Drupal ya está instalado...${NC}"

DRUPAL_INSTALLED=false

if "${DRUSH}" --root="${WEB_ROOT}" status --fields=bootstrap --format=list 2>/dev/null | grep -q "Successful"; then
  DRUPAL_INSTALLED=true
fi

if [ "${DRUPAL_INSTALLED}" = "true" ]; then
  echo -e "${GREEN}✅ Drupal ya está instalado${NC}"
else
  echo -e "${YELLOW}ℹ️ Drupal aún no está instalado${NC}"
fi

# ═══════════════════════════════════════════
# 9. Instalación automática opcional
# ═══════════════════════════════════════════
if [ "${INSTALL_SITE}" = "true" ] && [ "${DRUPAL_INSTALLED}" != "true" ]; then
  echo -e "${YELLOW}🚀 Iniciando instalación automática de Drupal...${NC}"

  if [ "${INSTALL_FROM_CONFIG}" = "true" ]; then
    "${DRUSH}" --root="${WEB_ROOT}" site:install "${INSTALL_PROFILE}" \
      --existing-config \
      --account-name="${ACCOUNT_NAME}" \
      --account-pass="${ACCOUNT_PASS}" \
      --account-mail="${ACCOUNT_MAIL}" \
      --site-name="${SITE_NAME}" \
      --site-mail="${SITE_MAIL}" \
      -y
  else
    "${DRUSH}" --root="${WEB_ROOT}" site:install "${INSTALL_PROFILE}" \
      --account-name="${ACCOUNT_NAME}" \
      --account-pass="${ACCOUNT_PASS}" \
      --account-mail="${ACCOUNT_MAIL}" \
      --site-name="${SITE_NAME}" \
      --site-mail="${SITE_MAIL}" \
      -y
  fi

  echo -e "${GREEN}✅ Drupal instalado automáticamente${NC}"
elif [ "${INSTALL_SITE}" = "true" ] && [ "${DRUPAL_INSTALLED}" = "true" ]; then
  echo -e "${GREEN}✅ INSTALL_SITE=true, pero Drupal ya está instalado; no se reinstala${NC}"
else
  echo -e "${YELLOW}ℹ️ INSTALL_SITE=false, omitiendo instalación automática${NC}"
fi

# ═══════════════════════════════════════════
# 10. Permisos finales
# ═══════════════════════════════════════════
chown -R www-data:www-data "${SITE_DIR}" || true
chmod -R 775 "${SITE_DIR}/files" || true

# ═══════════════════════════════════════════
# 11. SSH (AL FINAL)
# ═══════════════════════════════════════════
echo -e "${YELLOW}🔐 Configurando acceso SSH...${NC}"

mkdir -p /root/.ssh
chmod 700 /root/.ssh
: > /root/.ssh/authorized_keys

KEY_COUNT=0

if [ -n "${SSH_PUBLIC_KEYS:-}" ]; then
  while IFS= read -r KEY; do
    KEY="$(echo "$KEY" | tr -d '\r' | xargs || true)"
    if [ -n "$KEY" ]; then
      echo "$KEY" >> /root/.ssh/authorized_keys
      KEY_COUNT=$((KEY_COUNT + 1))
    fi
  done < <(printf '%b\n' "$SSH_PUBLIC_KEYS")
fi

while IFS='=' read -r VAR_NAME VAR_VALUE; do
  if [[ "$VAR_NAME" == SSH_KEY_* ]] && [ -n "$VAR_VALUE" ]; then
    KEY="$(echo "$VAR_VALUE" | tr -d '\r' | xargs || true)"
    if [ -n "$KEY" ] && ! grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null; then
      echo "$KEY" >> /root/.ssh/authorized_keys
      KEY_COUNT=$((KEY_COUNT + 1))
      echo -e "${GREEN}✅ Llave SSH cargada: ${VAR_NAME#SSH_KEY_}${NC}"
    fi
  fi
done < <(env)

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  KEY="$(echo "$SSH_PUBLIC_KEY" | tr -d '\r' | xargs || true)"
  if [ -n "$KEY" ] && ! grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$KEY" >> /root/.ssh/authorized_keys
    KEY_COUNT=$((KEY_COUNT + 1))
  fi
fi

chmod 600 /root/.ssh/authorized_keys

if [ -s /root/.ssh/authorized_keys ]; then
  TOTAL="$(grep -c 'ssh-' /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
  echo -e "${GREEN}✅ SSH configurado — $TOTAL llave(s) registrada(s)${NC}"
  /usr/sbin/sshd -p 2222
  echo -e "${GREEN}✅ SSH escuchando en 2222${NC}"
else
  echo -e "${YELLOW}⚠️ SSH sin llaves, no se inicia sshd${NC}"
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ honda-motoverso listo${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exec "$@"