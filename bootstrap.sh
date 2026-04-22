#!/usr/bin/env bash
#
# Cria usuário com sudo NOPASSWD, copia chaves SSH do root,
# adiciona chave pública extra, habilita linger, e dispara
# a instalação da stack (Node + Claude CLI + OpenClaw) como
# o próprio usuário novo via sudo -u.
#
# Modo 1 (via bootstrap.sh): recebe args por env vars
#   VPS_SETUP_USERNAME=openclaw VPS_SETUP_EXTRA_KEY="ssh-ed25519 ..." ./setup-user.sh
#
# Modo 2 (standalone): pergunta interativamente
#   sudo ./setup-user.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Precisa rodar como root (use sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Entrada de dados: env vars (do bootstrap) ou prompts
# ============================================================
if [[ -t 0 ]]; then
  TTY_IN=/dev/stdin
else
  TTY_IN=/dev/tty
fi

USERNAME="${VPS_SETUP_USERNAME:-}"
EXTRA_KEY="${VPS_SETUP_EXTRA_KEY:-}"

if [[ -z "$USERNAME" ]]; then
  printf "Nome do novo usuário [openclaw]: "
  read -r USERNAME <"$TTY_IN" || true
  USERNAME="${USERNAME:-openclaw}"
fi

if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "!! Nome inválido: '$USERNAME'" >&2
  exit 1
fi

if [[ -z "${EXTRA_KEY+x}" ]]; then
  printf "Chave pública SSH (em branco pra pular): "
  read -r EXTRA_KEY <"$TTY_IN" || true
fi

# ============================================================
# 1. Pacotes do sistema
# ============================================================
echo ">> Atualizando sistema e instalando dependências..."
apt update
apt upgrade -y
apt install -y curl git lsof build-essential ca-certificates

# ============================================================
# 2. Cria usuário
# ============================================================
if id "$USERNAME" &>/dev/null; then
  echo ">> Usuário '$USERNAME' já existe, pulando adduser."
else
  echo ">> Criando usuário '$USERNAME'..."
  adduser --disabled-password --gecos "" "$USERNAME"
fi

# ============================================================
# 3. Sudo NOPASSWD
# ============================================================
echo ">> Configurando sudo NOPASSWD..."
usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"
visudo -c -f "/etc/sudoers.d/$USERNAME" >/dev/null

# ============================================================
# 4. Chaves SSH
# ============================================================
USER_HOME="/home/$USERNAME"
USER_SSH="$USER_HOME/.ssh"
mkdir -p "$USER_SSH"

if [[ -f /root/.ssh/authorized_keys ]]; then
  echo ">> Copiando authorized_keys do root..."
  cp /root/.ssh/authorized_keys "$USER_SSH/authorized_keys"
else
  touch "$USER_SSH/authorized_keys"
fi

if [[ -n "$EXTRA_KEY" ]]; then
  if ! grep -qxF "$EXTRA_KEY" "$USER_SSH/authorized_keys"; then
    echo "$EXTRA_KEY" >> "$USER_SSH/authorized_keys"
    echo ">> Chave extra adicionada."
  else
    echo ">> Chave extra já presente, pulando."
  fi
fi

chown -R "$USERNAME:$USERNAME" "$USER_SSH"
chmod 700 "$USER_SSH"
chmod 600 "$USER_SSH/authorized_keys"

# ============================================================
# 5. Linger
# ============================================================
echo ">> Habilitando linger..."
loginctl enable-linger "$USERNAME"

# ============================================================
# 6. Instala stack como o novo usuário
# ============================================================
INSTALL_SCRIPT_LOCAL="$SCRIPT_DIR/install-openclaw.sh"
INSTALL_SCRIPT_DEST="$USER_HOME/install-openclaw.sh"

if [[ ! -f "$INSTALL_SCRIPT_LOCAL" ]]; then
  echo "!! install-openclaw.sh não encontrado em '$SCRIPT_DIR'." >&2
  echo "!! Stack não foi instalada. Baixe manualmente e rode como '$USERNAME'." >&2
else
  echo ">> Copiando install-openclaw.sh pro home do usuário..."
  cp "$INSTALL_SCRIPT_LOCAL" "$INSTALL_SCRIPT_DEST"
  chown "$USERNAME:$USERNAME" "$INSTALL_SCRIPT_DEST"
  chmod +x "$INSTALL_SCRIPT_DEST"

  echo ">> Executando install-openclaw.sh como '$USERNAME' (via sudo -u -i)..."
  sudo -u "$USERNAME" -i bash "$INSTALL_SCRIPT_DEST"
fi

# ============================================================
# 7. Próximos passos
# ============================================================
HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

============================================================
  Setup do usuário '$USERNAME' concluído.
============================================================

Próximos passos MANUAIS (precisam do seu Mac/browser):

  1. Sai do root:
     exit

  2. Conecta como o novo usuário:
     ssh $USERNAME@${HOST:-<IP_DO_VPS>}

  3. Loga no Claude CLI (abre URL no browser do Mac):
     claude login

  4. Gera o token OAuth:
     claude setup-token

     Copia o valor que começa com 'sk-ant-oat01-...'

  5. Persiste o token em DOIS lugares:

     # a) Pro shell interativo (bashrc):
     echo 'export CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-COLE_AQUI"' >> ~/.bashrc
     source ~/.bashrc

     # b) Pro systemd user (que não lê bashrc):
     mkdir -p ~/.config/environment.d/
     cat > ~/.config/environment.d/claude.conf <<ENVEOF
     CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-COLE_AQUI
     ENVEOF

     # c) Aplica no scope atual do systemd user:
     systemctl --user set-environment CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-COLE_AQUI

  6. Onboard do OpenClaw:
     openclaw onboard

  7. Instala gateway como serviço:
     openclaw gateway install
     systemctl --user enable --now openclaw-gateway.service

============================================================
EOF