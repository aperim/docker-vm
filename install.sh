#!/usr/bin/env bash
#
# sudo -v ; curl -s https://raw.githubusercontent.com/aperim/docker-vm/main/install.sh | sudo bash
#

# Function to print messages in color with emoji
function print_message() {
  echo -e "\033[1;36m💬  INFO 💬 \033[0m: $1"
}

# Define repository and temporary directory
REPO="${REPO:-https://github.com/aperim/docker-vm.git}"
TEMP_DIR="${TEMP_DIR:-/tmp/docker-vm}"
OPERATIONS_USER="${OPERATIONS_USER:-operations}"
VAULT_NAME="${VAULT_NAME:-Servers}"  # Define the 1Password vault name

# An associative array of command names and their corresponding package names
declare -A dependencies=( ["git"]="git" ["curl"]="curl" ["jq"]="jq" ["awk"]="gawk" ["sed"]="sed" ["hostnamectl"]="systemd")

# Store package names needed to install
packages_to_install=()

# Check for each command if it exists, if not add it to the install list
for cmd in ${!dependencies[@]}; do
    command -v $cmd > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "$cmd is not installed. Adding it to the install list."
        packages_to_install+=(${dependencies[$cmd]})
    fi
done

# If any packages need to be installed
if [[ ${#packages_to_install[@]} -ne 0 ]]; then
    echo "Updating package lists and installing necessary packages..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update

    # Install required packages, if fails then print error message and exit with failure status
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${packages_to_install[@]}; then
        echo -e "\n\033[1;93m⚠️  WARNING! ⚠️\033[0m"
        echo -e "\nFailed to install required packages. Please check your network connection and package repositories.\n"
        exit 1
    fi
fi

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

# Fetch the search domain provided by DHCP.
search_domain=$(awk '/^search/ { print $2 }' /etc/resolv.conf)

# Check if a search domain was found...
if [[ -n "$search_domain" ]]; then
    # Fetch the short version of the hostname
    short_hostname=$(hostname -s)
    
    # Set the hostname to be the combination of the short hostname and the search domain
    new_hostname="${short_hostname}.${search_domain}"
    sudo hostnamectl set-hostname "$new_hostname"
    
    print_message "Host updated to the new hostname: $new_hostname 👍"
fi

print_message "Scaffolding complete. Installing packages"

sudo apt-get -y update && \
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl gnupg jq

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
print_message "To configure rclone, run the following command:\nrclone config --config /var/lib/docker-plugins/rclone/config/rclone.conf\n"

# Prompt the user for the 1Password service account secret
echo -n "Please paste the 1Password service account secret: "
read -s op_secret < /dev/tty
echo ""

# Check if the user provided a secret
if [[ -n "$op_secret" ]]; then
  echo "$op_secret" > /var/secrets/op  # Write the secret to the file
  chown root:docker /var/secrets/op  # Change the owner of the file
  chmod 400 /var/secrets/op  # Set the permissions of the file

  print_message "1Password service account secret set successfully! 🔐"

  # Retrieve the fully qualified domain name
  fqn=$(hostname --fqdn)

  # Check if an FQDN was returned, if not use hostname -A
  if [[ "$fqn" == "$(hostname -s)" ]]; then
    # Extract all possible FQDNs
    possible_fqdns=$(hostname -A)
    host_short_name=$(hostname -s)

    # Iterate over possible FQDNs, select first valid one
    for possible_fqdn in $possible_fqdns; do
    if [[ $possible_fqdn == "$host_short_name".* && $possible_fqdn != "$host_short_name" ]]; then
        fqn=$possible_fqdn
        break
    fi
    done

    # If we didn't find something, record the error and suggest manual intervention
    if [[ -z "$fqn" || "$fqn" == "$host_short_name" ]]; then
    echo -e "\n\033[1;93m⚠️  WARNING! ⚠️ \033[0m"
    echo -e "\nUnable to determine FQDN. Please set it up manually! \n"
    exit 1
    fi
  fi

  # List items in the 1Password vault
  items=$(op list items --vault=$VAULT_NAME)

  # Assuming the items are JSON, and each item has a "name" property
  server_item=$(echo "$items" | jq -r --arg fqn "$fqn" '.[] | select(.name == $fqn)')

  # Check if an item with OPERATIONS_USER exists for the given server
  operations_user=$(echo "$server_item" | jq -r --arg user "$OPERATIONS_USER" '.details.fields[] | select(.name == "username" and .value == $user)')

  if [[ -n "$operations_user" ]]; then
    # Retrieve the password
    password=$(echo "$operations_user" | jq -r '.value')

    # Update the OPERATIONS_USER password
    echo "$OPERATIONS_USER:$password" | chpasswd

    print_message "OPERATIONS_USER password updated from 1Password! 👍"
  else
    echo -e "\n\033[1;93m⚠️  WARNING! ⚠️\033[0m"
    echo -e "\nNo OPERATIONS_USER found in the 1Password item for server $fqn 😔\n"
  fi
else
  echo -e "\n\033[1;93m⚠️  WARNING! ⚠️\033[0m"
  echo -e "\nYOU MUST REPLACE THE TOKEN IN /var/secrets/op WITH A VALID TOKEN. THIS IS A CRITICAL STEP 🔑 \n"
  exit 1
fi

# Disable password SSH login
if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config; then
  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
  print_message "Password SSH login disabled! 🔒"
else
  print_message "Password SSH login was already disabled."
fi

print_message "All done!"

exit 0
