#!/usr/bin/env bash
set -e

CLUSTER_NAME="iot-cluster"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
P3_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

# Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "Installation de Docker..."
    sudo apt-get update && sudo apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      docker-cli \
      docker.io \
      git
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
fi

# kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo "Installation de kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# k3d
if ! command -v k3d >/dev/null 2>&1; then
    echo "Installation de k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

echo "=== 2. Création du cluster K3d ==="
# Supprime l'ancien cluster s'il existe
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true

# 8888 -> Traefik HTTP (app)
# 8080 -> Traefik HTTPS (ArgoCD UI)
k3d cluster create "$CLUSTER_NAME" \
  --port "8888:80@loadbalancer" \
  --port "8080:443@loadbalancer" \
  --wait

echo "=== 3. Création des namespaces ==="
kubectl create namespace argocd || true
kubectl create namespace dev || true

echo "=== 4. Installation d'Argo CD ==="
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "En attente du démarrage d'Argo CD..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "=== 5. Déploiement de l'Application ==="
kubectl apply -f "$P3_DIR/confs/application.yaml"

echo "=== 6. Informations de connexion ==="
echo "Application URL : http://localhost:8888"
echo "ArgoCD UI       : http://localhost:8080 (ou via kubectl port-forward)"
echo "ArgoCD User     : admin"
echo -n "ArgoCD Password : "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
