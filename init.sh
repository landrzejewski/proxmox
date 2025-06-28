#!/bin/bash

# === Validate input ===
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME="$1"
CONFIG_FILE="config.yml"

# === Check config file exists ===
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ERROR] Configuration file $CONFIG_FILE not found."
  exit 1
fi

# === Parse global config values ===
ZEROTIER_NETWORK_ID=$(grep -m1 '^  id:' "$CONFIG_FILE" | awk '{print $2}')
ROOT_PASSWORD=$(grep -m1 '^  password:' "$CONFIG_FILE" | awk '{print $2}')

# === Extract user password for the specified username ===
USER_PASSWORD=$(awk -v user="$USERNAME" '
  $0 ~ "username: "user {
    getline;
    if ($1 == "password:") print $2;
  }' "$CONFIG_FILE")

if [ -z "$USER_PASSWORD" ]; then
  echo "[ERROR] No password found for user '$USERNAME' in config.yml"
  exit 1
fi

exec > >(tee /root/postclone.log) 2>&1
echo "[INFO] Starting setup for $USERNAME at $(date)"

# === Set hostname ===
hostnamectl set-hostname "$USERNAME"
echo "$USERNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$USERNAME/" /etc/hosts

# === Update system ===
apt update && apt upgrade -y

# === Create user ===
if ! id "$USERNAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:$USER_PASSWORD" | chpasswd
  usermod -aG sudo "$USERNAME"
fi

# === Set root password ===
echo "root:$ROOT_PASSWORD" | chpasswd

# === Remove possible default users ===
for DEFAULT_USER in user ubuntu; do
  if id "$DEFAULT_USER" &>/dev/null; then
    pkill -u "$DEFAULT_USER" 2>/dev/null
    userdel -r "$DEFAULT_USER" && echo "[INFO] Removed default user '$DEFAULT_USER'"
    rm -rf "/home/$DEFAULT_USER"
  fi
done

# === Install base packages ===
apt install -y curl sudo ufw unzip zip git build-essential \
    openssh-server xrdp xfce4 xfce4-goodies ca-certificates \
    gnupg lsb-release software-properties-common nfs-common yad

sudo mkdir -p /mnt/shared

# === Enable services ===
systemctl enable ssh
systemctl restart ssh
systemctl enable xrdp
systemctl restart xrdp

# === Configure XRDP ===
echo xfce4-session > /home/$USERNAME/.xsession
chown $USERNAME:$USERNAME /home/$USERNAME/.xsession
adduser $USERNAME ssl-cert

# === Install Docker ===
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$USERNAME"

# === Install ZeroTier ===
curl -s https://install.zerotier.com | bash
#zerotier-cli join "$ZEROTIER_NETWORK_ID"

# === Firewall ===
ufw allow 22
ufw allow 3389
ufw --force enable

# === Install SDKMAN and Java ===
su - "$USERNAME" -c 'curl -s "https://get.sdkman.io" | bash'
su - "$USERNAME" -c 'source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java && sdk default java $(sdk current java | grep -o "java-[^ ]*")'

# === Install IntelliJ IDEA ===
INTELLIJ_URL=$(curl -s https://data.services.jetbrains.com/products/releases?code=IIU\&latest=true\&type=release \
  | grep -oP '(?<="linux":\{"link":")[^"]+' | head -1)

su - "$USERNAME" -c "
  cd ~
  curl -L -o idea.tar.gz \"$INTELLIJ_URL\"
  tar -xzf idea.tar.gz
  IDEA_DIR=\$(tar -tf idea.tar.gz | head -1 | cut -f1 -d\"/\")
  mv \"\$IDEA_DIR\" idea
  rm idea.tar.gz
"

## === Install NVM and Node.js ===
#su - "$USERNAME" -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
#su - "$USERNAME" -c '
#  export NVM_DIR="$HOME/.nvm"
#  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
#  nvm install --lts
#  nvm use --lts
#  nvm alias default lts/*
#'
#
## === Persist paths ===
#echo 'export NVM_DIR="$HOME/.nvm"' >> /home/$USERNAME/.bashrc
#echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/$USERNAME/.bashrc
#echo 'export SDKMAN_DIR="$HOME/.sdkman"' >> /home/$USERNAME/.bashrc
#echo '[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && \. "$SDKMAN_DIR/bin/sdkman-init.sh"' >> /home/$USERNAME/.bashrc
#chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

## === Install Rust ===
#su - "$USERNAME" -c 'curl https://sh.rustup.rs -sSf | sh -s -- -y'
#echo 'source "$HOME/.cargo/env"' >> /home/$USERNAME/.bashrc
#echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/$USERNAME/.bashrc
#chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc


echo "
# Network Buffer Optimizations for xrdp
net.core.rmem_max = 12582912
net.core.wmem_max = 12582912
net.ipv4.tcp_rmem = 10240 87380 12582912
net.ipv4.tcp_wmem = 10240 87380 12582912
" >> /etc/sysctl.conf

# Apply the settings
sysctl -p

sudo nano /etc/xrdp/startwm.sh

yad --text-info --center --title="Regulamin" --width=800 --height=600 \
    --filename="/home/policy.txt" --button=OK:0 --button=Cancel:1
[ $? -eq 0 ]  || exit
