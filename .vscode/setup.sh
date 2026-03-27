#!/bin/bash
# ─────────────────────────────────────────────────────────────
# honda-motoverso — Setup inicial del desarrollador
# Uso: bash .vscode/setup.sh
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

[ ! -f "docker-compose.yml" ] && \
  echo -e "${RED}❌ Ejecuta desde la raíz del proyecto${NC}" && exit 1

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  🚀 honda-motoverso — Setup inicial     ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── .env ─────────────────────────────────────────────────────
echo -e "${CYAN}[1/4] Configurando .env...${NC}"
if [ ! -f ".env" ]; then
  cp .env.example .env
  HASH=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
  sed -i.bak "s|CAMBIAR_HASH_64_CARACTERES|$HASH|g" .env && rm -f .env.bak
  echo ""
  echo -e "${YELLOW}🔑 Tu llave SSH pública (cat ~/.ssh/id_ed25519.pub):${NC}"
  read -r SSH_KEY
  [ -n "$SSH_KEY" ] && \
    sed -i.bak "s|SSH_PUBLIC_KEY=|SSH_PUBLIC_KEY=$SSH_KEY|" .env && rm -f .env.bak
  echo -e "${GREEN}✅ .env generado${NC}"
else
  echo -e "${GREEN}✅ .env ya existe${NC}"
fi
source .env 2>/dev/null

# ── Docker ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[2/4] Verificando Docker...${NC}"
command -v docker &>/dev/null || \
  { echo -e "${RED}❌ Docker no instalado → https://www.docker.com/products/docker-desktop/${NC}"; exit 1; }
echo -e "${GREEN}✅ Docker OK${NC}"

# ── Levantar contenedores ────────────────────────────────────
echo ""
echo -e "${CYAN}[3/4] Levantando contenedores...${NC}"
docker compose up -d --build
[ $? -ne 0 ] && echo -e "${RED}❌ Error levantando contenedores${NC}" && exit 1

# ── Esperar DB ───────────────────────────────────────────────
echo ""
echo -e "${CYAN}[4/4] Esperando base de datos...${NC}"
RETRIES=20
until docker compose exec db mysqladmin ping -u"${DB_USER:-drupal}" \
      -p"${DB_PASS:-drupal}" --silent 2>/dev/null; do
  RETRIES=$((RETRIES-1))
  [ $RETRIES -eq 0 ] && echo -e "${RED}❌ Timeout BD${NC}" && exit 1
  echo -e "  ${YELLOW}⏳ ($RETRIES intentos restantes)${NC}"; sleep 3
done
echo -e "${GREEN}✅ Base de datos lista${NC}"

# ── Importar BD ──────────────────────────────────────────────
echo ""
echo -e "${CYAN}¿Importar BD ahora?${NC}"
echo -e "  ${GREEN}1)${NC} Pull desde main (producción)"
echo -e "  ${GREEN}2)${NC} Pull desde dev"
echo -e "  ${GREEN}3)${NC} Instalar Drupal desde cero"
echo -e "  ${GREEN}4)${NC} Omitir"
read -p "  Selecciona (1-4): " OPT
case $OPT in
  1) bash .vscode/pull-db.sh main ;;
  2) bash .vscode/pull-db.sh dev ;;
  3)
    echo -e "${YELLOW}⏳ Instalando Drupal...${NC}"
    docker compose exec web drush site:install \
      --account-name=admin --account-pass=admin \
      --site-name="Honda Motoverso" -y
    echo -e "${GREEN}✅ Drupal instalado — admin / admin${NC}"
    ;;
  *) echo -e "${YELLOW}Omitido.${NC}" ;;
esac

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Setup completo!                     ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🌐 Sitio       : ${CYAN}http://localhost:4000${NC}"
echo -e "  🗄️  phpMyAdmin  : ${CYAN}http://localhost:8081${NC}"
echo -e "  📥 Pull BD     : ${CYAN}bash .vscode/pull-db.sh main${NC}"
echo -e "  📁 Pull files  : ${CYAN}bash .vscode/pull-files.sh main${NC}"
echo -e "  🔧 Drush local : ${CYAN}bash .vscode/drush.sh cr${NC}"
echo -e "  🔧 Drush remoto: ${CYAN}bash .vscode/drush.sh main cr${NC}"
echo -e "  🖥️  Terminal    : ${CYAN}bash .vscode/ssh.sh${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
