#!/usr/bin/env bash
#
# Cria usuário, configura SSH + sudo + linger, roda install-openclaw.sh.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Precisa rodar como root (use sudo)." >&2
  exit 1
fi

# Detecta diretório do script de forma robusta
# (funciona tanto em execução direta quanto via pipe)
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"
SCRIPT_DIR="${SCRIPT_DIR:-$PWD}"

if [[ -t 0 ]]; then
  TTY_IN=/dev/stdin
else
  TTY_IN=/dev/tty
fi

# Aceita env vars do bootstrap ou pergunta interativo
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

# Resto igual ao anterior (pacotes, adduser, sudo, ssh, linger)
echo ">> Atualizando sistema e instalando dependências..."
apt update
apt upgrade -y
apt install -y curl git lsof build-essential ca-certificates

if id "$USERNAME" &>/dev/null; then
  echo ">> Usuário '$USERNAME' já existe, pulando adduser."
else
  echo ">> Criando usuário '$USERNAME'..."
  adduser --disabled-password --gecos "" "$USERNAME"
fi

echo ">> Configurando sudo NOPASSWD..."
usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"
visudo -c -f "/etc/sudoers.d/$USERNAME" >/dev/null

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

echo ">> Habilitando linger..."
loginctl enable-linger "$USERNAME"

# Instala stack como o novo user
INSTALL_SCRIPT_LOCAL="$SCRIPT_DIR/install-openclaw.sh"
INSTALL_SCRIPT_DEST="$USER_HOME/install-openclaw.sh"

if [[ ! -f "$INSTALL_SCRIPT_LOCAL" ]]; then
  echo "!! install-openclaw.sh não encontrado em '$SCRIPT_DIR'." >&2
  echo "!! Stack não instalada. Baixe e rode manualmente como '$USERNAME'." >&2
else
  echo ">> Copiando install-openclaw.sh pro home..."
  cp "$INSTALL_SCRIPT_LOCAL" "$INSTALL_SCRIPT_DEST"
  chown "$USERNAME:$USERNAME" "$INSTALL_SCRIPT_DEST"
  chmod +x "$INSTALL_SCRIPT_DEST"

  echo ">> Executando install-openclaw.sh como '$USERNAME'..."
  sudo -u "$USERNAME" -i bash "$INSTALL_SCRIPT_DEST"
fi

HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

============================================================
  Setup do usuário '$USERNAME' concluído.
============================================================

Próximos passos manuais:

  1. exit                               # sai do root
  2. ssh $USERNAME@${HOST:-<IP>}        # entra como novo user
  3. claude login                       # login OAuth no Claude
  4. claude setup-token                 # copia o token
  5. Persiste o token em dois lugares:

     echo 'export CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."' >> ~/.bashrc
     source ~/.bashrc

     mkdir -p ~/.config/environment.d/
     echo 'CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...' > ~/.config/environment.d/claude.conf

     systemctl --user set-environment CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

  6. openclaw onboard
  7. openclaw gateway install
     systemctl --user enable --now openclaw-gateway.service

============================================================
EOF