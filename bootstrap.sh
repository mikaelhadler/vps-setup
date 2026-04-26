#!/usr/bin/env bash
#
# Bootstrap: baixa os scripts do vps-setup e executa interativamente.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/mikaelhadler/vps-setup/main"

if [[ $EUID -ne 0 ]]; then
  echo "Precisa rodar como root (use sudo)." >&2
  exit 1
fi

if [[ -t 0 ]]; then
  TTY_IN=/dev/stdin
else
  TTY_IN=/dev/tty
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

echo ">> Baixando scripts do repo..."
curl -fsSL -o setup-user.sh       "$REPO_RAW/setup-user.sh"
curl -fsSL -o install-openclaw.sh "$REPO_RAW/install-openclaw.sh"
chmod +x setup-user.sh install-openclaw.sh

echo
echo "============================================"
echo "  Setup de VPS para OpenClaw"
echo "============================================"
echo

# Username
USERNAME=""
while true; do
  printf "Nome do novo usuário [openclaw]: "
  read -r USERNAME <"$TTY_IN" || true
  USERNAME="${USERNAME:-openclaw}"

  if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    break
  else
    echo "!! Nome inválido. Use apenas letras minúsculas, números, '_' ou '-'."
  fi
done

# Chave pública
echo
echo "Cole sua chave SSH pública (ex: 'ssh-ed25519 AAAA... comment')."
echo "No seu Mac/Linux local: cat ~/.ssh/id_ed25519.pub"
echo "Em branco pra pular (usa só authorized_keys do root)."
echo
EXTRA_KEY=""
while true; do
  printf "Chave pública: "
  read -r EXTRA_KEY <"$TTY_IN" || true

  if [[ -z "$EXTRA_KEY" ]]; then
    echo ">> Pulando chave extra."
    break
  fi

  if [[ "$EXTRA_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ssh-dss)\  ]]; then
    break
  else
    echo "!! Formato inválido. Deve começar com 'ssh-ed25519', 'ssh-rsa' etc."
  fi
done

echo
echo ">> Iniciando setup com:"
echo "   Usuário: $USERNAME"
echo "   Chave extra: $([[ -n "$EXTRA_KEY" ]] && echo 'sim' || echo 'não')"
echo

printf "Confirmar e prosseguir? [s/N]: "
CONFIRM=""
read -r CONFIRM <"$TTY_IN" || true
if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
  echo ">> Abortado pelo usuário."
  exit 0
fi

export VPS_SETUP_USERNAME="$USERNAME"
export VPS_SETUP_EXTRA_KEY="$EXTRA_KEY"

./setup-user.sh