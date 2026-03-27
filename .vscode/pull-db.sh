#!/bin/bash
# ─────────────────────────────────────────────────────────────
# honda-motoverso — Pull DB  Dokploy → Local
# Uso: bash .vscode/pull-db.sh [dev|stage|main]
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

[ -f ".env" ] && export $(grep -v '^#' .env | xargs 2>/dev/null)

ENV="${1:-main}"
DOKPLOY_HOST="${DOKPLOY_SSH_HOST}"; DOKPLOY_PORT="${DOKPLOY_SSH_PORT:-2222}"
DOKPLOY_USER="${DOKPLOY_SSH_USER:-root}"

case "$ENV" in
  main|live) CONTAINER="${CONTAINER_MAIN:-honda-motoverso-web}" ;;
  stage)     CONTAINER="${CONTAINER_STAGE:-honda-motoverso-stage-web}" ;;
  dev)       CONTAINER="${CONTAINER_DEV:-honda-motoverso-dev-web}" ;;
  *) echo -e "${RED}❌ Uso: dev | stage | main${NC}"; exit 1 ;;
esac

BACKUP_DIR=".backups"; DATE=$(date +"%Y%m%d_%H%M%S")
mkdir -p "$BACKUP_DIR"
DUMP_GZ="$BACKUP_DIR/honda_motoverso_${ENV}_${DATE}.sql.gz"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  📥 Pull DB ← $ENV                     ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Contenedor : ${GREEN}$CONTAINER${NC}"
echo -e "  Servidor   : ${GREEN}$DOKPLOY_HOST:$DOKPLOY_PORT${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Dump remoto via SSH al contenedor ────────────────────────
# La BD vive en el volumen honda_motoverso_db (independiente)
# drush sql-dump la accede via settings.local.php del contenedor
echo -e "${YELLOW}⏳ Creando dump desde volumen BD remoto...${NC}"

ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    -p "$DOKPLOY_PORT" "$DOKPLOY_USER@$DOKPLOY_HOST" \
  "docker exec $CONTAINER bash -c \
    'cd /opt/drupal && drush sql-dump --gzip'" \
  > "$DUMP_GZ" 2>/dev/null

if [ $? -ne 0 ] || [ ! -s "$DUMP_GZ" ]; then
  echo -e "${RED}❌ Error — verifica SSH: bash .vscode/ssh.sh $ENV${NC}"
  rm -f "$DUMP_GZ"; exit 1
fi

FILE_SIZE=$(du -sh "$DUMP_GZ" | cut -f1)
echo -e "${GREEN}✅ Dump descargado ($FILE_SIZE)${NC}"

# ── Importar en local ─────────────────────────────────────────
echo -e "${YELLOW}🔄 Importando en BD local...${NC}"
docker compose exec -T web bash -c \
  "cd /opt/drupal && drush sql-drop -y 2>/dev/null; drush sql-cli" \
  < <(gunzip -c "$DUMP_GZ")

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error importando. ¿Está el docker local corriendo?${NC}"
  echo -e "${YELLOW}   Ejecuta primero: docker compose up -d${NC}"
  exit 1
fi

docker compose exec web drush cr 2>/dev/null

echo ""
echo -e "${GREEN}✅ BD '$ENV' importada localmente!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  💾 Backup : ${CYAN}$DUMP_GZ${NC} (${FILE_SIZE})"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
