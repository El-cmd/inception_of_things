#! /usr/bin/env bash
set -e

apt-get update -y
apt-get install -y curl

ip addr add 192.168.56.110/24 dev eth1 2>/dev/null || true
ip link set eth1 up

hostnamectl set-hostname nleoniS && sed -i 's/trixie/nleoniS/g' /etc/hosts

export INSTALL_K3S_EXEC="--node-ip=192.168.56.110 --flannel-iface=eth1 --token=K3S_TOKEN --write-kubeconfig-mode=644"
curl -sfL https://get.k3s.io | sh -

while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    sleep 1
done

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc