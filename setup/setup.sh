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
ZEROTIER_NETWORK_ID=""
POLICY_FILE="/etc/policy.txt"
POLICY_ACCEPT_FILE="/etc/policy_accepted-$USER"

# === Update system ===
apt update && apt upgrade -y

# === Install ZeroTier ===
curl -s https://install.zerotier.com | bash
#zerotier-cli join "$ZEROTIER_NETWORK_ID"

# === Set hostname ===
hostnamectl set-hostname "$HOST_NAME"
echo "$HOST_NAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t$HOST_NAME/" /etc/hosts

# === Set root password ===
echo "root:$ROOT_PASSWORD" | chpasswd

# === Remove existing default users ===
for DEFAULT_USER in user ubuntu; do
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

# === Install base packages ===
apt install -y sudo curl zip unzip build-essential ufw fail2ban \
    openssh-server xrdp xfce4 xfce4-goodies ca-certificates \
    gnupg lsb-release software-properties-common nfs-common yad firefox chromium-browser

# === Configure SSH ===
cp -f ./sshd_config /etc/ssh/
systemctl enable ssh
systemctl restart ssh

# === Configure XRDP ===
echo xfce4-session > /home/$USER_NAME/.xsession
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xsession
adduser $USER_NAME ssl-cert

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
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

usermod -aG docker "$USER_NAME"

# === Install NVM and Node.js ===
su - "$USER_NAME" -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
su - "$USER_NAME" -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm use --lts
  nvm alias default lts/*
'

echo 'export NVM_DIR="$HOME/.nvm"' >> /home/$USER_NAME/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/$USER_NAME/.bashrc
echo 'export SDKMAN_DIR="$HOME/.sdkman"' >> /home/$USER_NAME/.bashrc
echo '[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && \. "$SDKMAN_DIR/bin/sdkman-init.sh"' >> /home/$USER_NAME/.bashrc
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.bashrc

# === Install SDKMAN and Java ===
su - "$USER_NAME" -c 'curl -s "https://get.sdkman.io" | bash'
su - "$USER_NAME" -c 'source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java && sdk default java $(sdk current java | grep -o "java-[^ ]*")'

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
sudo snap install code --classic

## === Install Rust ===
su - "$USER_NAME" -c 'curl https://sh.rustup.rs -sSf | sh -s -- -y'
echo 'source "$HOME/.cargo/env"' >> /home/$USER_NAME/.bashrc
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/$USER_NAME/.bashrc
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.bashrc

# === Policy ===
cp -f ./policy.txt "$POLICY_FILE"
chattr +i "$POLICY_FILE"

STARTWM_FILE="/etc/xrdp/startwm.sh"

# Policy block to insert
read -r -d '' POLICY_BLOCK <<'EOF'
# >>> POLICY BLOCK START <<<
POLICY_FILE="/etc/policy.txt"
ACCEPT_FILE="/etc/policy_accepted-$USER"

# Show policy prompt only if not already accepted
if [ ! -f "$ACCEPT_FILE" ]; then
    yad --text-info --center --title="Regulamin" --width=700 --height=800 \
        --filename="$POLICY_FILE" --button="Anuluj:0" --button="Akceptuję:1"

    if [ $? -ne 1 ]; then
        echo "Policy not accepted. Exiting..."
        exit 1
    fi

    echo "Accepted by $USER on $(date)" > "$ACCEPT_FILE"
    chmod 644 "$ACCEPT_FILE"
fi
# >>> POLICY BLOCK END <<<
EOF

# Check if block is already inserted
if grep -q "$MARKER" "$STARTWM_FILE"; then
    echo "Policy block already exists in $STARTWM_FILE. Skipping insertion."
else
    echo "Inserting policy block at the top of $STARTWM_FILE..."
    sudo sed -i "1a$POLICY_BLOCK" "$STARTWM_FILE"
    echo "Block inserted."
fi

history -c