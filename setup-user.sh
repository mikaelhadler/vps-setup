#!/usr/bin/env bash
#
# Cria um usuário com sudo NOPASSWD, copia as chaves SSH do root,
# adiciona uma chave pública extra e habilita linger (pra serviços
# systemd --user rodarem sem sessão ativa).
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

# 1. Cria usuário sem senha (login só via chave)
if id "$USERNAME" &>/dev/null; then
  echo "Usuário '$USERNAME' já existe, pulando adduser."
else
  adduser --disabled-password --gecos "" "$USERNAME"
fi

# 2. Sudo sem senha
usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"
visudo -c -f "/etc/sudoers.d/$USERNAME" >/dev/null

# 3. Copia authorized_keys do root (se existir)
USER_HOME="/home/$USERNAME"
USER_SSH="$USER_HOME/.ssh"
mkdir -p "$USER_SSH"

if [[ -f /root/.ssh/authorized_keys ]]; then
  cp /root/.ssh/authorized_keys "$USER_SSH/authorized_keys"
else
  touch "$USER_SSH/authorized_keys"
fi

# 4. Adiciona chave extra se passada (evita duplicata)
if [[ -n "$EXTRA_KEY" ]]; then
  if ! grep -qxF "$EXTRA_KEY" "$USER_SSH/authorized_keys"; then
    echo "$EXTRA_KEY" >> "$USER_SSH/authorized_keys"
    echo "Chave extra adicionada."
  else
    echo "Chave extra já presente, pulando."
  fi
fi

# 5. Permissões
chown -R "$USERNAME:$USERNAME" "$USER_SSH"
chmod 700 "$USER_SSH"
chmod 600 "$USER_SSH/authorized_keys"

# 6. Linger pra systemd --user persistir após logout
loginctl enable-linger "$USERNAME"

echo
echo "Pronto. Usuário '$USERNAME' configurado."
echo "  - sudo NOPASSWD ativo"
echo "  - SSH pronto em $USER_SSH/authorized_keys"
echo "  - linger habilitado"
echo
echo "Teste o login em outra sessão antes de sair do root:"
echo "  ssh $USERNAME@<host>"
