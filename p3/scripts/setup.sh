#!/usr/bin/env bash

# Prépare entièrement la partie 3 dans la VM hôte : Docker, kubectl, K3d,
# Argo CD et l'application suivie dans le dépôt GitHub public.
set -Eeuo pipefail

CLUSTER_NAME="iot-cluster"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
P3_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

log() {
  printf '\n[p3] %s\n' "$1"
}

fail() {
  printf '[p3] ERREUR : %s\n' "$1" >&2
  exit 1
}

# Les installations système demandent sudo, mais le script peut aussi être
# lancé directement par root pendant une démonstration.
if [[ $(id -u) -eq 0 ]]; then
  SUDO=()
  TARGET_USER=${SUDO_USER:-root}
else
  command -v sudo >/dev/null 2>&1 || fail "sudo est nécessaire pour installer les outils."
  SUDO=(sudo)
  TARGET_USER=${USER}
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -n "$TARGET_HOME" ]] || fail "impossible de trouver le dossier personnel de $TARGET_USER."
TARGET_GROUP=$(id -gn "$TARGET_USER")

if [[ ! -r /etc/os-release ]]; then
  fail "impossible de détecter le système Linux."
fi

# Cette partie est exécutée dans la VM Debian fournie par vm_base.
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == "debian" ]] || fail "ce script est prévu pour Debian (détecté : ${ID:-inconnu})."

case "$(dpkg --print-architecture)" in
  amd64) BINARY_ARCH=amd64 ;;
  arm64) BINARY_ARCH=arm64 ;;
  *) fail "architecture non prise en charge : $(dpkg --print-architecture)" ;;
esac

log "Installation des paquets nécessaires"
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  docker-cli \
  docker.io \
  git

"${SUDO[@]}" systemctl enable --now docker
if getent group docker >/dev/null 2>&1; then
  "${SUDO[@]}" usermod -aG docker "$TARGET_USER"
fi

DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

if ! command -v kubectl >/dev/null 2>&1; then
  log "Installation de kubectl"
  KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSLo "$DOWNLOAD_DIR/kubectl" \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${BINARY_ARCH}/kubectl"
  curl -fsSLo "$DOWNLOAD_DIR/kubectl.sha256" \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${BINARY_ARCH}/kubectl.sha256"
  printf '%s  %s\n' "$(cat "$DOWNLOAD_DIR/kubectl.sha256")" "$DOWNLOAD_DIR/kubectl" \
    | sha256sum --check
  "${SUDO[@]}" install -o root -g root -m 0755 "$DOWNLOAD_DIR/kubectl" /usr/local/bin/kubectl
fi

if ! command -v k3d >/dev/null 2>&1; then
  log "Installation de K3d"
  curl -fsSLo "$DOWNLOAD_DIR/install-k3d.sh" \
    https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh
  "${SUDO[@]}" bash "$DOWNLOAD_DIR/install-k3d.sh"
fi

# Un utilisateur ajouté au groupe docker doit normalement rouvrir sa session.
# Pour que la démonstration fonctionne immédiatement, on utilise sudo pour K3d
# uniquement lorsque le Docker de l'utilisateur n'est pas encore accessible.
K3D_AS_ROOT=false
if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
  K3D=(k3d)
elif "${SUDO[@]}" docker info >/dev/null 2>&1; then
  DOCKER=("${SUDO[@]}" docker)
  K3D=("${SUDO[@]}" k3d)
  K3D_AS_ROOT=true
else
  fail "Docker ne répond pas malgré le démarrage de son service."
fi

log "Création propre du cluster K3d"
"${K3D[@]}" cluster delete "$CLUSTER_NAME" >/dev/null 2>&1 || true
"${K3D[@]}" cluster create "$CLUSTER_NAME" \
  --wait \
  --timeout 180s \
  --port "8888:80@loadbalancer"

# Rend le kubeconfig lisible par l'utilisateur vagrant même si K3d a dû être
# lancé avec sudo. Ainsi les commandes kubectl restent utilisables sans sudo.
KUBECONFIG_TMP="$DOWNLOAD_DIR/kubeconfig"
"${K3D[@]}" kubeconfig get "$CLUSTER_NAME" > "$KUBECONFIG_TMP"
"${SUDO[@]}" install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m 0700 "$TARGET_HOME/.kube"
"${SUDO[@]}" install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 0600 \
  "$KUBECONFIG_TMP" "$TARGET_HOME/.kube/config"
export KUBECONFIG="$TARGET_HOME/.kube/config"

kubectl wait --for=condition=Ready nodes --all --timeout=180s

# Sur une VM VirtualBox un peu lente, K3s peut terminer son premier démarrage
# avant la création d'une permission interne. Dans ce cas son API redémarre et
# kubectl peut attendre indéfiniment. Le journal permet de reconnaître ce cas ;
# un redémarrage du conteneur suffit ensuite, car la permission existe déjà.
sleep 10
if "${DOCKER[@]}" logs --since 2m "k3d-${CLUSTER_NAME}-server-0" 2>&1 \
  | grep -q 'cloud-controller-manager exited: unable to load configmap'; then
  log "Redémarrage de K3s après une course de démarrage détectée"
  "${DOCKER[@]}" restart "k3d-${CLUSTER_NAME}-server-0" >/dev/null
fi

# On exige plusieurs réponses successives afin de ne pas confondre un bref
# démarrage de l'API avec un cluster réellement stable.
API_STABLE=false
CONSECUTIVE_READY=0
for _ in $(seq 1 60); do
  if kubectl --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then
    CONSECUTIVE_READY=$((CONSECUTIVE_READY + 1))
    if [[ $CONSECUTIVE_READY -ge 5 ]]; then
      API_STABLE=true
      break
    fi
  else
    CONSECUTIVE_READY=0
  fi
  sleep 2
done
[[ $API_STABLE == true ]] || fail "l'API Kubernetes n'est pas devenue stable."

log "Création des namespaces argocd et dev"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

log "Installation d'Argo CD"
timeout 180s kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Established \
  crd/applications.argoproj.io --timeout=180s
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s

log "Création de l'application Argo CD"
kubectl apply -f "$P3_DIR/confs/application.yaml"

# Argo CD doit d'abord lire GitHub avant que le Deployment existe. On attend
# son apparition, puis son état Ready, afin que le script détecte un vrai échec.
for _ in $(seq 1 60); do
  if kubectl get deployment/iot-app -n dev >/dev/null 2>&1; then
    break
  fi
  sleep 5
done
kubectl get deployment/iot-app -n dev >/dev/null 2>&1 \
  || fail "Argo CD n'a pas créé le Deployment iot-app après 5 minutes."
kubectl rollout status deployment/iot-app -n dev --timeout=300s

log "Vérification de l'application sur localhost:8888"
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8888/ >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS http://localhost:8888/ >/dev/null \
  || fail "l'application ne répond pas sur http://localhost:8888/."

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode)

log "Installation terminée"
printf '%s\n' \
  "Application : http://localhost:8888/" \
  "Utilisateur Argo CD : admin" \
  "Mot de passe Argo CD : $ARGOCD_PASSWORD" \
  "Interface Argo CD : ./scripts/argocd-ui.sh"

if [[ $K3D_AS_ROOT == true ]]; then
  printf '%s\n' \
    "Remarque : K3d a utilisé sudo car le groupe docker n'était pas encore actif." \
    "À la prochaine connexion SSH, Docker et K3d fonctionneront sans sudo."
fi
