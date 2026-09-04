#! /usr/bin/env bash
set -e

apt-get update -y
apt-get install -y curl

ip addr add 192.168.56.111/24 dev eth1 2>/dev/null || true
ip link set eth1 up

hostnamectl set-hostname vlothSW && sed -i 's/trixie/vlothSW/g' /etc/hosts

SERVER_IP="192.168.56.110"
TOKEN="K3S_TOKEN"

export K3S_URL="https://${SERVER_IP}:6443"
export K3S_TOKEN="${TOKEN}"
export INSTALL_K3S_EXEC="--node-ip=192.168.56.111 --flannel-iface=eth1"
export INSTALL_K3S_SKIP_START=true

curl -sfL https://get.k3s.io | sh -

systemctl start k3s-agent

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl