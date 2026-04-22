# VPS Setup

Scripts de bootstrap para VPS Debian/Ubuntu recém-provisionadas.

## setup-user.sh

Cria um usuário com sudo sem senha, copia as chaves SSH do root, habilita `linger` para serviços `systemd --user` e deixa a VPS pronta para uso sem login como root.

### Uso

```bash
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/main/setup-user.sh \
  | sudo bash -s <username> "<chave_pública_ssh>"
```

Exemplo:

```bash
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/main/setup-user.sh \
  | sudo bash -s openclaw "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... voce@host"
```

A chave pública é opcional. Se omitida, o script apenas copia o `authorized_keys` do root.

```bash
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/main/setup-user.sh \
  | sudo bash -s openclaw
```

### O que o script faz

1. Cria o usuário com `adduser --disabled-password` (login só via chave SSH)
2. Adiciona ao grupo `sudo` e cria `/etc/sudoers.d/<username>` com `NOPASSWD: ALL`
3. Valida o sudoers com `visudo -c` antes de confiar nele
4. Copia `/root/.ssh/authorized_keys` para `/home/<username>/.ssh/authorized_keys`
5. Anexa a chave pública extra (se passada), sem duplicar
6. Ajusta permissões: `700` no `.ssh`, `600` no `authorized_keys`
7. Executa `loginctl enable-linger <username>` para que serviços `systemd --user` continuem rodando após logout

O script é idempotente. Pode ser executado novamente no mesmo usuário sem quebrar nada.

### Requisitos

- Debian 11+ ou Ubuntu 20.04+
- Executar como root (ou com `sudo`)
- Chave SSH já presente em `/root/.ssh/authorized_keys` (a maioria dos provedores configura isso automaticamente ao criar a VPS)

### Fluxo recomendado em uma VPS nova

```bash
# Como root, na VPS recém-criada
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/main/setup-user.sh \
  | bash -s deploy "ssh-ed25519 AAAA... voce@host"

# Testar login do novo usuário em OUTRA sessão antes de sair do root
ssh deploy@<ip_da_vps>

# Depois que confirmar que funciona, desabilitar login do root via SSH
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl reload ssh
```

### Segurança

Antes de rodar `curl | bash` de qualquer fonte, leia o script:

```bash
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/main/setup-user.sh | less
```

Para reprodutibilidade, referencie um commit específico em vez da branch `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/<commit_sha>/setup-user.sh \
  | sudo bash -s openclaw
```

Algumas notas sobre escolhas que fiz:

**Flag `-s` do bash** é o detalhe que trava a maioria das pessoas na primeira vez que tenta passar argumentos via `curl | bash`. Deixei explícito no exemplo pra não ter que explicar depois.

**Passo de desabilitar root SSH** ficou fora do script principal de propósito, como recomendação no README. Mexer em `sshd_config` dentro de um script que é `curl | bash`'d é arriscado porque se algo der errado e a sessão root cair, você se tranca fora. Melhor o usuário fazer isso manualmente depois de confirmar que o login do novo user funciona.

**Seção de segurança** com o `| less` pra ler antes é padrão em projetos sérios que distribuem via `curl | bash` (rustup, nix, etc). Sinaliza que você tá consciente do pattern.

Se quiser expandir o repo depois com outros scripts (`install-docker.sh`, `harden-ssh.sh`, `install-node.sh`), o formato do README já tá pronto pra receber novas seções — só duplica a estrutura de `## setup-user.sh`.
