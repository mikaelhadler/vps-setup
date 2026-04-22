#!/usr/bin/env bash
#
# Cria usuário com sudo NOPASSWD, copia chaves SSH do root,
# adiciona chave pública extra, habilita linger, e dispara
# a instalação da stack (Node + Claude CLI + OpenClaw) como
# o próprio usuário novo via sudo -u.
#
# Uso:
#   sudo ./setup-user.sh <username> [extra_pubkey]
#
# Exemplo:
#   sudo ./setup-user.sh openclaw "ssh-ed25519 AAAA... comment"

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Precisa rodar como root (use sudo)." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Uso: $0 <username> [extra_pubkey]" >&2
  exit 1
fi

USERNAME="$1"
EXTRA_KEY="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# 1. Pacotes do sistema (fazemos aqui, como root, uma vez só)
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
# 5. Linger (systemd --user persiste após logout)
# ============================================================
echo ">> Habilitando linger..."
loginctl enable-linger "$USERNAME"

# ============================================================
# 6. Instala stack de dev como o novo usuário
# ============================================================
INSTALL_SCRIPT="$SCRIPT_DIR/install-openclaw.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
  echo "!! Script '$INSTALL_SCRIPT' não encontrado." >&2
  echo "!! Instalação da stack pulada. Rode manualmente como '$USERNAME':" >&2
  echo "   su - $USERNAME -c './install-openclaw.sh'" >&2
else
  echo ">> Executando install-openclaw.sh como '$USERNAME'..."
  # Copia o script pro home do user pra facilitar re-execução
  cp "$INSTALL_SCRIPT" "$USER_HOME/install-openclaw.sh"
  chown "$USERNAME:$USERNAME" "$USER_HOME/install-openclaw.sh"
  chmod +x "$USER_HOME/install-openclaw.sh"

  # sudo -u com -i simula login completo (carrega .bashrc, HOME, etc)
  sudo -u "$USERNAME" -i bash "$USER_HOME/install-openclaw.sh"
fi

# ============================================================
# 7. Próximos passos
# ============================================================
HOST="$(hostname -I | awk '{print $1}')"
cat <<EOF

============================================================
Setup do usuário '$USERNAME' concluído.

Próximos passos MANUAIS (precisam do seu Mac/browser):

  1. Sai do root:
     exit

  2. Conecta como o novo usuário:
     ssh $USERNAME@$HOST

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

     # c) Importa no scope atual do systemd user:
     systemctl --user set-environment CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-COLE_AQUI

  6. Onboard do OpenClaw:
     openclaw onboard

  7. Instala gateway como serviço:
     openclaw gateway install
     systemctl --user enable --now openclaw-gateway.service

============================================================
EOF