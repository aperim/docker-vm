#!/usr/bin/env bash

sudo rm /etc/sudoers.d/operations || true && \
  echo "operations ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/operations && \
  echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/90-elasticsearch.conf && \
  echo "net.core.rmem_max=2500000" | sudo tee /etc/sysctl.d/90-quic.conf && \
  mkdir -p /home/operations/.ssh && \
  touch /home/operations/.ssh/authorized_keys && \
  sudo chown -R operations:operations /home/operations/.ssh && \
  sudo chmod 640 /home/operations/.ssh/authorized_keys && \
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPbpCjkiYBPlx34WIDY2er5BuFT4BFWmTSGFNJCHoxo7 operations@aperim.com" | sudo tee -a /home/operations/.ssh/authorized_keys
  exit

curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
 sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" |
 sudo tee /etc/apt/sources.list.d/1password.list

 sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
 sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol
sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
 sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

sudo DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl gnupg && \
sudo install -m 0755 -d /etc/apt/keyrings && \
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
sudo apt-get update && \
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
sudo usermod -aG docker $USER && \
sudo systemctl enable docker.service && \
sudo systemctl enable containerd.service