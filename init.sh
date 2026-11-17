#!/bin/bash

set -e

RESET=0
if [ "$1" = "--reset" ]; then
  RESET=1
  WORK_DIR="$2"
else
  WORK_DIR="$1"
  if [ "$2" = "--reset" ]; then
    RESET=1
  fi
fi

if [ -z "$WORK_DIR" ]; then
  echo -e "\033[1;31m[✘] Usage: $0 [--reset] <work_dir>\033[0m"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

reset_environment() {
  echo -e "\033[1;34m[…] Resetting dev environment changes...\033[0m"

  rm -rf "$WORK_DIR/.glibc-2.41" "$WORK_DIR/.bin/.nvim" "$WORK_DIR/.bin/.git" "$WORK_DIR/.bin/.src" "$WORK_DIR/.bin/.sysroot"

  if [ -d "$WORK_DIR/.bin" ]; then
    rm -f "$WORK_DIR/.bin/nvim" "$WORK_DIR/.bin/git" "$WORK_DIR/.bin/gitk" "$WORK_DIR/.bin/git-cvsserver" "$WORK_DIR/.bin/scalar"
    rm -f "$WORK_DIR/.bin/git-receive-pack" "$WORK_DIR/.bin/git-upload-archive" "$WORK_DIR/.bin/git-upload-pack"
    if [ -d "$SCRIPT_DIR/tools-bin" ]; then
      find "$SCRIPT_DIR/tools-bin" -mindepth 1 -maxdepth 1 -exec sh -c 'rm -rf "$1/.bin/$(basename "$2")"' sh "$WORK_DIR" {} \;
    fi
    rmdir "$WORK_DIR/.bin" 2>/dev/null || true
  fi

  if [ -f "$HOME/.zshrc" ]; then
    sed -i "\|$WORK_DIR/.bin|d" "$HOME/.zshrc"
    sed -i '/^export EDITOR=nvim$/d' "$HOME/.zshrc"
    sed -i '/^export PAGER=delta$/d' "$HOME/.zshrc"
    sed -i '/^setopt ignore_eof$/d' "$HOME/.zshrc"
    sed -i 's|^ZSH_THEME="powerlevel10k/powerlevel10k"|ZSH_THEME="robbyrussell"|' "$HOME/.zshrc"
    sed -i 's/^plugins=(git zsh-autosuggestions zsh-syntax-highlighting z zsh-vi-mode)/plugins=(git)/' "$HOME/.zshrc"
    sed -i '/^ZVM_INIT_MODE=sourcing$/d' "$HOME/.zshrc"
    sed -i '\|eval "$(atuin init zsh --disable-up-arrow)"|d' "$HOME/.zshrc"
  fi

  rm -rf "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  rm -rf "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  rm -rf "$HOME/.oh-my-zsh/custom/plugins/zsh-vi-mode"
  rm -rf "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  if [ -L "$HOME/.tmux.conf" ]; then
    rm -f "$HOME/.tmux.conf"
  fi
  rm -rf "$HOME/.tmux"
  rm -f "$HOME/.tmux.conf.local"

  rm -rf "$HOME/.config/nvim"
  rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"

  # Only drop the config this script installs; installed packages under
  # ~/.local/share/soar are user data and are left alone.
  rm -f "$HOME/.config/soar/config.toml"
  rmdir "$HOME/.config/soar" 2>/dev/null || true

  git config --global --unset core.pager 2>/dev/null || true
  git config --global --unset interactive.diffFilter 2>/dev/null || true
  git config --global --unset delta.navigate 2>/dev/null || true
  git config --global --unset delta.side-by-side 2>/dev/null || true
  git config --global --unset merge.conflictstyle 2>/dev/null || true

  echo -e "\033[1;32m[✔] Reset complete\033[0m"
}

if [ "$RESET" -eq 1 ]; then
  reset_environment
  exit 0
fi

mkdir -p "$WORK_DIR"

# Network check
if curl -sfL --connect-timeout 5 https://www.google.com -o /dev/null; then
  echo -e "\033[1;32m[✔] Network OK (google reachable)\033[0m"
else
  echo -e "\033[1;31m[✘] ERROR: Cannot reach google, check network/proxy\033[0m"
  exit 1
fi

# Copy glibc and tools-bin to work directory
if [ -d "$WORK_DIR/.glibc-2.41" ]; then
  echo -e "\033[1;32m[✔] .glibc-2.41 already exists in $WORK_DIR\033[0m"
else
  cp -r "$SCRIPT_DIR/glibc-2.41" "$WORK_DIR/.glibc-2.41"
  echo -e "\033[1;32m[✔] glibc-2.41 copied to $WORK_DIR/.glibc-2.41\033[0m"
fi
if [ -d "$WORK_DIR/.bin" ]; then
  echo -e "\033[1;32m[✔] .bin already exists in $WORK_DIR\033[0m"
else
  cp -r "$SCRIPT_DIR/tools-bin" "$WORK_DIR/.bin"
  echo -e "\033[1;32m[✔] tools-bin copied to $WORK_DIR/.bin\033[0m"
fi

# Put the bundled tools, and the Git built below, ahead of the system ones for
# the rest of this script.
export PATH="$WORK_DIR/.bin:$PATH"

# export LC_ALL=zh_CN.UTF-8
# export LANG=zh_CN.UTF-8

if command -v zsh >/dev/null 2>&1; then
  echo -e "\033[1;32m[✔] zsh found: $(command -v zsh)\033[0m"
else
  echo -e "\033[1;31m[✘] ERROR: zsh not found!\033[0m"
  exit 1
fi

# ============ Git build dependencies ============
# Git needs zlib, OpenSSL, libcurl and expat headers to build. Slim nodes ship
# only the runtime .so files and we are not root, so unpack the matching .deb
# files (the ones pkgs.org indexes) into a private sysroot and build against
# that. Pre-downloaded .deb files dropped into $DEB_DIR are used as-is.

MULTIARCH="x86_64-linux-gnu"
SYSROOT="$WORK_DIR/.bin/.sysroot"
DEB_DIR="$WORK_DIR/.bin/.src/debs"
DEB_PKGS="zlib1g-dev libssl-dev libcurl4-openssl-dev libexpat1-dev"

have_system_build_deps() {
  [ -f /usr/include/zlib.h ] &&
    [ -f /usr/include/openssl/ssl.h ] &&
    [ -f /usr/include/expat.h ] &&
    { [ -f /usr/include/curl/curl.h ] || [ -f "/usr/include/$MULTIARCH/curl/curl.h" ]; }
}

fetch_deb() {
  curl -fsSLO "$1" && return 0
  # The distro's own mirror is not always reachable from these nodes; retry the
  # same pool path on the upstream archive.
  local alt=""
  case "$1" in
  */ubuntu/*) alt="http://archive.ubuntu.com/ubuntu/${1#*/ubuntu/}" ;;
  */debian/*) alt="https://deb.debian.org/debian/${1#*/debian/}" ;;
  esac
  [ -n "$alt" ] || return 1
  echo -e "\033[1;33m[!] mirror failed, retrying $alt\033[0m"
  curl -fsSLO "$alt"
}

build_deps_sysroot() {
  if [ -f "$SYSROOT/usr/include/zlib.h" ]; then
    echo -e "\033[1;32m[✔] build deps sysroot ready: $SYSROOT\033[0m"
    return 0
  fi
  mkdir -p "$DEB_DIR" "$SYSROOT"
  if ! ls "$DEB_DIR"/*.deb >/dev/null 2>&1; then
    echo -e "\033[1;34m[…] Resolving .deb URLs for: $DEB_PKGS\033[0m"
    # --print-uris needs no root, it only reads the apt lists. Dependencies are
    # named explicitly together with --reinstall so their .deb files get listed
    # even when the runtime library is already installed on the node.
    DEB_DEPS=$(apt-cache depends --no-recommends --no-suggests $DEB_PKGS 2>/dev/null |
      awk '/^ *Depends:/ {print $2}' | grep -v '^<' | sort -u)
    apt-get install --print-uris -y --reinstall $DEB_PKGS $DEB_DEPS 2>/dev/null |
      grep -oE "^'[^']+'" | tr -d "'" >"$DEB_DIR/urls.txt" || true
    if [ ! -s "$DEB_DIR/urls.txt" ]; then
      echo -e "\033[1;31m[✘] Could not resolve .deb URLs — apt package lists missing?\033[0m"
      echo -e "\033[1;33m[!] Download these from https://pkgs.org/ by hand into $DEB_DIR and re-run:\033[0m"
      echo -e "\033[1;33m[!]   $DEB_PKGS\033[0m"
      return 1
    fi
    (
      cd "$DEB_DIR"
      while read -r url; do
        echo "    $(basename "$url")"
        fetch_deb "$url" || exit 1
      done <urls.txt
    ) || {
      echo -e "\033[1;31m[✘] .deb download failed\033[0m"
      return 1
    }
  fi
  for deb in "$DEB_DIR"/*.deb; do
    dpkg-deb -x "$deb" "$SYSROOT" 2>/dev/null ||
      ar p "$deb" "$(ar t "$deb" | grep '^data\.tar')" | tar -xf - -C "$SYSROOT" ||
      return 1
  done
  # zlib1g-dev's libz.so is an absolute symlink into the host's /lib: repoint
  # such links at our own copy when we unpacked one, and drop the ones that
  # resolve nowhere so the linker does not trip over them.
  find "$SYSROOT" -type l | while read -r link; do
    target=$(readlink "$link")
    case "$target" in
    /*) [ -e "$SYSROOT$target" ] && ln -sf "$SYSROOT$target" "$link" ;;
    esac
    [ -e "$link" ] || rm -f "$link"
  done
  if [ ! -f "$SYSROOT/usr/include/zlib.h" ]; then
    echo -e "\033[1;31m[✘] sysroot incomplete, zlib.h missing under $SYSROOT\033[0m"
    return 1
  fi
  echo -e "\033[1;32m[✔] build deps unpacked to $SYSROOT\033[0m"
}

# ============ Git from source ============
# Built before everything else: the system git can be too old to clone the repos
# the steps below need, so they all run with this one instead.

if [ -x "$WORK_DIR/.bin/git" ]; then
  echo -e "\033[1;32m[✔] git already installed: $($WORK_DIR/.bin/git --version)\033[0m"
else
  echo -e "\033[1;34m[…] Building Git from source...\033[0m"

  # conda's include/lib paths are kept out of the build so it uses the system
  # toolchain; point it at the unpacked .deb sysroot when the node has no -dev
  # packages of its own.
  GIT_MAKE_FLAGS=(NO_RUST=YesPlease)
  GIT_CPATH=""
  GIT_LIBRARY_PATH=""
  if have_system_build_deps; then
    echo -e "\033[1;32m[✔] zlib/openssl/curl/expat headers found under /usr/include\033[0m"
  else
    build_deps_sysroot || exit 1
    GIT_CPATH="$SYSROOT/usr/include:$SYSROOT/usr/include/$MULTIARCH"
    GIT_LIBRARY_PATH="$SYSROOT/usr/lib/$MULTIARCH:$SYSROOT/lib/$MULTIARCH"
    # Explicit CURL_* flags keep the Makefile from asking curl-config (which the
    # .deb ships with /usr paths baked in) where libcurl lives. The rpath lets
    # the installed git find the sysroot's libcurl at runtime.
    GIT_MAKE_FLAGS+=(
      "CURL_CFLAGS=-I$SYSROOT/usr/include/$MULTIARCH -I$SYSROOT/usr/include"
      "CURL_LDFLAGS=-L$SYSROOT/usr/lib/$MULTIARCH -lcurl"
      "LDFLAGS=-L$SYSROOT/usr/lib/$MULTIARCH -L$SYSROOT/lib/$MULTIARCH -Wl,-rpath,$SYSROOT/usr/lib/$MULTIARCH -Wl,-rpath,$SYSROOT/lib/$MULTIARCH"
    )
  fi
  # po/*.mo needs msgfmt, which on these nodes often only exists inside conda —
  # and conda is deliberately off the build PATH.
  [ -x /usr/bin/msgfmt ] || GIT_MAKE_FLAGS+=(NO_GETTEXT=YesPlease)

  GIT_BUILD_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  if [ -n "$GIT_CPATH" ]; then
    GIT_BUILD_ENV=(-u LD_LIBRARY_PATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u PKG_CONFIG_PATH
      PATH="$GIT_BUILD_PATH" CPATH="$GIT_CPATH" LIBRARY_PATH="$GIT_LIBRARY_PATH")
  else
    GIT_BUILD_ENV=(-u LD_LIBRARY_PATH -u LIBRARY_PATH -u CPATH -u C_INCLUDE_PATH
      -u CPLUS_INCLUDE_PATH -u PKG_CONFIG_PATH PATH="$GIT_BUILD_PATH")
  fi

  GIT_SRC_DIR="$WORK_DIR/.bin/.src/git"
  rm -rf "$GIT_SRC_DIR"
  mkdir -p "$GIT_SRC_DIR"
  curl -fsSL https://github.com/git/git/archive/refs/heads/master.tar.gz -o "$WORK_DIR/.bin/.src/git.tar.gz"
  tar -xzf "$WORK_DIR/.bin/.src/git.tar.gz" -C "$GIT_SRC_DIR" --strip-components=1
  rm -f "$WORK_DIR/.bin/.src/git.tar.gz"
  (
    cd "$GIT_SRC_DIR"
    env "${GIT_BUILD_ENV[@]}" make "${GIT_MAKE_FLAGS[@]}" -j"$(nproc)"
    env "${GIT_BUILD_ENV[@]}" make "${GIT_MAKE_FLAGS[@]}" \
      prefix="$WORK_DIR/.bin/.git" bindir="$WORK_DIR/.bin" install
  )
  echo -e "\033[1;32m[✔] git installed: $($WORK_DIR/.bin/git --version)\033[0m"
  rm -rf "$GIT_SRC_DIR"
fi

# Drop any git path this shell already resolved, so the new binary is picked up.
hash -r
echo -e "\033[1;32m[✔] git in use: $(command -v git) ($(git --version))\033[0m"

# ============ neovim  from source============

if [ -x "$WORK_DIR/.bin/nvim" ]; then
  echo -e "\033[1;32m[✔] neovim already installed: $($WORK_DIR/.bin/nvim --version | head -1)\033[0m"
else
  echo -e "\033[1;34m[…] Building and installing neovim...\033[0m"
  NVIM_SRC_DIR="$WORK_DIR/.bin/.src/neovim"
  rm -rf "$NVIM_SRC_DIR"
  git clone --depth=1 --branch stable https://github.com/neovim/neovim.git "$NVIM_SRC_DIR"
  (
    cd "$NVIM_SRC_DIR"
    make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX="$WORK_DIR/.bin/.nvim" -j"$(nproc)"
    make CMAKE_INSTALL_PREFIX="$WORK_DIR/.bin/.nvim" install
  )
  ln -sf "$WORK_DIR/.bin/.nvim/bin/nvim" "$WORK_DIR/.bin/nvim"
  rm -rf "$NVIM_SRC_DIR"
  if [ -x "$WORK_DIR/.bin/nvim" ]; then
    echo -e "\033[1;32m[✔] neovim installed: $($WORK_DIR/.bin/nvim --version | head -1)\033[0m"
  else
    echo -e "\033[1;31m[✘] ERROR: neovim installation failed\033[0m"
    exit 1
  fi
fi

# Install oh-my-zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
  echo -e "\033[1;32m[✔] oh-my-zsh already installed\033[0m"
else
  echo -e "\033[1;34m[…] Installing oh-my-zsh...\033[0m"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  if [ $? -eq 0 ]; then
    echo -e "\033[1;32m[✔] oh-my-zsh installed\033[0m"
  else
    echo -e "\033[1;31m[✘] ERROR: oh-my-zsh installation failed\033[0m"
    exit 1
  fi
fi

# Install zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  echo -e "\033[1;34m[…] Installing zsh-autosuggestions...\033[0m"
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  echo -e "\033[1;34m[…] Installing zsh-syntax-highlighting...\033[0m"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-vi-mode" ]; then
  echo -e "\033[1;34m[…] Installing zsh-vi-mode...\033[0m"
  git clone https://github.com/jeffreytse/zsh-vi-mode "$ZSH_CUSTOM/plugins/zsh-vi-mode"
fi

# Install powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
  echo -e "\033[1;34m[…] Installing powerlevel10k...\033[0m"
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
fi

# Enable plugins and theme in .zshrc
if [ -f "$HOME/.zshrc" ]; then
  # zsh-vi-mode replaces oh-my-zsh's built-in vi-mode plugin and must be loaded last
  # so it can wrap the keybindings other plugins install.
  sed -i 's/^plugins=(.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting z zsh-vi-mode)/' "$HOME/.zshrc"
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
  # Initialize zsh-vi-mode at source time instead of the first precmd, otherwise it
  # clobbers keybindings added later in .zshrc (e.g. atuin's Ctrl-R).
  grep -q '^ZVM_INIT_MODE=sourcing' "$HOME/.zshrc" || sed -i '/^plugins=(/i ZVM_INIT_MODE=sourcing' "$HOME/.zshrc"
  grep -q 'export EDITOR=nvim' "$HOME/.zshrc" || echo 'export EDITOR=nvim' >>"$HOME/.zshrc"
  grep -q 'export PAGER=delta' "$HOME/.zshrc" || echo 'export PAGER=delta' >>"$HOME/.zshrc"
  grep -q 'setopt ignore_eof' "$HOME/.zshrc" || echo 'setopt ignore_eof' >>"$HOME/.zshrc"
  grep -q "$WORK_DIR/.bin" "$HOME/.zshrc" 2>/dev/null || echo "export PATH=\"$WORK_DIR/.bin:\$PATH\"" >>"$HOME/.zshrc"
  echo -e "\033[1;32m[✔] Plugins and theme configured\033[0m"
fi

# ============ tmux ============

if command -v tmux >/dev/null 2>&1; then
  TMUX_VER=$(tmux -V | grep -oE '[0-9]+\.[0-9]+')
  echo -e "\033[1;32m[✔] tmux found: $(command -v tmux) (version $TMUX_VER)\033[0m"
  if [ "$(printf '%s\n' "3.5" "$TMUX_VER" | sort -V | head -n1)" != "3.5" ]; then
    echo -e "\033[1;31m[✘] ERROR: tmux >= 3.5 required, found $TMUX_VER\033[0m"
    exit 1
  fi
else
  echo -e "\033[1;31m[✘] ERROR: tmux not found!\033[0m"
  exit 1
fi

# Install oh-my-tmux
if [ -d "$HOME/.tmux" ]; then
  echo -e "\033[1;32m[✔] oh-my-tmux already installed\033[0m"
else
  echo -e "\033[1;34m[…] Installing oh-my-tmux...\033[0m"
  git clone https://github.com/gpakosz/.tmux.git "$HOME/.tmux"
  echo -e "\033[1;32m[✔] oh-my-tmux installed\033[0m"
fi

# Ensure oh-my-tmux config files are linked/copied
ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.tmux.conf"
if [ ! -f "$HOME/.tmux.conf.local" ]; then
  cp "$HOME/.tmux/.tmux.conf.local" "$HOME/.tmux.conf.local"
fi

# Configure oh-my-tmux
TMUX_LOCAL="$HOME/.tmux.conf.local"
if [ -f "$TMUX_LOCAL" ]; then
  sed -i 's/^#\?set -g mouse on/set -g mouse on/' "$TMUX_LOCAL"
  sed -i 's/^#\?set -g history-limit.*/set -g history-limit 1000000/' "$TMUX_LOCAL"
  sed -i 's/^#\?set -g prefix C-a/set -g prefix C-a/' "$TMUX_LOCAL"
  sed -i 's/^#\?unbind C-b/unbind C-b/' "$TMUX_LOCAL"
  sed -i 's/^#\?bind C-a send-prefix/bind C-a send-prefix/' "$TMUX_LOCAL"
  sed -i 's/^#\?set -g status-keys vi/set -g status-keys vi/' "$TMUX_LOCAL"
  sed -i 's/^#\?setw -g mode-keys vi/setw -g mode-keys vi/' "$TMUX_LOCAL"
  # Append settings if not already present
  grep -q '^set -g mouse on' "$TMUX_LOCAL" || echo 'set -g mouse on' >>"$TMUX_LOCAL"
  grep -q '^set -g history-limit' "$TMUX_LOCAL" || echo 'set -g history-limit 1000000' >>"$TMUX_LOCAL"
  grep -q '^set -g prefix C-a' "$TMUX_LOCAL" || echo 'set -g prefix C-a' >>"$TMUX_LOCAL"
  grep -q '^unbind C-b' "$TMUX_LOCAL" || echo 'unbind C-b' >>"$TMUX_LOCAL"
  grep -q '^bind C-a send-prefix' "$TMUX_LOCAL" || echo 'bind C-a send-prefix' >>"$TMUX_LOCAL"
  grep -q '^set -g status-keys vi' "$TMUX_LOCAL" || echo 'set -g status-keys vi' >>"$TMUX_LOCAL"
  grep -q '^setw -g mode-keys vi' "$TMUX_LOCAL" || echo 'setw -g mode-keys vi' >>"$TMUX_LOCAL"
  grep -q '^set -g default-shell' "$TMUX_LOCAL" || echo "set -g default-shell $(command -v zsh)" >>"$TMUX_LOCAL"
  echo -e "\033[1;32m[✔] tmux configured: mouse on, history 1000000, prefix C-a, vi-mode, zsh\033[0m"
fi

if tmux info >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
fi

# Install LazyVim
if [ -d "$HOME/.config/nvim" ]; then
  echo -e "\033[1;32m[✔] nvim config already exists\033[0m"
else
  echo -e "\033[1;34m[…] Installing LazyVim...\033[0m"
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
  echo -e "\033[1;32m[✔] LazyVim installed\033[0m"
fi

# Check tree-sitter installed by LazyVim/Mason
TS_BIN="$HOME/.local/share/nvim/mason/bin/tree-sitter"
if [ ! -e "$TS_BIN" ]; then
  TS_BIN=$(find "$HOME/.local/share/nvim" \( -name tree-sitter -o -name tree-sitter-linux-x64 \) 2>/dev/null | head -1)
fi
if [ -z "$TS_BIN" ] || [ ! -e "$TS_BIN" ]; then
  echo -e "\033[1;33m[!] tree-sitter not found. Please start zsh and run nvim once to install LazyVim plugins, then re-run this script.\033[0m"
  echo -e "\033[1;33m[!] Example: exec zsh; nvim\033[0m"
  exit 1
fi

# # Enable LazyVim extras
# LAZYVIM_JSON="$HOME/.config/nvim/lazyvim.json"
# EXTRAS_TO_ADD='coding.yanky'
# if [ ! -f "$LAZYVIM_JSON" ]; then
#   cat >"$LAZYVIM_JSON" <<EOF
# {
#   "extras": [
#     "$EXTRAS_TO_ADD"
#   ]
# }
# EOF
#   echo -e "\033[1;32m[✔] LazyVim extras configured: $EXTRAS_TO_ADD\033[0m"
# else
#   # LazyVim starter expects short extra names in lazyvim.json, e.g. "coding.yanky".
#   # Fix old wrong value that caused lazyvim.plugins.extras.lazyvim.plugins.extras.* imports.
#   sed -i 's|lazyvim\.plugins\.extras\.coding\.yanky|coding.yanky|g' "$LAZYVIM_JSON"
#   if ! grep -q '"coding.yanky"' "$LAZYVIM_JSON"; then
#     sed -i "s|\"extras\": \[|\"extras\": [\n    \"$EXTRAS_TO_ADD\",|" "$LAZYVIM_JSON"
#     echo -e "\033[1;32m[✔] LazyVim extras added: $EXTRAS_TO_ADD\033[0m"
#   fi
# fi

# Patch tree-sitter binary with newer glibc (for nvim-treesitter)
GLIBC_DIR="/$WORK_DIR/.glibc-2.41"
if [ ! -d "$GLIBC_DIR" ]; then
  echo -e "\033[1;34m[…] Downloading glibc 2.41...\033[0m"
  curl -fsSL http://ftp.de.debian.org/debian/pool/main/g/glibc/libc6_2.41-12+deb13u3_amd64.deb -o /tmp/libc6.deb
  mkdir -p "$GLIBC_DIR"
  dpkg-deb -x /tmp/libc6.deb "$GLIBC_DIR"
  rm -f /tmp/libc6.deb
  echo -e "\033[1;32m[✔] glibc 2.41 extracted to $GLIBC_DIR\033[0m"
fi

# Patch tree-sitter binary after LazyVim downloads it
TS_BIN="$HOME/.local/share/nvim/mason/bin/tree-sitter"
if [ ! -f "$TS_BIN" ]; then
  TS_BIN=$(find "$HOME/.local/share/nvim" -name tree-sitter -type f 2>/dev/null | head -1)
fi

if [ -n "$TS_BIN" ] && [ -f "$TS_BIN" ]; then
  if ! command -v patchelf >/dev/null 2>&1; then
    echo -e "\033[1;34m[…] Installing patchelf...\033[0m"
    apt-get install -y patchelf >/dev/null 2>&1 || pip install patchelf
  fi
  LD_PATH="$GLIBC_DIR/usr/lib/x86_64-linux-gnu"
  INTERP="$LD_PATH/ld-linux-x86-64.so.2"
  patchelf --set-interpreter "$INTERP" --force-rpath --set-rpath "$LD_PATH" "$TS_BIN"
  echo -e "\033[1;32m[✔] tree-sitter patched to use glibc 2.41\033[0m"
else
  echo -e "\033[1;33m[!] tree-sitter binary not found yet — run nvim once, then re-run this script to patch it\033[0m"
fi

# ============ Node.js ============

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

if command -v node >/dev/null 2>&1; then
  echo -e "\033[1;32m[✔] node already installed: $(node --version)\033[0m"
else
  echo -e "\033[1;34m[…] Installing Node.js via nvm...\033[0m"
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    . "$NVM_DIR/nvm.sh"
  fi
  nvm install 22
  if command -v node >/dev/null 2>&1; then
    echo -e "\033[1;32m[✔] Node.js installed: $(node --version)\033[0m"
  else
    echo -e "\033[1;31m[✘] ERROR: Node.js installation failed\033[0m"
    exit 1
  fi
fi

# ============ git delta ============

if command -v delta >/dev/null 2>&1; then
  git config --global core.pager delta
  git config --global interactive.diffFilter 'delta --color-only'
  git config --global delta.navigate true
  git config --global delta.side-by-side true
  git config --global merge.conflictstyle zdiff3
  echo -e "\033[1;32m[✔] git configured to use delta\033[0m"
else
  echo -e "\033[1;33m[!] delta not found, skipping git delta config\033[0m"
fi

# ============ conda ============

if [[ ":$PATH:" == *conda* ]]; then
  if [ -n "$CONDA_DEFAULT_ENV" ]; then
    echo -e "\033[1;32m[✔] conda environment active: $CONDA_DEFAULT_ENV\033[0m"
  else
    echo -e "\033[1;32m[✔] conda environment detected in PATH\033[0m"
  fi
else
  echo -e "\033[1;33m[!] conda environment is not active. Please run: conda activate <env-name>\033[0m"
fi

# ============ soar ============

SOAR_CONFIG_SRC="$SCRIPT_DIR/config/soar/config.toml"
SOAR_CONFIG_DST="$HOME/.config/soar/config.toml"

if [ ! -f "$SOAR_CONFIG_SRC" ]; then
  echo -e "\033[1;33m[!] soar config not found at $SOAR_CONFIG_SRC, skipping\033[0m"
elif [ -f "$SOAR_CONFIG_DST" ]; then
  echo -e "\033[1;32m[✔] soar config already exists: $SOAR_CONFIG_DST\033[0m"
else
  mkdir -p "$(dirname "$SOAR_CONFIG_DST")"
  cp "$SOAR_CONFIG_SRC" "$SOAR_CONFIG_DST"
  echo -e "\033[1;32m[✔] soar config copied to $SOAR_CONFIG_DST\033[0m"
fi

# ============ atuin ============

if ! command -v atuin >/dev/null 2>&1; then
  echo -e "\033[1;33m[!] atuin not found in PATH, skipping atuin setup\033[0m"
else
  # Ensure the atuin binary can actually run; patch with newer glibc if not
  if ! atuin --version >/dev/null 2>&1; then
    echo -e "\033[1;34m[…] Patching atuin to use glibc 2.41...\033[0m"
    if ! command -v patchelf >/dev/null 2>&1; then
      apt-get install -y patchelf >/dev/null 2>&1 || pip install patchelf
    fi
    LD_PATH="$GLIBC_DIR/usr/lib/x86_64-linux-gnu"
    INTERP="$LD_PATH/ld-linux-x86-64.so.2"
    patchelf --set-interpreter "$INTERP" --force-rpath --set-rpath "$LD_PATH" "$WORK_DIR/.bin/atuin"
    echo -e "\033[1;32m[✔] atuin patched to use glibc 2.41\033[0m"
  fi

  # Enable atuin shell integration in .zshrc (idempotent)
  if [ -f "$HOME/.zshrc" ]; then
    grep -q 'atuin init zsh' "$HOME/.zshrc" || echo 'eval "$(atuin init zsh --disable-up-arrow)"' >>"$HOME/.zshrc"
    echo -e "\033[1;32m[✔] atuin shell integration enabled in .zshrc\033[0m"
  fi

  # Import existing shell history (idempotent, harmless to re-run)
  atuin import auto >/dev/null 2>&1 || true

  # Login and sync
  if atuin status 2>/dev/null | grep -qi 'username:'; then
    echo -e "\033[1;32m[✔] atuin already logged in, syncing...\033[0m"
    atuin sync || true
  elif [ -t 0 ]; then
    echo -e "\033[1;34m[…] atuin login (leave username empty to skip)\033[0m"
    printf 'atuin username: '
    read ATUIN_USER
    if [ -n "$ATUIN_USER" ]; then
      printf 'atuin password: '
      read -s ATUIN_PASS
      echo
      printf 'atuin key: '
      read -s ATUIN_KEY
      echo
      if atuin login -u "$ATUIN_USER" -p "$ATUIN_PASS" -k "$ATUIN_KEY"; then
        echo -e "\033[1;32m[✔] atuin logged in\033[0m"
        atuin sync || true
        echo -e "\033[1;32m[✔] atuin synced\033[0m"
      else
        echo -e "\033[1;31m[✘] atuin login failed, skipping sync\033[0m"
      fi
      unset ATUIN_PASS ATUIN_KEY
    else
      echo -e "\033[1;33m[!] atuin login skipped\033[0m"
    fi
  else
    echo -e "\033[1;33m[!] no TTY, atuin login skipped — run 'atuin login' manually\033[0m"
  fi
fi
