#!/bin/bash
# ─────────────────────────────────────────────────────────────
# honda-motoverso — Pull Files  Dokploy → Local
# Los files viven en el VOLUMEN honda_motoverso_files
# Son independientes del contenedor — siempre persisten
# Uso: bash .vscode/pull-files.sh [dev|stage|main] [--only-public]
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

[ -f ".env" ] && export $(grep -v '^#' .env | xargs 2>/dev/null)

ENV="${1:-main}"; ONLY_PUBLIC=false
[ "$2" == "--only-public" ] && ONLY_PUBLIC=true

DOKPLOY_HOST="${DOKPLOY_SSH_HOST}"; DOKPLOY_PORT="${DOKPLOY_SSH_PORT:-2222}"
DOKPLOY_USER="${DOKPLOY_SSH_USER:-root}"

case "$ENV" in
  main|live) CONTAINER="${CONTAINER_MAIN:-honda-motoverso-web}"
             VOLUME="${VOLUME_FILES_MAIN:-honda_motoverso_files}" ;;
  stage)     CONTAINER="${CONTAINER_STAGE:-honda-motoverso-stage-web}"
             VOLUME="honda_motoverso_stage_files" ;;
  dev)       CONTAINER="${CONTAINER_DEV:-honda-motoverso-dev-web}"
             VOLUME="honda_motoverso_dev_files" ;;
  *) echo -e "${RED}❌ Uso: dev | stage | main${NC}"; exit 1 ;;
esac

BACKUP_DIR=".backups"; DATE=$(date +"%Y%m%d_%H%M%S")
LOCAL_FILES="web/sites/default/files"
mkdir -p "$BACKUP_DIR" "$LOCAL_FILES"
ARCHIVE="$BACKUP_DIR/honda_motoverso_${ENV}_${DATE}_files.tar.gz"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  📁 Pull Files ← $ENV                  ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Contenedor : ${GREEN}$CONTAINER${NC}"
echo -e "  Volumen    : ${GREEN}$VOLUME${NC}"
[ "$ONLY_PUBLIC" = true ] && echo -e "  Modo       : ${YELLOW}Solo archivos públicos${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Comprimir files desde el volumen en el servidor ──────────
# El volumen existe independientemente del contenedor
# Leemos desde el contenedor que lo tiene montado
echo -e "${YELLOW}⏳ Comprimiendo files desde volumen remoto...${NC}"

# Excluir archivos generados (css/js/styles se regeneran con drush cr)
EXCLUDES="--exclude=./php --exclude=./js --exclude=./css --exclude=./styles"
[ "$ONLY_PUBLIC" = true ] && EXCLUDES="$EXCLUDES --exclude=./private"

ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    -p "$DOKPLOY_PORT" "$DOKPLOY_USER@$DOKPLOY_HOST" \
  "docker exec $CONTAINER bash -c \
    'tar -czf - $EXCLUDES \
     -C /opt/drupal/web/sites/default/files .'" \
  > "$ARCHIVE" 2>/dev/null

if [ $? -ne 0 ] || [ ! -s "$ARCHIVE" ]; then
  echo -e "${RED}❌ Error descargando files${NC}"
  rm -f "$ARCHIVE"; exit 1
fi

FILE_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
echo -e "${GREEN}✅ Files descargados ($FILE_SIZE)${NC}"

# ── Extraer localmente ────────────────────────────────────────
# Los files locales también están en un volumen Docker
echo -e "${YELLOW}📂 Extrayendo en volumen local ($LOCAL_FILES)...${NC}"
tar -xzf "$ARCHIVE" -C "$LOCAL_FILES"

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Error extrayendo files${NC}"; exit 1
fi

docker compose exec web drush cr 2>/dev/null

echo ""
echo -e "${GREEN}✅ Files '$ENV' sincronizados!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  💾 Archive : ${CYAN}$ARCHIVE${NC} (${FILE_SIZE})"
echo -e "  📁 Destino : ${CYAN}$LOCAL_FILES${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
