#!/usr/bin/env bash
#
# sudo -v ; curl -s https://raw.githubusercontent.com/aperim/docker-vm/main/install.sh | sudo bash
#

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to print messages in color with emoji
print_message() {
    echo -e "${GREEN}✅ INFO: ${NC}$1"
}

# Function to print error messages in color with emoji
print_error() {
    echo -e "${RED}🚩 ERROR: ${NC}$1"
    exit 1
}

# Function for the safe addition of a new line to a file. Checks if the line already exists. 
# If it does, it won't duplicate it.
# Params: $1 Line to add , $2 File
safe_add_line_to_file() {
    grep -qF "$1" "$2"  || echo "$1" >> "$2"
}

# Function to ensure that the operations user is created and belongs to its own group
create_operations_user() {
    if id -u "${OPERATIONS_USER}" >/dev/null 2>&1; then
        print_message "User $OPERATIONS_USER already exists"
    else
        useradd -m "${OPERATIONS_USER}" -s /bin/bash
        print_message "User $OPERATIONS_USER has been created"
    fi
    
    if getent group "${OPERATIONS_USER}" >/dev/null 2>&1; then
        print_message "Group $OPERATIONS_USER already exists"
    else
        groupadd "${OPERATIONS_USER}"
        print_message "Group $OPERATIONS_USER has been created"
    fi
    
    usermod -aG "${OPERATIONS_USER}" "${OPERATIONS_USER}"
    print_message "User $OPERATIONS_USER added to group $OPERATIONS_USER"
}

# Ensure the script is being run as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
fi

# Check for any upgradeable packages
apt-get -y update > /dev/null
upgradeable=$(apt list --upgradable 2>/dev/null | tail -n +2)
if [[ -n "$upgradeable" ]]; then
    print_error "There are upgradeable packages that need to be upgraded before running this script. Please run 'apt-get -y full-upgrade' and reboot the system before proceeding."
fi

# Define repository and temporary directory
REPO="${REPO:-https://github.com/aperim/docker-vm.git}"
TEMP_DIR="${TEMP_DIR:-/tmp/docker-vm}"
OPERATIONS_USER="${OPERATIONS_USER:-operations}"
VAULT_NAME="${VAULT_NAME:-Servers}"  # Define the 1Password vault name

# Create operations user and group if they doesn't exist
create_operations_user

# An associative array of command names and their corresponding package names
declare -A dependencies=( ["git"]="git" ["curl"]="curl" ["jq"]="jq" ["awk"]="gawk" ["sed"]="sed" ["hostnamectl"]="systemd" ["vi"]="vim-scripts" )

# Store package names needed to install
packages_to_install=()

# Check for each command if it exists
for cmd in ${!dependencies[@]}; do
    command -v $cmd > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        print_message "$cmd is not installed. Adding it to the install list."
        packages_to_install+=(${dependencies[$cmd]})
    fi
done

# If any packages need to be installed
if [[ ${#packages_to_install[@]} -ne 0 ]]; then
    print_message "Updating package lists and installing necessary packages..."
    DEBIAN_FRONTEND=noninteractive apt-get update

    # Install required packages, if fails then print error message and exit with failure status
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y ${packages_to_install[@]}; then
        print_error "Failed to install required packages. Please check your network connection and package repositories."
    fi
fi

# Check if DNSStubListener is yes
if grep -q "DNSStubListener=yes" /etc/systemd/resolved.conf; then
    # Disable the stub resolver
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf

    # Restart systemd-resolved
    systemctl restart systemd-resolved

    print_message "DNSStubListener has been disabled and systemd-resolved has been restarted"
else
    print_message "DNSStubListener already disabled"
fi

# Remove the temporary directory if it exists, and clone the repo
rm -rf "$TEMP_DIR"
git clone "$REPO" "$TEMP_DIR" || print_error "Failed to clone repository"

# Copy all the files from operations directory to user directory
if [[ "$OPERATIONS_USER" != "operations" ]]; then
    mv "$TEMP_DIR/rootfs/home/operations" "$TEMP_DIR/rootfs/home/${OPERATIONS_USER}" || print_error "Failed to move operations files"
fi

# Copy all files from rootfs into /
cp -Rvvv "$TEMP_DIR/rootfs/"* / || print_error "Failed to copy root files"

# Change permissions of scripts in /usr/local/sbin/
chmod +x /usr/local/sbin/rclone-setup /usr/local/sbin/update-rclone || print_error "Failed to change script permissions"

# Change owner of authorized_keys file
chown ${OPERATIONS_USER}:${OPERATIONS_USER} /home/${OPERATIONS_USER}/.ssh/authorized_keys || print_error "Failed to change owner of authorized_keys file"

# Change owner of portainer directory
chown -R ${OPERATIONS_USER}:${OPERATIONS_USER} /opt/portainer || print_error "Failed to change owner of portainer directory"

# Change permissions of authorized_keys file
chmod 640 /home/${OPERATIONS_USER}/.ssh/authorized_keys || print_error "Failed to change permissions of authorized_keys file"

# Fetch search domain provided by DHCP.
search_domain=$(awk '/^search/ { print $2 }' /etc/resolv.conf)

# Check if a search domain was found...
if [[ -n "$search_domain" ]]; then
    # Fetch the short version of the hostname
    short_hostname=$(hostname -s)
    
    # Set the hostname to be the combination of the short hostname and the search domain
    new_hostname="${short_hostname}.${search_domain}"
    hostnamectl set-hostname "$new_hostname"
    
    print_message "Host updated to the new hostname: $new_hostname"
fi

print_message "Scaffolding complete. Installing packages"

# Run apt-get
apt-get -y update || print_error "Failed to run apt-get update"

# Install packages
DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl gnupg jq || print_error "Failed to install packages"

# Clean-up
rm -rf "$TEMP_DIR"
rm -rf /etc/apt/keyrings/docker.gpg \
    /usr/share/keyrings/1password-archive-keyring.gpg \
    /etc/apt/sources.list.d/1password.list \
    /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    /etc/apt/sources.list.d/docker.list

print_message "Clean-up complete"

# Import 1password keys
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg || print_error "Failed to import 1Password keys"

# Add 1password to the apt source list
safe_add_line_to_file "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" /etc/apt/sources.list.d/1password.list

# Create necessary directories
mkdir -p /etc/debsig/policies/AC2D62742012EA22/

# Add 1password pol
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
    tee /etc/debsig/policies/AC2D62742012EA22/1password.pol || print_error "Failed to add 1Password pol"

# Create necessary directories
mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22

# Import 1password asc
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg || print_error "Failed to import 1Password asc"

# Create necessary directories and file
install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    safe_add_line_to_file "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" /etc/apt/sources.list.d/docker.list

# Update apt-get
apt-get update || print_error "Failed to run 'apt-get update'"

# Install Rclone
curl https://rclone.org/install.sh | bash -s beta || print_error "Failed to install Rclone"

# Install prerequisite packages
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    1password-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    htop \
    libarchive-tools \
    open-vm-tools \
    rsyslog \
    unzip \
    wget \
    zsh || print_error "Failed to install necessary packages"

# Change shell to zsh
if [ "$(getent passwd $OPERATIONS_USER | cut -d: -f7)" != "$(which zsh)" ]; then
  chsh -s $(which zsh) $OPERATIONS_USER || print_error "Failed to change shell to zsh"
  print_message "Shell changed to zsh"
else
  print_message "Shell already set to zsh"
fi

# Install ohmyzsh unattended
if [ ! -d "/home/${OPERATIONS_USER}/.oh-my-zsh" ]; then
  su - $OPERATIONS_USER -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended" || print_error "Failed to install ohmyzsh"
  print_message "ohmyzsh installed"
else
  print_message "ohmyzsh already installed"
fi

# Add user to docker group if not already present
if ! id -nGz "$OPERATIONS_USER" | grep -qzxF docker; then
    usermod -aG docker "$OPERATIONS_USER" || print_error "Failed to add user to docker group"
    print_message "User '$OPERATIONS_USER' added to docker group" 
else
    print_message "User '$OPERATIONS_USER' is already in docker group"
fi

# Make necessary directories and touch files
mkdir -p /var/secrets \
    /var/lib/docker-plugins/rclone/cache \
    /var/lib/docker-plugins/rclone/config && \
    touch /var/lib/docker-plugins/rclone/config/rclone.conf \
        /var/secrets/op || print_error "Failed to make directories and touch files"
        
# Change ownership and permissions        
chown root:docker /var/lib/docker-plugins/rclone \
        /var/lib/docker-plugins/rclone/config \
        /var/lib/docker-plugins/rclone/cache \
        /var/lib/docker-plugins/rclone/config/rclone.conf || print_error "Failed to change ownership"
        
chmod 775 /var/lib/docker-plugins/rclone /var/lib/docker-plugins/rclone/config /var/lib/docker-plugins/rclone/cache
chmod 660 /var/lib/docker-plugins/rclone/config/rclone.conf
chmod 440 /var/secrets/op || print_error "Failed to change permissions"

# Enable and start services
systemctl enable rsyslog
systemctl start rsyslog
systemctl enable update-rclone.service
systemctl enable docker-volume-rclone.service
systemctl enable docker.service
systemctl enable containerd.service
systemctl start docker.service || print_error "Failed to start and enable services"

# Check and install rclone plugin for docker
if ! docker plugin ls | grep rclone &>/dev/null; then
  architecture=$(uname -m)
  case $architecture in
    x86_64)
        variant=amd64
        ;;
    aarch64)
        variant=arm64
        ;;
    *)
        print_error "Unsupported architecture: $architecture"
        ;;
  esac
  docker plugin install rclone/docker-volume-rclone:$variant --alias rclone --grant-all-permissions args="--vfs-cache-mode=full --vfs-read-ahead=512M --allow-other" || print_error "Failed to install docker plugin"
fi

# Prints the final command information
print_message "To configure rclone, run the following command:\nrclone config --config /var/lib/docker-plugins/rclone/config/rclone.conf\n"

# Check if /var/secrets/op is empty
if [ ! -s /var/secrets/op ]; then
    # Prompt the user for the 1Password service account secret
    echo -e "Please paste the 1Password service account secret: \c"
    read -s op_secret
    echo

    # Write the secret into the file only if a secret was provided
    if [[ -n "$op_secret" ]]; then
        echo "$op_secret" > /var/secrets/op
        chown root:docker /var/secrets/op  # Change the owner of the file
        chmod 440 /var/secrets/op  # Set the permissions of the file
    fi
else
    print_message "1Password service account secret already exists, skipping the update."
fi

# Check if 1Password has a secret
if [ -s /var/secrets/op ]; then
  # Retrieve the fully qualified domain name
  fqn=$(hostname --fqdn)

  # Check if an FQDN was returned, if not use hostname -A
  if [[ "$fqn" == "$(hostname -s)" ]]; then
    possible_fqdns=$(hostname -A)
    host_short_name=$(hostname -s)

    for possible_fqdn in $possible_fqdns; do
      if [[ $possible_fqdn == "$host_short_name".* && $possible_fqdn != "$host_short_name" ]]; then
        fqn=$possible_fqdn
        break
      fi
    done

    if [[ -z "$fqn" || "$fqn" == "$host_short_name" ]]; then
      print_error "Unable to determine FQDN. Please set it up manually!"
    fi
  fi
  items="$(OP_SERVICE_ACCOUNT_TOKEN=$(cat /var/secrets/op) op item list --categories 'SERVER' --vault ${VAULT_NAME} --format=json)"
  
  if [[ -z "$items" ]]; then
    print_error "No items found in the 1Password vault."
  fi

  server_item="$(echo "$items" | jq -r --arg fqn "$fqn" '.[] | select(.title == $fqn)')"

  if [[ -z "$server_item" ]]; then
    print_error "No server item found in the 1Password."
  fi

  server_item_data="$(echo "${server_item}" | OP_SERVICE_ACCOUNT_TOKEN=$(cat /var/secrets/op) op item get - --fields username,password --format=json --vault ${VAULT_NAME})"
  
  if [[ -z "$server_item_data" ]]; then
    print_error "No server item data found in 1Password."
  fi

  # Check if username matches OPERATIONS_USER
  username=$(echo "$server_item_data" | jq -r '.[] | select(.id == "username") | .value')
    
  if [[ "$OPERATIONS_USER" == "$username" ]]; then
    password=$(echo "$server_item_data" | jq -r 'map(select(.id == "password")) | .[0] | .value')
    echo "$OPERATIONS_USER:$password" | chpasswd
    print_message "${OPERATIONS_USER} password updated from 1Password!"
  else
    print_error "No ${OPERATIONS_USER} found in the 1Password item for server $fqn"
  fi
fi

# Disable password SSH login
if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
  print_message "Password SSH login disabled!"
else
  print_message "Password SSH login was already disabled."
fi

print_message "All done!"
exit 0