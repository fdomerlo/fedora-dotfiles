![status](https://img.shields.io/badge/status-active-success)
![platform](https://img.shields.io/badge/platform-linux-blue)
![shell](https://img.shields.io/badge/shell-zsh-green)

# 🚀 Fedora Develop Environment

Plataforma de desarrollo portable basada en:

- Fedora Workstation (host)
- Podman + Distrobox (entornos reproducibles)
- devctl (CLI unificada)
- BTRFS + Snapper + zram + swap fallback

---

## 🧠 Filosofía

Este proyecto separa claramente:

- 🧱 Host → mínimo, descartable
- 📦 Boxes → donde vive el entorno real
- 📁 Proyectos → reproducibles

> ❗ El entorno NO vive en el sistema operativo.

---

## ⚡ Instalación (One-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/fdomerlo/fedora-dev-env/main/bootstrap.sh | bash
````

---

## 🔐 Seguridad (recomendado)

Revisar antes de ejecutar:

```bash
curl -fsSL https://raw.githubusercontent.com/fdomerlo/fedora-dev-env/main/bootstrap.sh
```

---

## ⚙️ Instalación manual

```bash
git clone https://github.com/fdomerlo/fedora-dev-env.git
cd fedora-dev-env
./install.sh
```

---

## 🤖 Modo no interactivo (CI / power users)

```bash
curl -fsSL https://raw.githubusercontent.com/fdomerlo/fedora-dev-env/main/bootstrap.sh | NON_INTERACTIVE=true bash
```

---

## 🧱 Setup inicial

```bash
devctl host setup
devctl host snapper
devctl host swap
```

---

## 📦 Entornos (boxes)

```bash
devctl box build python
devctl box create python

devctl box build php
devctl box create php
```

---

## 💻 Uso diario

Entrar al entorno:

```bash
devctl box enter python
```

---

## 🚀 Crear proyecto Django

```bash
mkdir myproject
cd myproject

devctl project init django
direnv allow
```

---

## 🔧 Comandos principales

### 🧱 Host

```bash
devctl host setup
devctl host snapper
devctl host swap
```

---

### 📦 Boxes

```bash
devctl box build python
devctl box create python
devctl box enter python
devctl box rebuild python
```

---

### 📁 Proyectos

```bash
devctl project init django
```

---

### 🧠 Sistema

```bash
devctl doctor
devctl upgrade
```

---

### 📦 Portabilidad

```bash
devctl box export python
devctl box import python.tar
```

---

## 🧪 Diagnóstico

```bash
devctl doctor
```

Valida:

* podman
* distrobox
* btrfs
* snapper
* swap / zram
* boxes existentes

---

## 🔄 Actualización

```bash
devctl upgrade
```

---

## 💻 Shell (Zsh)

Por defecto se instala una configuración mínima:

* rápida
* portable
* sin dependencias externas

---

## ✨ Oh My Zsh (opcional)

Para quienes lo necesiten:

```bash
devctl shell ohmyzsh
```

O desde el menú interactivo.

---

## 🧠 Reglas del equipo

### ❗ 1. No instalar tooling en el host

Todo debe vivir en boxes.

---

### ❗ 2. Nada manual

Todo debe ser reproducible vía scripts.

---

### ❗ 3. Nada dependiente de distro

Los entornos deben funcionar en cualquier Linux.

---

### ❗ 4. devctl es la fuente de verdad

Si no está en devctl, no existe.

---

## 🧱 Arquitectura

```
Host (Fedora)
 ├── podman
 ├── distrobox
 ├── snapper
 └── zsh

Boxes
 ├── dev-python
 ├── dev-php
 └── dev-ai (futuro)

Projects
 └── templates + direnv
```

---

## 🔥 Qué resuelve

* ❌ "funciona en mi máquina"
* ❌ setups manuales
* ❌ dependencia de distro
* ❌ entornos inconsistentes

---

## 🚀 Roadmap

* devctl doctor (extendido)
* registry de boxes
* integración con Proxmox
* entornos remotos
* cache distribuido

---

## 👨‍💻 Autor

Fernando Merlo
