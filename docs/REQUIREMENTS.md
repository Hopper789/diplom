# Требования

## Управляющая машина / сервер

На машине, где запускается репозиторий, нужны:

```text
Linux или WSL2
bash
git
Docker
Docker Compose plugin
Python 3
PyYAML
curl
Ansible
OpenSSH client
ssh-copy-id
```

## Проверка на сервере

```bash
bash --version
git --version
docker --version
docker compose version
python3 --version
curl --version
ansible --version
ssh -V
ssh-copy-id -h
```

## Установка на Ubuntu/WSL

```bash
sudo apt update
sudo apt install -y \
  git \
  curl \
  python3 \
  python3-pip \
  python3-yaml \
  ansible \
  openssh-client
```

Docker устанавливается отдельно по инструкции Docker для вашей системы.

Проверка доступа к Docker:

```bash
docker ps
```

Если получаете `permission denied`, временно используйте `sudo docker ...` или добавьте пользователя в группу `docker`:

```bash
sudo usermod -aG docker "$USER"
```

После этого нужно выйти из сессии и зайти снова.

## Клиентские машины

На client nodes нужны:

```text
Linux
SSH server
sudo
Python 3
apt или другой пакетный менеджер
boinc-client
curl
python3-pip
ca-certificates
```

Ansible playbook устанавливает на клиентах:

```text
boinc-client
python3
python3-pip
curl
ca-certificates
procps
psmisc
```

## Установка SSH-сервера на клиенте Ubuntu

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

Проверка:

```bash
ss -tlnp | grep :22
```

С управляющей машины:

```bash
ssh user@client_ip
```

## Windows + WSL

Если сервер запускается в WSL/Docker, а клиенты должны подключаться по LAN IP, может понадобиться открыть порт 8080.

В `cmd` от администратора:

```cmd
netsh advfirewall firewall add rule name="BOINC Server 8080" dir=in action=allow protocol=TCP localport=8080
```

Если `localhost:8080` работает, а `SERVER_LAN_IP:8080` нет, может понадобиться portproxy:

```cmd
netsh interface portproxy add v4tov4 listenaddress=192.168.1.209 listenport=8080 connectaddress=WSL_IP connectport=8080
```

Проверка:

```cmd
netsh interface portproxy show all
```
