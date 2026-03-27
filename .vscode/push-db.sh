#!/bin/bash
# push-db.sh — honda-motoverso
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -f ".env" ] && export $(grep -v '^#' .env | xargs 2>/dev/null)
ENV="${1:-dev}"
[[ "$ENV" == "main" || "$ENV" == "live" ]] && \
  echo -e "${RED}🚫 Push a producción bloqueado. Usa PR en Git.${NC}" && exit 1
case "$ENV" in
  stage) CONTAINER="${CONTAINER_STAGE:-honda-motoverso-stage-web}" ;;
  dev)   CONTAINER="${CONTAINER_DEV:-honda-motoverso-dev-web}" ;;
  *) echo -e "${RED}❌ Usa: dev | stage${NC}"; exit 1 ;;
esac
DOKPLOY_HOST="${DOKPLOY_SSH_HOST}"; DOKPLOY_PORT="${DOKPLOY_SSH_PORT:-2222}"
DOKPLOY_USER="${DOKPLOY_SSH_USER:-root}"
BACKUP_DIR=".backups"; DATE=$(date +"%Y%m%d_%H%M%S"); mkdir -p "$BACKUP_DIR"
DUMP_GZ="$BACKUP_DIR/honda_motoverso_local_${DATE}.sql.gz"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  📤 Push DB → $ENV                     ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}⚠️  Sobreescribirá BD del entorno '$ENV' en Dokploy.${NC}"
read -p "   ¿Confirmas? (escribe 'si'): " C
[[ "$C" != "si" ]] && echo -e "${YELLOW}Cancelado.${NC}" && exit 0
echo -e "${YELLOW}⏳ Exportando BD local...${NC}"
docker compose exec -T web bash -c "cd /opt/drupal && drush sql-dump" | gzip > "$DUMP_GZ"
[ ! -s "$DUMP_GZ" ] && echo -e "${RED}❌ Error exportando BD${NC}" && exit 1
echo -e "${GREEN}✅ Exportada: $DUMP_GZ ($(du -sh $DUMP_GZ | cut -f1))${NC}"
echo -e "${YELLOW}📤 Subiendo e importando en $ENV...${NC}"
gunzip -c "$DUMP_GZ" | \
  ssh -o StrictHostKeyChecking=no -p "$DOKPLOY_PORT" "$DOKPLOY_USER@$DOKPLOY_HOST" \
    "docker exec -i $CONTAINER bash -c \
      'cd /opt/drupal && drush sql-drop -y && drush sql-cli && drush cr'"
[ $? -ne 0 ] && echo -e "${RED}❌ Error importando${NC}" && exit 1
echo -e "${GREEN}✅ BD subida a '$ENV'!${NC}"
