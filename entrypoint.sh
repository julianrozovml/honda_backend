#!/bin/bash
# Sin set -e — manejamos errores manualmente

GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  🚀 honda-motoverso arrancando...       ${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ═══════════════════════════════════════════
# 1. SSH — múltiples desarrolladores
# ═══════════════════════════════════════════
mkdir -p /root/.ssh && chmod 700 /root/.ssh
> /root/.ssh/authorized_keys

# Una variable por desarrollador: SSH_KEY_NOMBRE=<llave.pub>
while IFS='=' read -r VAR_NAME VAR_VALUE; do
  if [[ "$VAR_NAME" == SSH_KEY_* ]] && [ -n "$VAR_VALUE" ]; then
    KEY=$(echo "$VAR_VALUE" | tr -d '\r' | xargs)
    [ -n "$KEY" ] && echo "$KEY" >> /root/.ssh/authorized_keys \
      && echo -e "${GREEN}  ✅ SSH: ${VAR_NAME#SSH_KEY_}${NC}"
  fi
done < <(env)

# Retrocompatibilidad
[ -n "$SSH_PUBLIC_KEYS" ] && echo -e "$SSH_PUBLIC_KEYS" | tr -d '\r' >> /root/.ssh/authorized_keys
[ -n "$SSH_PUBLIC_KEY" ]  && echo "$SSH_PUBLIC_KEY" | tr -d '\r' >> /root/.ssh/authorized_keys

chmod 600 /root/.ssh/authorized_keys
TOTAL=$(grep -c 'ssh-' /root/.ssh/authorized_keys 2>/dev/null || echo 0)

if [ "$TOTAL" -gt 0 ]; then
  echo -e "${GREEN}✅ SSH — $TOTAL llave(s) configurada(s)${NC}"
  /usr/sbin/sshd -p 2222 && echo -e "${GREEN}✅ SSH en puerto 2222${NC}"
else
  echo -e "${YELLOW}⚠️  Sin llaves SSH — agrega SSH_KEY_NOMBRE en Dokploy env vars${NC}"
fi

# ═══════════════════════════════════════════
# 2. VENDOR — verificar si composer.lock cambió
#
# El vendor/ viene de la imagen (build time).
# El volumen honda_motoverso_vendor persiste entre deploys.
#
# Situaciones:
# A) Primer deploy: vendor del build se copia al volumen → OK
# B) Redeploy sin cambios en deps: volumen ya tiene vendor → skip
# C) Redeploy con nuevas deps: composer.lock cambió → reinstalar
# ═══════════════════════════════════════════
cd /opt/drupal

VENDOR_DIR="/opt/drupal/vendor"
COMPOSER_LOCK="/opt/drupal/composer.lock"
COMPOSER_JSON="/opt/drupal/composer.json"
STAMP="$VENDOR_DIR/.stamp"

if [ ! -f "$COMPOSER_JSON" ]; then
  echo -e "${YELLOW}⚠️  Sin composer.json — omitiendo verificación${NC}"

elif [ ! -d "$VENDOR_DIR" ] || [ ! -f "$VENDOR_DIR/autoload.php" ]; then
  echo -e "${CYAN}ℹ️  vendor/ ausente — ejecutando composer install${NC}"
  composer install --no-interaction --no-dev --optimize-autoloader --prefer-dist --no-progress
  [ $? -eq 0 ] && { [ -f "$COMPOSER_LOCK" ] && md5sum "$COMPOSER_LOCK" > "$STAMP" || md5sum "$COMPOSER_JSON" > "$STAMP"; }

elif [ -f "$STAMP" ]; then
  # Comparar checksum
  CURRENT=$( [ -f "$COMPOSER_LOCK" ] && md5sum "$COMPOSER_LOCK" || md5sum "$COMPOSER_JSON" | cut -d' ' -f1 )
  SAVED=$(cut -d' ' -f1 "$STAMP" 2>/dev/null)

  if [ "$CURRENT" != "$SAVED" ]; then
    echo -e "${CYAN}ℹ️  Dependencias cambiaron — actualizando${NC}"
    composer install --no-interaction --no-dev --optimize-autoloader --prefer-dist --no-progress
    [ $? -eq 0 ] && { [ -f "$COMPOSER_LOCK" ] && md5sum "$COMPOSER_LOCK" > "$STAMP" || md5sum "$COMPOSER_JSON" > "$STAMP"; }
  else
    echo -e "${GREEN}✅ Dependencias al día${NC}"
  fi
else
  echo -e "${GREEN}✅ vendor/ disponible${NC}"
fi

# Drush global
[ -f "/opt/drupal/vendor/bin/drush" ] && \
  ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush 2>/dev/null

# ═══════════════════════════════════════════
# 3. DIRECTORIOS PERSISTENTES (volúmenes Docker)
# ═══════════════════════════════════════════
FILES_DIR="/opt/drupal/web/sites/default/files"
mkdir -p "$FILES_DIR/translations" "$FILES_DIR/private"
chown -R www-data:www-data "$FILES_DIR" 2>/dev/null
chmod -R 775 "$FILES_DIR" 2>/dev/null
echo -e "${GREEN}✅ Files: $FILES_DIR${NC}"

mkdir -p "/opt/drupal/config/sync"
chmod -R 775 "/opt/drupal/config/sync" 2>/dev/null
chown -R www-data:www-data "/opt/drupal/config/sync" 2>/dev/null

# ═══════════════════════════════════════════
# 4. SETTINGS.LOCAL.PHP desde env vars
# ═══════════════════════════════════════════
SETTINGS="/opt/drupal/web/sites/default/settings.php"
SETTINGS_LOCAL="/opt/drupal/web/sites/default/settings.local.php"

chmod u+w /opt/drupal/web/sites/default 2>/dev/null

if [ ! -f "$SETTINGS" ] && [ -f "/opt/drupal/web/sites/default/default.settings.php" ]; then
  cp /opt/drupal/web/sites/default/default.settings.php "$SETTINGS"
  chmod 664 "$SETTINGS"
fi

if [ -f "$SETTINGS" ] && ! grep -q "settings.local.php" "$SETTINGS"; then
  chmod u+w "$SETTINGS"
  printf '\nif (file_exists($app_root . "/" . $site_path . "/settings.local.php")) {\n  include $app_root . "/" . $site_path . "/settings.local.php";\n}\n' >> "$SETTINGS"
fi

cat > "$SETTINGS_LOCAL" << EOF
<?php
/**
 * honda-motoverso — settings.local.php
 * Auto-generado por entrypoint.sh — NO versionar.
 */
\$databases['default']['default'] = [
  'driver'    => 'mysql',
  'database'  => '${DB_NAME:-drupal}',
  'username'  => '${DB_USER:-drupal}',
  'password'  => '${DB_PASS:-drupal}',
  'host'      => '${DB_HOST:-db}',
  'port'      => '${DB_PORT:-3306}',
  'prefix'    => '',
  'charset'   => 'utf8mb4',
  'collation' => 'utf8mb4_general_ci',
  'namespace' => 'Drupal\\\\mysql\\\\Driver\\\\Database\\\\mysql',
  'autoload'  => 'core/modules/mysql/src/Driver/Database/mysql/',
];
\$settings['hash_salt']             = '${DRUPAL_HASH_SALT:-INSECURE_CHANGE_IN_PRODUCTION}';
\$settings['file_public_path']      = 'sites/default/files';
\$settings['file_private_path']     = 'sites/default/files/private';
\$settings['config_sync_directory'] = '../config/sync';
\$settings['trusted_host_patterns'] = ['.*'];
\$settings['cors.config'] = [
  'enabled'        => TRUE,
  'allowedHeaders' => ['*'],
  'allowedMethods' => ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  'allowedOrigins' => array_filter(explode(',', '${CORS_ORIGINS:-http://localhost:3000}')),
  'exposedHeaders' => TRUE,
  'maxAge'         => FALSE,
  'supportsCredentials' => FALSE,
];
\$settings['reverse_proxy']           = TRUE;
\$settings['reverse_proxy_addresses'] = ['127.0.0.1'];
define('APP_ENV', '${APP_ENV:-production}');
EOF

chmod 444 "$SETTINGS_LOCAL"
echo -e "${GREEN}✅ settings.local.php generado${NC}"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ honda-motoverso listo               ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exec "$@"
