#!/bin/bash

# === Validate input ===
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <hostname> <rootpassword> <USER_NAME> <userpassword>"
  exit 1
fi

HOST_NAME="$1"
ROOT_PASSWORD="$2"
USER_NAME="$3"
USER_PASSWORD="$4"
ZEROTIER_NETWORK_ID="363c67c55a1018b2"
POLICY_FILE="/etc/policy.txt"
POLICY_ACCEPT_FILE="/etc/policy_accepted-$USER_NAME"

# === Update system ===
apt update && apt upgrade -y

# === Install base packages ===
apt update && apt install -y \
    sudo \
    curl \
    zip \
    unzip \
    build-essential \
    ufw \
    fail2ban \
    openssh-server \
    xrdp \
    ssl-cert \
    gnome-session \
    gnome-shell \
    gnome-terminal \
    nautilus \
    gdm3 \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    nfs-common \
    yad \
    firefox-esr \
    chromium

# === Install ZeroTier ===
curl -s https://install.zerotier.com | bash
zerotier-cli join "$ZEROTIER_NETWORK_ID"

# === Set hostname ===
hostnamectl set-hostname "$HOST_NAME"
echo "$HOST_NAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$HOST_NAME/" /etc/hosts

# === Set root password ===
echo "root:$ROOT_PASSWORD" | chpasswd

# === Remove existing default users ===
for DEFAULT_USER in user debian; do
  if id "$DEFAULT_USER" &>/dev/null; then
    pkill -u "$DEFAULT_USER" 2>/dev/null
    userdel -r "$DEFAULT_USER" && echo "[INFO] Removed default user '$DEFAULT_USER'"
    rm -rf "/home/$DEFAULT_USER"
  fi
done

# === Create user ===
if ! id "$USER_NAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USER_NAME"
  echo "$USER_NAME:$USER_PASSWORD" | chpasswd
  usermod -aG sudo "$USER_NAME"
fi

# === Configure SSH ===
cp -f ./sshd_config /etc/ssh/
systemctl enable ssh
systemctl restart ssh

# === Configure XRDP ===
echo "gnome-session" > /home/"$USER_NAME"/.xsession
chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME"/.xsession
adduser "$USER_NAME" ssl-cert

echo "
# Network Buffer Optimizations for xrdp
net.core.rmem_max = 12582912
net.core.wmem_max = 12582912
net.ipv4.tcp_rmem = 10240 87380 12582912
net.ipv4.tcp_wmem = 10240 87380 12582912
" >> /etc/sysctl.conf

sysctl -p

systemctl enable xrdp
systemctl restart xrdp

# === Firewall ===
ufw allow 22
ufw allow 3389
ufw --force enable

# === fail2ban ===
cp -f ./jail.local /etc/fail2ban/
systemctl enable fail2ban
systemctl restart fail2ban

# === Install Docker ===
apt-get update -y
apt-get install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

usermod -aG docker "$USER_NAME"

# === Install NVM and Node.js ===
su - "$USER_NAME" -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash >/dev/null 2>&1'
su - "$USER_NAME" -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts >/dev/null 2>&1
  nvm use --lts >/dev/null 2>&1
  nvm alias default lts/* >/dev/null 2>&1
'
echo 'export NVM_DIR="$HOME/.nvm"' >> /home/"$USER_NAME"/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/"$USER_NAME"/.bashrc
chown "$USER_NAME":"$USER_NAME" /home/"$USER_NAME"/.bashrc

# === Install SDKMAN and Java ===
su - "$USER_NAME" -c 'curl -s "https://get.sdkman.io" | bash'
su - "$USER_NAME" -c '
  source "$HOME/.sdkman/bin/sdkman-init.sh"
  sdk install java
  sdk default java $(sdk list java | grep -E "installed|>" | head -1 | awk "{print \$NF}")
'
echo 'export SDKMAN_DIR="$HOME/.sdkman"' >> /home/"$USER_NAME"/.bashrc
echo '[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && \. "$SDKMAN_DIR/bin/sdkman-init.sh"' >> /home/"$USER_NAME"/.bashrc

# === Install IntelliJ IDEA ===
INTELLIJ_URL=$(curl -s https://data.services.jetbrains.com/products/releases?code=IIU\&latest=true\&type=release \
  | grep -oP '(?<="linux":\{"link":")[^"]+' | head -1)

su - "$USER_NAME" -c "
  cd ~
  curl -L -o idea.tar.gz \"$INTELLIJ_URL\"
  tar -xzf idea.tar.gz
  IDEA_DIR=\$(tar -tf idea.tar.gz | head -1 | cut -f1 -d\"/\")
  mv \"\$IDEA_DIR\" idea
  rm idea.tar.gz
"

# === Install Visual Studio Code ===
# For Debian, we'll use the official Microsoft repository instead of snap
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt update
apt install code -y

# === Policy ===
cp -f ./policy.txt "$POLICY_FILE"

cp -f ./ssh_policy.sh /etc/profile.d/ssh_policy.sh
chmod +x /etc/profile.d/ssh_policy.sh
chattr +i /etc/profile.d/ssh_policy.sh
echo "source /etc/profile.d/ssh_policy.sh" >> /etc/bash.bashrc

chattr +i "$POLICY_FILE"
sed -i '1r ./xrdp_policy.sh' /etc/xrdp/startwm.sh

# === Storage and logs ===
mkdir -p /mnt/shared

cp ./archive_logs.sh /root
chmod +x /root/archive_logs.sh

history -c