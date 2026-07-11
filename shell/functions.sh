#!/bin/bash

# functions.sh - Funciones de desarrollo integradas
# Agregar a ~/.bashrc o ~/.zshrc: source ~/functions.sh

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables globales
CURRENT_USER=$(whoami)
DEV_BASE_DIR="$HOME/workspace/github.com/$CURRENT_USER"

# Funciones de logging
log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# =============================================================================
# FUNCIONES DE NAVEGACIÓN Y GESTIÓN DE DIRECTORIOS
# =============================================================================

# Función para ir al directorio de desarrollo
devdir() {
    cd "$DEV_BASE_DIR" || {
        log_error "Directorio de desarrollo no encontrado: $DEV_BASE_DIR"
        return 1
    }
}

# Función para cambiar a un proyecto específico
cdp() {
    local project_name=$1
    
    if [ -z "$project_name" ]; then
        log_error "Uso: cdp <nombre-proyecto>"
        return 1
    fi
    
    local project_path="$DEV_BASE_DIR/$project_name"
    
    if [ -d "$project_path" ]; then
        cd "$project_path"
        log_success "Cambiado a proyecto: $project_name"
        
        # Activar virtual environment automáticamente si existe
        if [ -f "venv/bin/activate" ]; then
            source venv/bin/activate
            log_info "Virtual environment activado"
        fi
    else
        log_error "Proyecto no encontrado: $project_name"
        log_info "Proyectos disponibles:"
        lsdev
        return 1
    fi
}

# Función para listar proyectos
lsdev() {
    if [ ! -d "$DEV_BASE_DIR" ]; then
        log_warning "Directorio de desarrollo no existe: $DEV_BASE_DIR"
        return 1
    fi
    
    log_info "Proyectos disponibles en $DEV_BASE_DIR:"
    find "$DEV_BASE_DIR" -maxdepth 1 -type d -not -path "$DEV_BASE_DIR" | \
    while read -r dir; do
        local project_name=$(basename "$dir")
        local git_status=""
        local venv_status=""
        
        # Verificar si es repositorio Git
        if [ -d "$dir/.git" ]; then
            git_status=" [Git]"
        fi
        
        # Verificar si tiene virtual environment
        if [ -d "$dir/venv" ]; then
            venv_status=" [venv]"
        fi
        
        echo "  📁 $project_name$git_status$venv_status"
    done
}

# =============================================================================
# FUNCIONES DE CLONADO DE REPOSITORIOS
# =============================================================================

# Función para clonar repositorio con estructura organizada
clone_repo() {
    local repo_url=$1
    local use_ssh=${2:-false}

    if [ -z "$repo_url" ]; then
        log_error "Uso: clone_repo <url-repositorio> [true|false para SSH]"
        return 1
    fi

    # Normalizar URL para extraer partes
    local normalized_url=$(echo "$repo_url" | sed -e 's/^https:\/\///' -e 's/^git@//' -e 's/:/\//')
    
    local host=$(echo "$normalized_url" | cut -d'/' -f1)
    local org=$(echo "$normalized_url" | cut -d'/' -f2)
    local repo=$(echo "$normalized_url" | cut -d'/' -f3 | sed 's/.git$//')

    if [ -z "$host" ] || [ -z "$org" ] || [ -z "$repo" ]; then
        log_error "No se pudo parsear la URL del repositorio: $repo_url"
        return 1
    fi

    local target_dir="$HOME/workspace/$host/$org/$repo"

    log_info "Clonando en: $target_dir"
    mkdir -p "$(dirname "$target_dir")"

    if [ "$use_ssh" = "true" ]; then
        repo_url="git@$host:$org/$repo.git"
    fi

    git clone "$repo_url" "$target_dir" && {
        cd "$target_dir"
        log_success "Repositorio clonado exitosamente"
    }
}

# Función para clonar repositorio shorthand (user/repo)
clone_short() {
    local shorthand=$1
    local use_ssh=${2:-false}
    
    if [ -z "$shorthand" ]; then
        log_error "Uso: clone_short <usuario/repositorio> [true|false para SSH]"
        return 1
    fi
    
    # Determinar host (default github.com)
    local host="github.com"
    local path="$shorthand"
    
    if [[ $shorthand == *"/"*"/"* ]]; then
        host=$(echo "$shorthand" | cut -d'/' -f1)
        path=$(echo "$shorthand" | cut -d'/' -f2-)
    fi
    
    local org=$(echo "$path" | cut -d'/' -f1)
    local repo=$(echo "$path" | cut -d'/' -f2)
    
    local target_dir="$HOME/workspace/$host/$org/$repo"
    
    if [[ $use_ssh == "true" ]]; then
        local url="git@$host:$org/$repo.git"
    else
        local url="https://$host/$org/$repo.git"
    fi
    
    log_info "Clonando: $url"
    mkdir -p "$(dirname "$target_dir")"
    git clone "$url" "$target_dir" && {
        cd "$target_dir"
        log_success "Repositorio clonado exitosamente"
    }
}

# =============================================================================
# FUNCIÓN PRINCIPAL DE CREACIÓN DE PROYECTOS DJANGO
# =============================================================================

# Función para crear nuevo proyecto Django
create_django_project() {
    local project_name=""
    local with_docker=false
    local skip_git=false
    
    # Parse argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-docker)
                with_docker=true
                shift
                ;;
            --skip-git)
                skip_git=true
                shift
                ;;
            -*)
                log_error "Opción desconocida: $1"
                return 1
                ;;
            *)
                if [ -z "$project_name" ]; then
                    project_name=$1
                else
                    log_error "Múltiples nombres de proyecto especificados"
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$project_name" ]; then
        log_error "Uso: create_django_project <project-name> [--with-docker] [--skip-git]"
        return 1
    fi
    
    # Validar nombre del proyecto
    if [[ ! "$project_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        log_error "Nombre del proyecto debe empezar con letra minúscula y contener solo letras, números y guiones"
        return 1
    fi
    
    local project_path="$DEV_BASE_DIR/$project_name"
    local django_app_name=$(echo "$project_name" | tr '-' '_')
    
    # Verificar dependencias
    _check_django_dependencies || return 1
    
    # Verificar que no exista el proyecto
    if [ -d "$project_path" ]; then
        log_error "El proyecto '$project_name' ya existe en $project_path"
        return 1
    fi
    
    log_info "🚀 Creando proyecto Django: $project_name"
    
    # Crear estructura
    _create_django_structure "$project_path" "$project_name" "$django_app_name" "$with_docker" "$skip_git"
    
    log_success "✅ Proyecto Django creado exitosamente!"
    log_info "Ubicación: $project_path"
    log_info ""
    log_info "Próximos pasos:"
    log_info "1. cd $project_path"
    log_info "2. ./scripts/setup.sh"
    log_info "3. source venv/bin/activate"
    log_info "4. python src/manage.py migrate"
    log_info "5. python src/manage.py createsuperuser"
    log_info "6. python src/manage.py runserver"
}

# =============================================================================
# FUNCIONES AUXILIARES PARA CREACIÓN DE PROYECTOS
# =============================================================================

# Función para verificar dependencias
_check_django_dependencies() {
    log_info "Verificando dependencias..."
    
    local deps=("git" "python3" "pip3")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Dependencias faltantes: ${missing_deps[*]}"
        log_info "Instalar con: sudo apt update && sudo apt install ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Función principal para crear estructura
_create_django_structure() {
    local project_path=$1
    local project_name=$2
    local django_app_name=$3
    local with_docker=$4
    local skip_git=$5
    
    # Crear directorio base
    mkdir -p "$DEV_BASE_DIR"
    mkdir -p "$project_path"
    cd "$project_path"
    
    # Crear estructura de directorios
    mkdir -p {docs,scripts,src}
    mkdir -p src/{apps,core,logs,media,static,tests}
    
    # Inicializar Git
    if [ "$skip_git" != "true" ]; then
        git init
        _configure_git
    fi
    
    # Crear archivos base
    _create_tool_versions
    _create_gitignore
    _create_readme "$project_name" "$django_app_name"
    _create_env_example "$project_name" "$django_app_name"
    _create_requirements
    
    # Crear proyecto Django
    _setup_django_project "$project_name" "$django_app_name"
    
    # Crear scripts de automatización
    _create_automation_scripts "$project_name"
    
    # Crear archivos Docker si se solicita
    if [ "$with_docker" = "true" ]; then
        _create_docker_files "$project_name"
        _create_infrastructure_files "$project_name"
    fi
    
    
    # Commit inicial
    if [ "$skip_git" != "true" ]; then
        git add .
        git commit -m "Initial commit: Django project structure"
    fi
}

# Función para configurar Git
_configure_git() {
    if ! git config --global user.name &>/dev/null; then
        git config --global user.name "$CURRENT_USER"
    fi
    
    if ! git config --global user.email &>/dev/null; then
        git config --global user.email "${CURRENT_USER}@example.com"
    fi

    if ! git config --global init.defaultBranch &>/dev/null; then
        git config --global init.defaultBranch "develop"
    fi
}

# Función para crear .gitignore
_create_gitignore() {
    cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# Django
*.log
local_settings.py
db.sqlite3
db.sqlite3-journal
mediafiles/
staticfiles/
static/admin/
static/rest_framework/

# Virtual Environment
virtualenv/
virtualenv-clone/
venv/
env/
ENV/
env.bak/
venv.bak/

# Environment variables
.env
.env.local
.env.staging
.env.production

# IDEs
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Logs
logs/
*.log

# Coverage
coverage/
*.cover
.coverage
.coverage.*
.cache
.pytest_cache/

# Backup files
*.bak
*.backup
*.tmp
backups/

# Local data
tmp/
temp/
uploads/

# Docker
.dockerignore
docker-compose.override.yml

# Infrastructure secrets
infrastructure/secrets/
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl

# Node.js
node_modules/
npm-debug.log*
package-lock.json
yarn.lock
EOF
}

# Función para crear README.md
_create_readme() {
    local project_name=$1
    local django_app_name=$2
    
    cat > README.md << EOF
# $project_name

Descripción breve del proyecto Django.

## Características

- Django con SQLite en desarrollo
- PostgreSQL en producción
- Nginx como servidor web
- Despliegue en LXC Ubuntu 24.04

## Instalación Rápida

\`\`\`bash
# Activar el proyecto
cdp $project_name

# Setup automático
./scripts/setup.sh

# Iniciar desarrollo
python src/manage.py runserver
\`\`\`

## Scripts Disponibles

- 
xargs -I {} echo "  - {}" <<< "./scripts/setup.sh - Configuración inicial"
- 
xargs -I {} echo "  - {}" <<< "./scripts/deploy.sh - Despliegue"
- 
xargs -I {} echo "  - {}" <<< "./scripts/backup.sh - Respaldo"
- 
xargs -I {} echo "  - {}" <<< "./scripts/test.sh - Tests"

## Desarrollo

\`\`\`bash
# Activar virtual environment
source venv/bin/activate

# Migraciones
python src/manage.py makemigrations
python src/manage.py migrate

# Crear superusuario
python src/manage.py createsuperuser

# Ejecutar tests
python src/manage.py test
\`\`\`

## Deployment

\`\`\`bash
# Staging
./scripts/deploy.sh staging

# Producción  
./scripts/deploy.sh production
\`\`\`
EOF
}

# Función para crear .env.example
_create_env_example() {
    local project_name=$1
    local django_app_name=$2
    
    cat > .env.example << EOF
# Configuración del proyecto
PROJECT_NAME=$project_name
ENVIRONMENT=development
DEBUG=True

# Django
SECRET_KEY=your-secret-key-here
ALLOWED_HOSTS=localhost,127.0.0.1
DJANGO_SETTINGS_MODULE=${django_app_name}.settings

# Base de datos - Desarrollo (SQLite)
DB_ENGINE=django.db.backends.sqlite3
DB_NAME=db.sqlite3

# Base de datos - Producción (PostgreSQL)
# DB_ENGINE=django.db.backends.postgresql
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=${django_app_name}_prod
# DB_USER=postgres
# DB_PASSWORD=secure_password

# Static/Media files
STATIC_URL=/static/
STATIC_ROOT=/var/www/$project_name/static/
MEDIA_URL=/media/
MEDIA_ROOT=/var/www/$project_name/media/

# Deploy configuración
DEPLOY_USER=deploy
DEPLOY_HOST=your-server.com
DEPLOY_PATH=/var/www/$project_name
HEALTH_CHECK_URL=https://your-domain.com/health/

# Backup configuración
BACKUP_RETENTION_DAYS=30
AWS_S3_BUCKET=${project_name}-backups
REMOTE_BACKUP_HOST=backup.your-domain.com
REMOTE_BACKUP_PATH=/backups/$project_name

# Notificaciones
SLACK_WEBHOOK_URL=
NOTIFICATION_EMAIL=admin@your-domain.com
EOF
}

# Función para crear requirements.txt
_create_requirements() {
    cat > requirements.txt << 'EOF'
# Django core
Django>
 djangorestframework

# Database
psycopg2-binary

# Environment
python-decouple

# Security
django-cors-headers

# Development
django-debug-toolbar

# Testing
pytest
pytest-django

# Production
gunicorn
whitenoise

# Utilities
Pillow
requests
EOF
}

# Función para crear un .tool-versions
_create_tool_versions() {
    cat > .tool-versions << 'EOF'
python 3.12.*
EOF
}

# Función para setup de Django
_setup_django_project() {
    local project_name=$1
    local django_app_name=$2
    
    # Crear virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Instalar Django
    pip install --upgrade pip
    pip install django
    
    # Crear proyecto Django
    django-admin startproject core src
    
    # Mover la carpeta del proyecto a src
    mv ./src/core ./src/
    
    # Instalar requirements
    pip install -r requirements.txt
    
    # Crear apps directory
    mkdir -p src/apps
    touch src/apps/__init__.py
    
    log_success "Proyecto Django configurado"
}

# Función para crear scripts de automatización
_create_automation_scripts() {
    local project_name=$1
    
    # Crear scripts básicos (versiones simplificadas)
    cat > scripts/setup.sh << 'EOF'
#!/bin/bash
set -euo pipefail

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

log_info "Configurando proyecto..."

# Activar virtual environment
if [ ! -d "venv" ]; then
    python3 -m venv venv
    log_success "Virtual environment creado"
fi

source venv/bin/activate

# Instalar dependencias
pip install --upgrade pip
pip install -r requirements.txt
log_success "Dependencias instaladas"

# Crear .env si no existe
if [ ! -f ".env" ] && [ ! -f ".env.example" ]; then
    cp .env.example .env
    log_success "Archivo .env creado desde template"
fi

# Ejecutar migraciones
cd src
python manage.py migrate
log_success "Migraciones ejecutadas"

# Crear directorios necesarios
mkdir -p ../logs ../media ../static
log_success "Directorios creados"

log_success "Setup completado! Ejecuta: python src/manage.py runserver"
EOF

    cat > scripts/dev.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
cd src
python manage.py runserver
EOF

    cat > scripts/test.sh << 'EOF'
#!/bin/bash
source venv/bin/activate
cd src
python manage.py test
EOF

    chmod +x scripts/*.sh
}

# Función para crear archivos Docker
_create_docker_files() {
    local project_name=$1
    
    mkdir -p docker
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código
COPY . .

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "src.config.wsgi:application"]
EOF

    cat > docker-compose.yml << EOF
version: '3.8'

services:
  web:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - ./src:/app/src
    environment:
      - DEBUG=True
    depends_on:
      - db

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=${project_name}
      - POSTGRES_USER=postgres  
      - POSTGRES_PASS=password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
EOF
}

# Función para crear archivos de infraestructura
_create_infrastructure_files() {
    local project_name=$1
    
    mkdir -p docker/nginx
    cat > docker/nginx/default.conf << EOF
upstream django {
    server 127.0.0.1:8000;
}

server {
    listen 80;
    server_name your-domain.com;
    
    location /static/ {
        alias /var/www/$project_name/static/;
    }
    
    location /media/ {
        alias /var/www/$project_name/media/;
    }
    
    location / {
        proxy_pass http://django;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
}

# =============================================================================
# ALIASES Y SHORTCUTS
# =============================================================================

# Aliases para facilitar el uso
alias djcreate='create_django_project'
alias clone='clone_repo'
alias clones='clone_short'
alias projects='lsdev'

# =============================================================================
# FUNCIÓN DE AYUDA
# =============================================================================

# Función de ayuda
dev_help() {
    echo -e "${BLUE}Funciones de desarrollo disponibles:${NC}"
    echo ""
    echo -e "${GREEN}Navegación:${NC}"
    echo "  dev                    - Ir al directorio de desarrollo"
    echo "  cdp <proyecto>         - Cambiar a proyecto específico"
    echo "  lsdev | projects       - Listar proyectos disponibles"
    echo ""
    echo -e "${GREEN}Repositorios:${NC}"
    echo "  clone_repo <url>       - Clonar repositorio con estructura organizada"
    echo "  clone_short <user/repo> - Clonar usando formato corto"
    echo "  clone <url>            - Alias para clone_repo"
    echo "  clones <user/repo>     - Alias para clone_short"
    echo ""
    echo -e "${GREEN}Proyectos Django:${NC}"
    echo "  create_django_project <nombre> [--with-docker] [--skip-git]"
    echo "  djcreate <nombre>      - Alias para crear proyecto Django"
    echo ""
    echo -e "${GREEN}Ejemplos:${NC}"
    echo "  djcreate mi-blog"
    echo "  djcreate ecommerce --with-docker"
    echo "  clone_short django/django"
    echo "  cdp mi-blog"
}

# Mostrar ayuda al cargar
echo -e "${BLUE}Funciones de desarrollo cargadas. Usa 'dev_help' para ver comandos disponibles."
