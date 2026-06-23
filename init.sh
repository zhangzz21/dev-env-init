#!/bin/bash

set -e

WORK_DIR="$1"
if [ -z "$WORK_DIR" ]; then
  echo -e "\033[1;31m[✘] Usage: $0 <work_dir>\033[0m"
  exit 1
fi
mkdir -p "$WORK_DIR"

# Network check
if curl -sfL --connect-timeout 5 https://www.google.com -o /dev/null; then
  echo -e "\033[1;32m[✔] Network OK (google reachable)\033[0m"
else
  echo -e "\033[1;31m[✘] ERROR: Cannot reach google, check network/proxy\033[0m"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# export LC_ALL=zh_CN.UTF-8
# export LANG=zh_CN.UTF-8

if command -v zsh >/dev/null 2>&1; then
  echo -e "\033[1;32m[✔] zsh found: $(command -v zsh)\033[0m"
else
  echo -e "\033[1;31m[✘] ERROR: zsh not found!\033[0m"
  exit 1
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

# Install powerlevel10k theme
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
  echo -e "\033[1;34m[…] Installing powerlevel10k...\033[0m"
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
fi

# Enable plugins and theme in .zshrc
if [ -f "$HOME/.zshrc" ]; then
  sed -i 's/^plugins=(.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting z vi-mode)/' "$HOME/.zshrc"
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$HOME/.zshrc"
  grep -q 'export EDITOR=nvim' "$HOME/.zshrc" || echo 'export EDITOR=nvim' >>"$HOME/.zshrc"
  grep -q 'export PAGER=delta' "$HOME/.zshrc" || echo 'export PAGER=delta' >>"$HOME/.zshrc"
  grep -q 'setopt ignore_eof' "$HOME/.zshrc" || echo 'set opt ignore_eof' >>"$HOME/.zshrc"
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

# ============ neovim ============

if command -v nvim >/dev/null 2>&1; then
  echo -e "\033[1;32m[✔] neovim already installed: $(nvim --version | head -1)\033[0m"
else
  echo -e "\033[1;34m[…] Building and installing neovim...\033[0m"
  git clone --depth=1 --branch stable https://github.com/neovim/neovim.git /tmp/neovim-build
  cd /tmp/neovim-build
  make CMAKE_BUILD_TYPE=Release -j"$(nproc)"
  make install
  cd -
  rm -rf /tmp/neovim-build
  if command -v nvim >/dev/null 2>&1; then
    echo -e "\033[1;32m[✔] neovim installed: $(nvim --version | head -1)\033[0m"
  else
    echo -e "\033[1;31m[✘] ERROR: neovim installation failed\033[0m"
    exit 1
  fi
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
GLIBC_DIR="/workspace/.glibc-2.41"
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
  patchelf --set-interpreter "$INTERP" --set-rpath "$LD_PATH" "$TS_BIN"
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
