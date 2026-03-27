#!/bin/bash
# drush.sh — honda-motoverso
# Local:  bash .vscode/drush.sh cr
# Remoto: bash .vscode/drush.sh main cr
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -f ".env" ] && export $(grep -v '^#' .env | xargs 2>/dev/null)
DOKPLOY_HOST="${DOKPLOY_SSH_HOST}"; DOKPLOY_PORT="${DOKPLOY_SSH_PORT:-2222}"
DOKPLOY_USER="${DOKPLOY_SSH_USER:-root}"
[ -z "$1" ] && echo -e "${BLUE}Uso:${NC} bash .vscode/drush.sh [entorno] <comando>" && exit 0
ENVS=("main" "live" "stage" "dev"); IS_REMOTE=false
for e in "${ENVS[@]}"; do
  if [[ "$1" == "$e" ]]; then IS_REMOTE=true; ENV=$1; shift; break; fi
done
DRUSH_CMD="$@"
if [ "$IS_REMOTE" = true ]; then
  case "$ENV" in
    main|live) C="${CONTAINER_MAIN:-honda-motoverso-web}" ;;
    stage)     C="${CONTAINER_STAGE:-honda-motoverso-stage-web}" ;;
    dev)       C="${CONTAINER_DEV:-honda-motoverso-dev-web}" ;;
  esac
  echo -e "${BLUE}🔧 Drush REMOTO${NC} [$ENV] → ${CYAN}drush $DRUSH_CMD${NC}"
  echo ""
  ssh -t -o StrictHostKeyChecking=no -p "$DOKPLOY_PORT" "$DOKPLOY_USER@$DOKPLOY_HOST" \
    "docker exec -it $C bash -c 'cd /opt/drupal && drush $DRUSH_CMD'"
else
  echo -e "${BLUE}🔧 Drush LOCAL${NC} → ${CYAN}drush $DRUSH_CMD${NC}"
  echo ""
  docker compose exec web bash -c "cd /opt/drupal && drush $DRUSH_CMD"
fi
