#!/usr/bin/env bash
#
# sudo -v ; curl -s https://raw.githubusercontent.com/aperim/docker-vm/main/install.sh | sudo bash
#

# Define repository and temporary directory
REPO="${REPO:-https://github.com/aperim/docker-vm.git}"
TEMP_DIR="${TEMP_DIR:-/tmp/docker-vm}"
OPERATIONS_USER="${OPERATIONS_USER:-operations}"

# Remove temporary directory if exists and clone the repo
rm -rf "$TEMP_DIR" && git clone "$REPO" "$TEMP_DIR"

# If OPERATIONS_USER is not "operations"
if [[ "$OPERATIONS_USER" != "operations" ]]; then
  # Copy all the files from the operations directory to the user directory
  mv "$TEMP_DIR/rootfs/home/operations" "$TEMP_DIR/rootfs/home/${OPERATIONS_USER}"
fi

# Copy all the files from rootfs into /
cp -Rvvv "$TEMP_DIR/rootfs/"* /

# Change permissions of scripts in /usr/local/sbin/
chmod +x /usr/local/sbin/rclone-setup /usr/local/sbin/update-rclone
chown ${OPERATIONS_USER}:${OPERATIONS_USER} /home/${OPERATIONS_USER}/.ssh/authorized_keys
chown -R ${OPERATIONS_USER}:${OPERATIONS_USER} /opt/portainer
chmod 640 /home/${OPERATIONS_USER}/.ssh/authorized_keys

# Remove temporary directory
rm -rf "$TEMP_DIR"
rm -Rf /etc/apt/keyrings/docker.gpg \
    /usr/share/keyrings/1password-archive-keyring.gpg \
    /etc/apt/sources.list.d/1password.list \
    /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    /etc/apt/sources.list.d/docker.list

echo "Scaffolding complete. Installing packages"

sudo apt-get -y update && \
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl gnupg

curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
    sudo tee /etc/apt/sources.list.d/1password.list

sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/

curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
    sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol

sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22

curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

sudo install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

sudo curl https://rclone.org/install.sh | sudo bash -s beta

sudo DEBIAN_FRONTEND=noninteractive apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 1password-cli && \
sudo usermod -aG docker $OPERATIONS_USER

sudo mkdir -p /var/secrets \
    /var/lib/docker-plugins/rclone/cache \
    /var/lib/docker-plugins/rclone/config && \
    sudo touch /var/lib/docker-plugins/rclone/config/rclone.conf \
        /var/secrets/op && \
    sudo chown root:docker /var/lib/docker-plugins/rclone \
        /var/lib/docker-plugins/rclone/config \
        /var/lib/docker-plugins/rclone/cache \
        /var/lib/docker-plugins/rclone/config/rclone.conf && \
    sudo chmod 775 /var/lib/docker-plugins/rclone /var/lib/docker-plugins/rclone/config /var/lib/docker-plugins/rclone/cache && \
    sudo chmod 660 /var/lib/docker-plugins/rclone/config/rclone.conf && \
    sudo chmod 400 /var/secrets/op

sudo systemctl enable update-rclone.service && \
    sudo systemctl enable docker-volume-rclone.service && \
    sudo systemctl enable docker.service && \
    sudo systemctl enable containerd.service && \
    sudo systemctl start docker.service

# Check and install the rclone plugin for docker
if ! docker plugin ls | grep rclone; then
  architecture=$(uname -m)
  case $architecture in
    x86_64)
        variant=amd64
        ;;
    aarch64)
        variant=arm64
        ;;
    *)
        echo "Unsupported architecture: $architecture"
        exit 1
        ;;
  esac
  docker plugin install rclone/docker-volume-rclone:$variant --alias rclone --grant-all-permissions args="--vfs-cache-mode=full --vfs-read-ahead=512M --allow-other"
fi

# Info
echo -e "\n\nTo configure rclone:\n"
echo -e "rclone config --config /var/lib/docker-plugins/rclone/config/rclone.conf\n\n"
# Print warning message to the user
echo -e "\n\033[1;93m⚠️  WARNING! ⚠️\033[0m"
echo -e "\nYOU MUST REPLACE THE TOKEN IN /var/secrets/op WITH A VALID TOKEN."
echo -e "THIS IS A CRITICAL STEP 🔑 \n"
exit 0
