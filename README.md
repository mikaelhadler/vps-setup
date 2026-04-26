# VPS Setup

Scripts de bootstrap para VPS Debian/Ubuntu recém-provisionadas.

## setup-user.sh

Cria um usuário com sudo sem senha, copia as chaves SSH do root, habilita `linger` para serviços `systemd --user` e deixa a VPS pronta para uso sem login como root.

### Uso

```bash
curl -fsSL https://raw.githubusercontent.com/mikaelhadler/vps-setup/main/bootstrap.sh \
  | sudo bash -s
```
