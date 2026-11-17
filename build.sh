#!/bin/bash
# build.sh - Construcción de la ISO de KebianOS
#
# Uso:
#   ./build.sh -n   ISO normal (final): limpia todo, compresión xz
#   ./build.sh -p   ISO de prueba: rápida (gzip nivel 1), reutiliza la caché
#   ./build.sh -u   Sube los cambios al repositorio (git add/commit/push)

set -euo pipefail

# Trabajar siempre desde la carpeta donde está el script
cd "$(dirname "$(readlink -f "$0")")"

# Usar sudo solo si no somos root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

usage() {
    echo "Uso: $0 [-n | -p | -u]"
    echo "  -n  ISO normal (final, xz, limpia todo incluida la caché)"
    echo "  -p  ISO de prueba (rápida, gzip nivel 1, conserva la caché)"
    echo "  -u  Subir cambios a git"
    exit 1
}

# ---------------------------------------------------------------
# Dependencias: instala solo las que falten
# ---------------------------------------------------------------
check_deps() {
    local missing=()
    local pkg
    for pkg in live-build debootstrap xorriso squashfs-tools; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Faltan paquetes: ${missing[*]}. Instalando..."
        $SUDO apt update
        $SUDO apt install -y "${missing[@]}"
    fi
}

# ---------------------------------------------------------------
# Configuración común. Los argumentos extra se pasan a lb config.
# ---------------------------------------------------------------
lb_config() {
    $SUDO lb config \
        --distribution trixie \
        --architectures amd64 \
        --archive-areas "main contrib non-free non-free-firmware" \
        --debootstrap-options "--include=ca-certificates,apt-transport-https,gnupg" \
        --iso-application "KebianOS" \
        --iso-preparer "KebianOS Team" \
        --iso-publisher "KebianOS Team: https://kebianos.github.io/" \
        --image-name "KebianOS" \
        --bootappend-live "boot=live components quiet splash" \
        "$@"
}

# lb build guardando el log (pipefail hace que falle si lb build falla)
lb_build() {
    mkdir -p logs
    local log="logs/build-$(date +%Y-%m-%d_%H-%M-%S).log"
    echo "Creando ISO (log: $log)"
    $SUDO lb build 2>&1 | tee "$log"
    echo "ISO creada"
}

# ---------------------------------------------------------------
# Asegura que lo pesado no se suba a git
# ---------------------------------------------------------------
ensure_gitignore() {
    touch .gitignore
    local entry
    for entry in chroot/ cache/ binary/ .build/ logs/ '*.iso' 'live-image-*' '*.contents' '*.files' '*.packages'; do
        grep -qxF "$entry" .gitignore || echo "$entry" >> .gitignore
    done
}

# ---------------------------------------------------------------
# Modos
# ---------------------------------------------------------------
[ $# -ge 1 ] || usage

case "$1" in
    -n)
        check_deps
        echo "Live build en modo normal (final)"
        $SUDO lb clean --purge
        lb_config \
            --compression xz \
            --chroot-squashfs-compression-type xz \
            --initramfs-compression lzma
        lb_build
        ;;

    -p)
        check_deps
        echo "Creando ISO de prueba (rápida)"
        $SUDO lb clean
        lb_config \
            --compression gzip \
            --chroot-squashfs-compression-type gzip \
            --chroot-squashfs-compression-level 1 \
            --initramfs-compression gzip
        lb_build
        ;;

    -u)
        ensure_gitignore
        git add .
        # Solo hace commit si realmente hay cambios (si no, git commit falla)
        if git diff --cached --quiet; then
            echo "No hay cambios para subir"
        else
            git commit -m "KebianOS $(date +%Y-%m-%d_%H-%M)"
        fi
        git push origin main
        ;;

    *)
        usage
        ;;
esac
