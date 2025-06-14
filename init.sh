#!/bin/bash
USERNAME="$1"
USER_PASSWORD="$2"
ROOT_PASSWORD="$3"
ZEROTIER_NETWORK_ID="$4"

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
for DEFAULT_USER in student user ubuntu pi; do
  if id "$DEFAULT_USER" &>/dev/null; then
    echo "[INFO] Attempting to remove default user: $DEFAULT_USER"

    # Kill all user processes
    pkill -9 -u "$DEFAULT_USER" 2>/dev/null || echo "[WARN] Could not kill all processes for $DEFAULT_USER"

    # Force logout and unmount home if mounted
    loginctl terminate-user "$DEFAULT_USER" 2>/dev/null || true
    umount "/home/$DEFAULT_USER" 2>/dev/null || true

    # Now delete the user and its home directory
    userdel -r "$DEFAULT_USER" && echo "[INFO] Removed default user '$DEFAULT_USER'" || echo "[ERROR] Failed to remove user '$DEFAULT_USER'"

    # Remove home manually if still exists
    rm -rf "/home/$DEFAULT_USER"
  fi
done

# === Install base packages ===
apt install -y curl sudo ufw unzip zip git build-essential \
    openssh-server xrdp xfce4 xfce4-goodies ca-certificates \
    gnupg lsb-release software-properties-common

# === Enable services ===
systemctl enable ssh
systemctl restart ssh
systemctl enable xrdp
systemctl restart xrdp

# === Configure XRDP ===
echo xfce4-session > /home/$USERNAME/.xsession
chown $USERNAME:$USERNAME /home/$USERNAME/.xsession
adduser $USERNAME ssl-cert

# === Install Docker (official Ubuntu) ===
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
zerotier-cli join "$ZEROTIER_NETWORK_ID"

# === Firewall ===
ufw allow 22
ufw allow 3389
ufw --force enable

# === Install SDKMAN and LTS Java ===
su - "$USERNAME" -c 'curl -s "https://get.sdkman.io" | bash'
su - "$USERNAME" -c 'source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install java && sdk default java $(sdk current java | grep -o "java-[^ ]*")'

# === Install NVM and LTS Node.js ===
su - "$USERNAME" -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
su - "$USERNAME" -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm use --lts
  nvm alias default lts/*
'

# === Persist SDKMAN and NVM paths ===
echo 'export NVM_DIR="$HOME/.nvm"' >> /home/$USERNAME/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /home/$USERNAME/.bashrc
echo 'export SDKMAN_DIR="$HOME/.sdkman"' >> /home/$USERNAME/.bashrc
echo '[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && \. "$SDKMAN_DIR/bin/sdkman-init.sh"' >> /home/$USERNAME/.bashrc
chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

# === Install Rust via rustup ===
su - "$USERNAME" -c 'curl https://sh.rustup.rs -sSf | sh -s -- -y'
echo 'source "$HOME/.cargo/env"' >> /home/$USERNAME/.bashrc
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/$USERNAME/.bashrc
chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

# === Download and install IntelliJ IDEA Ultimate Edition ===
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

echo "[INFO] IntelliJ IDEA Ultimate installed to /home/$USERNAME/idea"

# === Done ===
touch /root/.setup_done
echo "[INFO] Setup completed for $USERNAME at $(date)"
