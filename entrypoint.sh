#!/bin/bash
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  🚀 honda-motoverso arrancando...       ${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ═══════════════════════════════════════════
# 1. SSH — Inyectar llaves públicas desde env
# ═══════════════════════════════════════════
# Soporta múltiples desarrolladores.
# En el .env de Dokploy definir SSH_PUBLIC_KEYS
# con una llave por línea, usando \n como separador:
#
# SSH_PUBLIC_KEYS=ssh-ed25519 AAAA... dev1@mac\nssh-ed25519 BBBB... dev2@mac
#
# O como variable individual por desarrollador:
# SSH_KEY_JULIAN=ssh-ed25519 AAAA... julian@mac
# SSH_KEY_ANDRES=ssh-ed25519 BBBB... andres@mac
# SSH_KEY_CARLOS=ssh-ed25519 CCCC... carlos@mac

mkdir -p /root/.ssh
chmod 700 /root/.ssh
> /root/.ssh/authorized_keys  # limpiar antes de escribir

KEY_COUNT=0

# ── Método 1: SSH_PUBLIC_KEYS con \n como separador ──────────
if [ -n "$SSH_PUBLIC_KEYS" ]; then
  echo -e "$SSH_PUBLIC_KEYS" | while IFS= read -r KEY; do
    KEY=$(echo "$KEY" | tr -d '\r' | xargs)
    if [ -n "$KEY" ]; then
      echo "$KEY" >> /root/.ssh/authorized_keys
      KEY_COUNT=$((KEY_COUNT + 1))
    fi
  done
fi

# ── Método 2: SSH_KEY_NOMBRE por cada desarrollador ──────────
# Lee todas las variables de entorno que empiecen con SSH_KEY_
while IFS='=' read -r VAR_NAME VAR_VALUE; do
  if [[ "$VAR_NAME" == SSH_KEY_* ]] && [ -n "$VAR_VALUE" ]; then
    DEV_NAME="${VAR_NAME#SSH_KEY_}"
    KEY=$(echo "$VAR_VALUE" | tr -d '\r' | xargs)
    if [ -n "$KEY" ]; then
      echo "$KEY" >> /root/.ssh/authorized_keys
      KEY_COUNT=$((KEY_COUNT + 1))
      echo -e "${GREEN}  ✅ Llave SSH: $DEV_NAME${NC}"
    fi
  fi
done < <(env)

# ── Método 3: SSH_PUBLIC_KEY (retrocompatibilidad) ────────────
if [ -n "$SSH_PUBLIC_KEY" ]; then
  KEY=$(echo "$SSH_PUBLIC_KEY" | tr -d '\r' | xargs)
  if [ -n "$KEY" ] && ! grep -qF "$KEY" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$KEY" >> /root/.ssh/authorized_keys
    KEY_COUNT=$((KEY_COUNT + 1))
  fi
fi

chmod 600 /root/.ssh/authorized_keys

if [ "$KEY_COUNT" -gt 0 ] || [ -s /root/.ssh/authorized_keys ]; then
  TOTAL=$(grep -c 'ssh-' /root/.ssh/authorized_keys 2>/dev/null || echo 0)
  echo -e "${GREEN}✅ SSH configurado — $TOTAL llave(s) registrada(s)${NC}"
else
  echo -e "${YELLOW}⚠️  No se encontraron llaves SSH — acceso deshabilitado${NC}"
  echo -e "${YELLOW}   Agrega SSH_KEY_NOMBRE=<llave.pub> en el .env de Dokploy${NC}"
fi

/usr/sbin/sshd -p 2222
echo -e "${GREEN}✅ SSH en puerto 2222${NC}"

# ═══════════════════════════════════════════
# 2. VOLÚMENES PERSISTENTES
#    Estos directorios viven en volúmenes
#    Docker nombrados → sobreviven reinicios
#    y redeploys completos
# ═══════════════════════════════════════════

# ── Files públicos (imágenes, uploads) ───
# Volumen: honda_motoverso_files
FILES_DIR="/opt/drupal/web/sites/default/files"
mkdir -p "$FILES_DIR/translations"
mkdir -p "$FILES_DIR/private"
chown -R www-data:www-data "$FILES_DIR"
chmod -R 775 "$FILES_DIR"
echo -e "${GREEN}✅ Volumen files listo: $FILES_DIR${NC}"

# ── Config sync (gestionado por Git, no volumen) ─
CONFIG_DIR="/opt/drupal/config/sync"
mkdir -p "$CONFIG_DIR"
chmod -R 775 "$CONFIG_DIR"
chown -R www-data:www-data "$CONFIG_DIR"

# ═══════════════════════════════════════════
# 3. SETTINGS.PHP
#    Generado desde variables de entorno
#    del contenedor — sin credenciales en repo
# ═══════════════════════════════════════════
SETTINGS="/opt/drupal/web/sites/default/settings.php"
SETTINGS_LOCAL="/opt/drupal/web/sites/default/settings.local.php"

# Copiar default.settings si settings no existe
if [ ! -f "$SETTINGS" ]; then
  if [ -f "/opt/drupal/web/sites/default/default.settings.php" ]; then
    cp /opt/drupal/web/sites/default/default.settings.php "$SETTINGS"
    chmod 664 "$SETTINGS"
  fi
fi

# Asegurar que settings.php incluye settings.local.php
if [ -f "$SETTINGS" ] && ! grep -q "settings.local.php" "$SETTINGS"; then
  cat >> "$SETTINGS" << 'SETTINGS_EOF'

// Incluir configuración generada desde env vars
if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
SETTINGS_EOF
fi

# Generar settings.local.php desde env vars del contenedor
cat > "$SETTINGS_LOCAL" << EOF
<?php

/**
 * honda-motoverso — settings.local.php
 * Auto-generado por entrypoint.sh desde variables de entorno.
 * NO versionar este archivo.
 */

// ── Base de datos ─────────────────────────────────────────────
// Volumen: honda_motoverso_db (MariaDB)
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

// ── Seguridad ─────────────────────────────────────────────────
\$settings['hash_salt'] = '${DRUPAL_HASH_SALT:-INSECURE_CHANGE_IN_PRODUCTION}';

// ── Rutas persistentes (apuntan a volúmenes Docker) ──────────
\$settings['file_public_path']  = 'sites/default/files';
\$settings['file_private_path'] = 'sites/default/files/private';
\$settings['config_sync_directory'] = '../config/sync';

// ── Host patterns ─────────────────────────────────────────────
\$settings['trusted_host_patterns'] = ['.*'];

// ── CORS para JSON:API ────────────────────────────────────────
\$settings['cors.config'] = [
  'enabled'             => TRUE,
  'allowedHeaders'      => ['*'],
  'allowedMethods'      => ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  'allowedOrigins'      => array_filter(explode(',', '${CORS_ORIGINS:-http://localhost:3000}')),
  'exposedHeaders'      => TRUE,
  'maxAge'              => FALSE,
  'supportsCredentials' => FALSE,
];

// ── Reverse proxy Traefik ─────────────────────────────────────
\$settings['reverse_proxy']           = TRUE;
\$settings['reverse_proxy_addresses'] = ['127.0.0.1'];

// ── Entorno ───────────────────────────────────────────────────
define('APP_ENV', '${APP_ENV:-production}');
EOF

chmod 444 "$SETTINGS_LOCAL"
echo -e "${GREEN}✅ settings.local.php generado desde env vars${NC}"

# ═══════════════════════════════════════════
# 4. COMPOSER INSTALL
#    Solo si vendor no existe (primer boot
#    o si se borró el volumen de vendor)
# ═══════════════════════════════════════════
if [ -f "/opt/drupal/composer.json" ] && [ ! -d "/opt/drupal/vendor" ]; then
  echo -e "${YELLOW}📦 Ejecutando composer install...${NC}"
  cd /opt/drupal && composer install \
    --no-interaction \
    --no-dev \
    --optimize-autoloader \
    --prefer-dist
  echo -e "${GREEN}✅ Composer OK${NC}"
fi

# ── Drush disponible globalmente ──────────
if [ -f "/opt/drupal/vendor/bin/drush" ] && [ ! -L "/usr/local/bin/drush" ]; then
  ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush
fi

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ honda-motoverso listo               ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exec "$@"
