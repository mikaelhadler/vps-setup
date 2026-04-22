#!/usr/bin/env bash
#
# Instala nvm + Node LTS + Claude CLI + OpenClaw.
# Deve rodar como o usuário que vai "dono" do OpenClaw
# (NÃO como root).

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Não rode como root. Execute como o usuário alvo." >&2
  echo "Exemplo: sudo -u openclaw -i bash install-openclaw.sh" >&2
  exit 1
fi

echo ">> Rodando como $(whoami), HOME=$HOME"

# ============================================================
# 1. nvm
# ============================================================
if [[ ! -d "$HOME/.nvm" ]]; then
  echo ">> Instalando nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
else
  echo ">> nvm já instalado, pulando."
fi

# ============================================================
# 2. Carrega nvm + Node LTS (com set +u por compatibilidade)
# ============================================================
# nvm.sh usa variáveis não definidas internamente, incompatível com set -u
set +u
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo ">> Instalando Node LTS (v22)..."
# Fixa em 22 (LTS atual codinome 'iron') em vez de --lts,
# que em algumas versões do nvm pega a 'current'
nvm install 22
nvm use 22
nvm alias default 22
set -u

echo ">> Node: $(node --version)"
echo ">> npm: $(npm --version)"

# ============================================================
# 3. npm prefix local (evita EACCES em installs globais)
# ============================================================
echo ">> Configurando npm prefix local..."
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"

BASHRC="$HOME/.bashrc"
PATH_LINE='export PATH=~/.npm-global/bin:$PATH'
if ! grep -qxF "$PATH_LINE" "$BASHRC" 2>/dev/null; then
  echo "$PATH_LINE" >> "$BASHRC"
  echo ">> PATH adicionado ao .bashrc"
else
  echo ">> PATH já presente no .bashrc, pulando."
fi

export PATH="$HOME/.npm-global/bin:$PATH"

# ============================================================
# 4. Claude CLI + OpenClaw
# ============================================================
echo ">> Instalando Claude CLI e OpenClaw..."
npm install -g @anthropic-ai/claude-code openclaw

echo
echo ">> Versões instaladas:"
echo "   claude:   $(claude --version 2>/dev/null || echo 'NÃO ENCONTRADO')"
echo "   openclaw: $(openclaw --version 2>/dev/null || echo 'NÃO ENCONTRADO')"

echo
echo ">> Instalação concluída."