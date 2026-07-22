![status](https://img.shields.io/badge/status-active-success)
![platform](https://img.shields.io/badge/platform-linux-blue)
![shell](https://img.shields.io/badge/shell-zsh-green)

# Fedora Dotfiles

Aprovisionamiento de desarrollo portable basada en Fedora Workstation, Podman, Distrobox y virtualización ligera.

* **Host:** Sistema base mínimo, limpio y descartable.
* **Boxes:** Contenedores donde vive el entorno de desarrollo real y sus dependencias.
* **Proyectos:** Directorios de trabajo locales mapeados de forma de desarrollo reproducible.

## Instalacion

### Opcion 1: Instalacion rapida (Recomendado)
Asegura las dependencias base, clona el repositorio y despliega la ayuda interactiva del Makefile:

```bash
sudo dnf install -y git make && git clone https://github.com/fdomerlo/fedora-dotfiles.git ~/.dotfiles && make -C ~/.dotfiles help
```

### Opcion 2: Instalacion manual

Si prefieres inspeccionar el contenido localmente antes de ejecutar el despliegue:

```bash
git clone [https://github.com/fdomerlo/fedora-dotfiles.git](https://github.com/fdomerlo/fedora-dotfiles.git) ~/.dotfiles
cd ~/.dotfiles
```

## Referencia de Comandos (devctl)

### Gestion de Boxes (Entornos de desarrollo)

Crea, destruye y administra contenedores Distrobox aislados por lenguaje o tecnología.

```bash
devctl box build python
devctl box create python
devctl box enter python
devctl box rebuild python
```

### Inicializacion de Proyectos

Configura plantillas locales y entornos virtuales integrados con direnv.

```bash
mkdir mi-proyecto && cd mi-proyecto
devctl project init django
direnv allow
```

### Mantenimiento y Diagnostico

```bash
devctl doctor     # Verifica dependencias, podman, snapper, swap y boxes activos
devctl upgrade    # Actualiza los scripts locales y reconstruye los entornos
```

### Portabilidad

```bash
devctl box export python
devctl box import python.tar
```

## Reglas del Entorno

1. **No instalar herramientas en el host:** Todo el tooling de desarrollo debe vivir estrictamente dentro de una Box.
2. **Evitar configuraciones manuales:** Cualquier cambio en el entorno debe ser reproducible mediante scripts o Dockerfiles.
3. **Independencia de la distribucion:** Las Boxes deben ser portables y capaces de correr en cualquier sistema Linux compatible con Podman y Distrobox.
4. **devctl como unica fuente de verdad:** Toda acción de automatización debe estar integrada en la CLI unificada.

## Diagnostico Integrado

El comando `devctl doctor` realiza las siguientes validaciones automáticas sobre el sistema de destino:

* Estado y permisos de ejecución de Podman y Distrobox.
* Configuración de subvolúmenes BTRFS y Snapper.
* Configuración y dimensionamiento de swap y zram.
* Integridad de las Boxes de desarrollo instaladas en el host.

---

Si este entorno te ha sido de utilidad para simplificar tu flujo de trabajo diario, considera otorgarle una **estrella (★)** al repositorio. Esto ayuda a mejorar la visibilidad del proyecto para que otros desarrolladores puedan encontrarlo y beneficiarse de él.
