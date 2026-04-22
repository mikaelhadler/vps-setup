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

# Carrega nvm no shell atual
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ============================================================
# 2. Node LTS
# ============================================================
echo ">> Instalando Node LTS..."
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'

echo ">> Node: $(node --version)"
echo ">> npm: $(npm --version)"

# ============================================================
# 3. npm prefix local (evita EACCES em installs globais)
# ============================================================
echo ">> Configurando npm prefix local..."
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"

# Adiciona ao PATH no bashrc (só se ainda não estiver)
BASHRC="$HOME/.bashrc"
PATH_LINE='export PATH=~/.npm-global/bin:$PATH'
if ! grep -qxF "$PATH_LINE" "$BASHRC" 2>/dev/null; then
  echo "$PATH_LINE" >> "$BASHRC"
  echo ">> PATH adicionado ao .bashrc"
else
  echo ">> PATH já presente no .bashrc, pulando."
fi

# Aplica no shell atual (pra os comandos npm abaixo funcionarem)
export PATH="$HOME/.npm-global/bin:$PATH"

# ============================================================
# 4. Claude CLI + OpenClaw
# ============================================================
echo ">> Instalando Claude CLI e OpenClaw globalmente (no prefix local)..."
npm install -g @anthropic-ai/claude-code openclaw

echo
echo ">> Versões instaladas:"
echo "   claude: $(claude --version 2>/dev/null || echo 'NÃO ENCONTRADO')"
echo "   openclaw: $(openclaw --version 2>/dev/null || echo 'NÃO ENCONTRADO')"

echo
echo ">> Instalação concluída. Próximos passos manuais no README do setup."