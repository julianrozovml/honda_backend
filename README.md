# Honda Motoverso — Drupal 11 listo para Dokploy y local

Este repo quedó ajustado para dos usos:

1. **Dokploy con Docker Compose** para desplegar Drupal + MariaDB + phpMyAdmin.
2. **Docker local** para levantar el sitio rápido y, si lo deseas, instalar Drupal automáticamente.

## Qué cambió

- Se eliminó el volumen de `vendor` para no mezclar dependencias de Composer con despliegues nuevos.
- Se eliminaron `container_name` y nombres fijos de volúmenes/redes para evitar colisiones entre `dev`, `stage` y `prod` en el mismo servidor.
- Se añadió `docker-compose.local.yml` para puertos locales sin ensuciar la configuración de Dokploy.
- `entrypoint.sh` ahora puede esperar la base de datos e instalar Drupal automáticamente si `INSTALL_SITE=true`.
- Se añadió `.dockerignore` para acelerar los builds.

## Uso en Dokploy

### Tipo recomendado

Usa este repo como **Docker Compose service** si quieres que Drupal, MariaDB y phpMyAdmin queden juntos.

### Configuración sugerida

- **Provider**: GitHub
- **Compose type**: Docker Compose
- **Compose path**: `./docker-compose.yml`
- **Auto Deploy**: activado
- **Branch**: una por ambiente (`develop`, `staging`, `main`)
- **Domains**: configúralos desde la UI de Dokploy

### Variables de entorno

Copia `.env.example` a la sección de variables en Dokploy y cambia lo sensible.

## Uso local

```bash
cp .env.example .env
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build -d
```

Luego abre:

- Drupal: `http://localhost:8080`
- phpMyAdmin: `http://localhost:8081`

### Instalación automática

Si `INSTALL_SITE=true` y la base está vacía, el contenedor instala Drupal al arrancar.

Para instalación estándar:

```env
INSTALL_SITE=true
INSTALL_FROM_CONFIG=false
```

Para instalación desde configuración sincronizada:

```env
INSTALL_SITE=true
INSTALL_FROM_CONFIG=true
```

## Reiniciar desde cero en local

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml down -v
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build -d
```

## Notas

- En Dokploy, configura los dominios desde la UI en vez de meter labels manuales en el compose.
- Si más adelante separas la base de datos a un servicio gestionado, este repo se puede migrar fácil a una Application con Dockerfile.
