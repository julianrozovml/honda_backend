#!/bin/bash
# ssh.sh — honda-motoverso
# Local:  bash .vscode/ssh.sh
# Remoto: bash .vscode/ssh.sh main|stage|dev
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
[ -f ".env" ] && export $(grep -v '^#' .env | xargs 2>/dev/null)
DOKPLOY_HOST="${DOKPLOY_SSH_HOST}"; DOKPLOY_PORT="${DOKPLOY_SSH_PORT:-2222}"
DOKPLOY_USER="${DOKPLOY_SSH_USER:-root}"
ENV="${1:-local}"
if [[ "$ENV" == "local" ]] || [ -z "$1" ]; then
  echo -e "${BLUE}🖥️  Terminal LOCAL${NC} — contenedor web"
  echo -e "${YELLOW}  'exit' para salir${NC}"; echo ""
  docker compose exec web bash -c "cd /opt/drupal && bash"
else
  case "$ENV" in
    main|live) C="${CONTAINER_MAIN:-honda-motoverso-web}" ;;
    stage)     C="${CONTAINER_STAGE:-honda-motoverso-stage-web}" ;;
    dev)       C="${CONTAINER_DEV:-honda-motoverso-dev-web}" ;;
    *) echo -e "${RED}❌ Usa: local | dev | stage | main${NC}"; exit 1 ;;
  esac
  echo -e "${BLUE}🖥️  Terminal REMOTA${NC} [$ENV] → $C"
  echo -e "${YELLOW}  'exit' para salir${NC}"; echo ""
  ssh -t -o StrictHostKeyChecking=no -p "$DOKPLOY_PORT" "$DOKPLOY_USER@$DOKPLOY_HOST" \
    "docker exec -it $C bash -c 'cd /opt/drupal && bash'"
fi
