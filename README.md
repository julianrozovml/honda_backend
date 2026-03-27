# honda-motoverso — Drupal 11 en Dokploy

## Persistencia de datos

```
┌─────────────────────────────────────────────────────────┐
│                    VPS / Dokploy                        │
│                                                         │
│  ┌──────────────────┐    ┌───────────────────────┐      │
│  │  Contenedor web  │    │   Contenedor db        │      │
│  │  (efímero)       │    │   (efímero)            │      │
│  │                  │    │                        │      │
│  │  Código Drupal ──┼────┼── del repo Git         │      │
│  │                  │    │                        │      │
│  └────────┬─────────┘    └──────────┬─────────────┘      │
│           │                         │                    │
│     monta │                   monta │                    │
│           ▼                         ▼                    │
│  ┌─────────────────┐    ┌───────────────────────┐        │
│  │ honda_motoverso │    │  honda_motoverso_db   │        │
│  │ _files          │    │                       │        │
│  │                 │    │  Base de datos        │        │
│  │ Imágenes        │    │  MariaDB              │        │
│  │ Uploads         │    │                       │        │
│  │ Files Drupal    │    │  PERSISTE SIEMPRE     │        │
│  │                 │    │                       │        │
│  │ PERSISTE SIEMPRE│    └───────────────────────┘        │
│  └─────────────────┘                                     │
│                                                         │
│  ⚠️  Los volúmenes sobreviven a:                        │
│     ✅ docker compose restart                           │
│     ✅ docker compose down && up                        │
│     ✅ Redeploy desde Dokploy                           │
│     ✅ Rebuild del Dockerfile                           │
│     ❌ docker volume rm honda_motoverso_files (manual)  │
└─────────────────────────────────────────────────────────┘
```

## Inicio rápido

```bash
git clone git@github.com:tu-org/honda-motoverso.git
cd honda-motoverso
bash .vscode/setup.sh
```

## Comandos del día a día

| Acción | Comando |
|--------|---------|
| Traer BD de producción | `bash .vscode/pull-db.sh main` |
| Traer files de producción | `bash .vscode/pull-files.sh main` |
| Subir BD a dev | `bash .vscode/push-db.sh dev` |
| Drush local | `bash .vscode/drush.sh cr` |
| Drush remoto | `bash .vscode/drush.sh main cr` |
| Terminal local | `bash .vscode/ssh.sh` |
| Terminal remota | `bash .vscode/ssh.sh main` |

> En VSCode: **Terminal → Run Task** para menú gráfico con todos los comandos.


## Gestión de llaves SSH — Múltiples desarrolladores

Cada desarrollador tiene su propia variable en el `.env` de Dokploy.
Así se puede agregar o revocar acceso sin tocar las demás llaves.

### Agregar un desarrollador nuevo

1. El desarrollador comparte su llave pública:
```bash
cat ~/.ssh/id_ed25519.pub
# → ssh-ed25519 AAAA... nombre@mac
```

2. Agregar en **Dokploy → Application → Environment Variables**:
```
SSH_KEY_JULIAN=ssh-ed25519 AAAA... julian@mac
```

3. Hacer redeploy en Dokploy — la llave queda activa.

### Revocar acceso a un desarrollador

Eliminar su variable `SSH_KEY_NOMBRE` en Dokploy y hacer redeploy.
Las demás llaves no se ven afectadas.

### Ejemplo de `.env` con 3 desarrolladores

```bash
SSH_KEY_JULIAN=ssh-ed25519 AAAA... julian@mac
SSH_KEY_ANDRES=ssh-ed25519 BBBB... andres@mac
SSH_KEY_CARLOS=ssh-ed25519 CCCC... carlos@mac
```

### Verificar llaves activas en el contenedor

```bash
bash .vscode/ssh.sh main
# Ya dentro del contenedor:
cat /root/.ssh/authorized_keys
```

## Estructura

```
honda-motoverso/
├── Dockerfile              ← PHP 8.3 + Apache + SSH + Drush
├── docker-compose.yml      ← Servicios + volúmenes persistentes
├── entrypoint.sh           ← SSH + settings + composer
├── composer.json           ← Dependencias (sin vendor en repo)
├── .env.example            ← Plantilla (sí versionar)
├── .gitignore
├── config/sync/            ← Config Drupal exportada ✅ Git
├── web/
│   ├── modules/custom/     ← Módulos propios ✅ Git
│   ├── themes/custom/      ← Temas propios ✅ Git
│   ├── sites/default/
│   │   ├── settings.php    ← Sin credenciales ✅ Git
│   │   ├── settings.local.php ← Auto-generado ❌ .gitignore
│   │   └── files/          ← Volumen Docker ❌ .gitignore
│   ├── core/               ← ❌ Composer
│   └── modules/contrib/    ← ❌ Composer
└── .vscode/
    ├── setup.sh            ← Primera vez
    ├── pull-db.sh          ← BD remota → local
    ├── pull-files.sh       ← Files remotos → local
    ├── push-db.sh          ← BD local → remoto (dev/stage)
    ├── drush.sh            ← Drush local y remoto
    ├── ssh.sh              ← Terminal local y remota
    └── tasks.json          ← Tareas VSCode
```

## Volúmenes Docker en el servidor

```bash
# Ver volúmenes existentes
docker volume ls | grep honda

# Inspeccionar volumen de files
docker volume inspect honda_motoverso_files

# Ruta física en el VPS
# /var/lib/docker/volumes/honda_motoverso_files/_data
# /var/lib/docker/volumes/honda_motoverso_db/_data
```
