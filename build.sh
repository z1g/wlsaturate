#!/usr/bin/env bash
# Build (and optionally install) wlsaturation for Plasma 6 / KWin Wayland.
# Rebuild on EACH machine — do not copy build/ between hosts (KWin ABI).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Default outside this folder so Nextcloud does not sync object files.
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/wlsaturation-build}"
PREFIX="${PREFIX:-/usr}"
JOBS="$(nproc)"

DEPS_ARCH=(
  base-devel
  cmake
  extra-cmake-modules
  vulkan-headers
  qt6-base
  qt6-tools
  kconfig
  kcoreaddons
  kwin
  python
  kscreen
  python-pyqt6
)

install_user_menu() {
  local gui="$ROOT/tools/wlsaturation-gui"
  local dest="${XDG_DATA_HOME:-$HOME/.local/share}/applications/wlsaturation-gui.desktop"
  local src="$ROOT/data/wlsaturation-gui.desktop"
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$src" ]]; then
    echo "missing $src" >&2
    return 1
  fi
  chmod +x "$gui"
  # Absolute Exec so Kickoff works without cmake --install / PATH.
  sed -e "s|^Exec=.*|Exec=$gui|" -e "s|^TryExec=.*|TryExec=$gui|" "$src" >"$dest"
  command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$dest")" >/dev/null 2>&1 || true
  command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
  echo "KDE menu entry: $dest"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--deps] [--install] [--reload] [--menu]

  --deps      Install Arch/CachyOS build + GUI runtime packages (sudo pacman)
  --install   sudo cmake --install into PREFIX (default $PREFIX)
              also installs the default menu file to share/applications
  --reload    unload/load the KWin effect after install
  --menu      user Kickoff entry (~/.local/share/applications), no sudo
              Exec points at this tree's tools/wlsaturation-gui

Environment:
  BUILD_DIR   CMake build directory (default: $HOME/.cache/wlsaturation-build)
  PREFIX      CMAKE_INSTALL_PREFIX (default: /usr)

Examples:
  ./build.sh
  ./build.sh --menu
  ./build.sh --deps --install --reload
  BUILD_DIR=./build ./build.sh          # local build/ (do not sync this)
EOF
}

DO_DEPS=0
DO_INSTALL=0
DO_RELOAD=0
DO_MENU=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --deps) DO_DEPS=1 ;;
    --install) DO_INSTALL=1 ;;
    --reload) DO_RELOAD=1 ;;
    --menu) DO_MENU=1 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$DO_DEPS" -eq 1 ]]; then
  if ! command -v pacman >/dev/null; then
    echo "pacman not found; install KWin 6 / Qt6 / KF6 / python-pyqt6 with your distro tools." >&2
    exit 1
  fi
  # Install missing packages only. `pacman -S --needed kwin` still *upgrades*
  # kwin when the repo is ahead of the running Plasma (6.7 desktop + 6.8 kwin
  # = kwin_wayland symbol error / black SDDM greeter).
  echo "Checking build deps (will not upgrade already-installed packages):"
  missing=()
  for p in "${DEPS_ARCH[@]}"; do
    if pacman -Q "$p" >/dev/null 2>&1; then
      echo "  keep $(pacman -Q "$p")"
    else
      echo "  missing $p"
      missing+=("$p")
    fi
  done
  if ((${#missing[@]})); then
    sudo pacman -S --needed "${missing[@]}"
  else
    echo "All build packages already installed."
  fi
fi

# --menu alone just writes the Kickoff entry (no compiler needed).
NEED_BUILD=0
if [[ "$DO_INSTALL" -eq 1 || "$DO_RELOAD" -eq 1 || "$DO_DEPS" -eq 1 ]]; then
  NEED_BUILD=1
fi
if [[ "$DO_MENU" -eq 0 && "$DO_INSTALL" -eq 0 && "$DO_RELOAD" -eq 0 && "$DO_DEPS" -eq 0 ]]; then
  NEED_BUILD=1
fi

if [[ "$NEED_BUILD" -eq 1 ]]; then
  cmake -S "$ROOT" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
  cmake --build "$BUILD_DIR" -j"$JOBS"
fi

if [[ "$DO_INSTALL" -eq 1 ]]; then
  sudo cmake --install "$BUILD_DIR"
fi

if [[ "$DO_RELOAD" -eq 1 ]]; then
  qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect wlsaturation || true
  qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect wlsaturation
fi

if [[ "$DO_MENU" -eq 1 ]]; then
  install_user_menu
fi

echo
if [[ "$NEED_BUILD" -eq 1 ]]; then
  echo "Built in $BUILD_DIR"
fi
if [[ "$DO_INSTALL" -eq 1 ]]; then
  echo "Installed CLI/GUI: wlsaturation / wlsaturation-gui"
  echo "System menu: ${PREFIX}/share/applications/wlsaturation-gui.desktop"
fi
if [[ "$DO_MENU" -eq 1 ]]; then
  echo "User menu: wlsaturation (Kickoff search)"
elif [[ "$DO_INSTALL" -eq 0 ]]; then
  echo "GUI from this tree: $ROOT/tools/wlsaturation-gui"
  echo "Kickoff entry: $0 --menu"
  echo "System install: $0 --install --reload"
fi
