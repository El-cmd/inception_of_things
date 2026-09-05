#!/usr/bin/env bash

# BUT DE CE SCRIPT : préparer automatiquement la VM `iot-host` pour travailler
# sur le projet IoT. Il installe les programmes nécessaires et configure la VM.
# Normalement, vous n'avez pas besoin d'exécuter les commandes une par une :
# Vagrant lance ce script pendant le premier `./bin/vagrant up`.

# En langage simple : si une étape importante échoue, on arrête immédiatement
# au lieu de continuer avec une installation incomplète.
# Arrête le script dès qu'une commande échoue (-e), détecte les variables non
# définies (-u), propage les erreurs dans les fonctions (-E) et les pipelines.
set -Eeuo pipefail

# En langage simple : répond automatiquement aux questions de l'installateur.
# Empêche apt d'ouvrir des questions interactives pendant le provisioning.
export DEBIAN_FRONTEND=noninteractive

# Affiche une étape clairement dans les journaux de `vagrant up`.
log() {
  printf '\n[setup] %s\n' "$1"
}

# En langage simple : installer des programmes exige les droits administrateur
# dans la VM. Vagrant donne automatiquement ces droits à ce script.
# Les installations et les services système nécessitent les droits root.
# Le provisioner shell de Vagrant exécute ce fichier en root par défaut.
if [[ $(id -u) -ne 0 ]]; then
  printf 'Ce script doit être exécuté en tant que root.\n' >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  printf 'Impossible de détecter le système.\n' >&2
  exit 1
fi

# En langage simple : vérifie que la VM utilise bien Debian.
# Charge ID, VERSION_CODENAME, PRETTY_NAME, etc. depuis Debian.
# shellcheck disable=SC1091
. /etc/os-release
if [[ ${ID:-} != "debian" ]]; then
  printf 'Ce script est prévu pour Debian, système détecté : %s.\n' "${ID:-inconnu}" >&2
  exit 1
fi

# En langage simple : choisit les programmes adaptés au type de processeur.
# Les URL de kubectl utilisent amd64/arm64 : on refuse toute autre architecture.
case "$(dpkg --print-architecture)" in
  amd64) binary_arch="amd64" ;;
  arm64) binary_arch="arm64" ;;
  *)
    printf 'Architecture non prise en charge : %s.\n' "$(dpkg --print-architecture)" >&2
    exit 1
    ;;
esac

log "Installation des paquets système"
# En langage simple : met à jour la liste des logiciels disponibles, puis
# installe les outils qui serviront dans les parties p1, p2 et p3.
# --no-install-recommends limite les paquets non indispensables et la taille VM.
apt-get update
apt-get install -y --no-install-recommends \
  bash-completion \
  bridge-utils \
  ca-certificates \
  cloud-guest-utils \
  curl \
  dnsmasq-base \
  docker-cli \
  docker.io \
  git \
  gnupg \
  jq \
  libvirt-clients \
  libvirt-daemon-system \
  make \
  nfs-common \
  openssh-client \
  qemu-system-x86 \
  qemu-utils \
  rsync \
  unzip \
  vagrant \
  vagrant-libvirt \
  vim

log "Agrandissement de la partition racine"
# En langage simple : VirtualBox a agrandi le disque virtuel à 40 Gio, mais
# Debian doit encore apprendre à utiliser tout ce nouvel espace.
# findmnt retourne le périphérique monté sur /, normalement /dev/sda1.
root_source=$(findmnt -no SOURCE /)
if [[ "$root_source" =~ ^/dev/([[:alpha:]]+)([0-9]+)$ ]]; then
  # Les groupes capturés séparent /dev/sda (disque) et 1 (partition).
  root_disk="/dev/${BASH_REMATCH[1]}"
  root_partition="${BASH_REMATCH[2]}"
  # growpart étend la partition jusqu'à la fin du disque de 40 Gio.
  # Il retourne parfois 1 lorsque la partition est déjà agrandie : c'est normal.
  growpart "$root_disk" "$root_partition" || true
  # resize2fs donne ensuite tout l'espace de la partition au système ext4.
  resize2fs "$root_source"
else
  printf '[setup] ATTENTION : partition racine non reconnue : %s\n' "$root_source" >&2
fi

log "Activation de Docker et libvirt"
# En langage simple : démarre Docker et le gestionnaire de VM maintenant, puis
# demande à Debian de les redémarrer automatiquement à chaque démarrage.
# --now démarre les services immédiatement ; enable les relance au prochain boot.
systemctl enable --now docker
systemctl enable --now libvirtd

# En langage simple : autorise l'utilisateur `vagrant` à utiliser Docker et KVM
# sans devoir écrire `sudo` devant chaque commande.
# Les prochains shells du compte vagrant recevront ces groupes. La commande
# reste sans effet indésirable si le compte appartient déjà aux groupes.
for group_name in docker libvirt kvm; do
  if getent group "$group_name" >/dev/null 2>&1; then
    usermod -aG "$group_name" vagrant
  fi
done

log "Configuration de la virtualisation KVM imbriquée"
# En langage simple : autorise notre VM à créer elle-même d'autres VM. C'est
# indispensable parce que `iot-host` devra lancer les machines de p1 et p2.
# vmx correspond à Intel VT-x et svm à AMD-V. Le fichier modprobe rend
# l'activation de la virtualisation imbriquée persistante après redémarrage.
if grep -Eqm1 vmx /proc/cpuinfo; then
  printf '%s\n' 'options kvm_intel nested=1' > /etc/modprobe.d/kvm-nested.conf
  modprobe kvm_intel 2>/dev/null || true
elif grep -Eqm1 svm /proc/cpuinfo; then
  printf '%s\n' 'options kvm_amd nested=1' > /etc/modprobe.d/kvm-nested.conf
  modprobe kvm_amd 2>/dev/null || true
else
  printf '[setup] ATTENTION : aucune extension vmx/svm visible.\n' >&2
fi

log "Installation de kubectl"
# En langage simple : kubectl est la commande utilisée pour observer et gérer
# les applications placées dans Kubernetes/K3s.
# Récupère la dernière version stable publiée officiellement par Kubernetes.
kubectl_version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
# Tous les téléchargements temporaires seront effacés à la sortie du script.
download_dir=$(mktemp -d)
trap 'rm -rf "$download_dir"' EXIT

# Télécharge kubectl et son empreinte SHA-256 pour vérifier son intégrité.
curl -fsSLo "$download_dir/kubectl" \
  "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${binary_arch}/kubectl"
curl -fsSLo "$download_dir/kubectl.sha256" \
  "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${binary_arch}/kubectl.sha256"
(
  # Le sous-shell permet de changer de dossier sans modifier le reste du script.
  cd "$download_dir"
  printf '%s  %s\n' "$(cat kubectl.sha256)" kubectl | sha256sum --check
)
# 0755 rend le binaire exécutable par tous les utilisateurs.
install -o root -g root -m 0755 "$download_dir/kubectl" /usr/local/bin/kubectl

log "Installation de K3d"
# En langage simple : K3d permet de créer un petit cluster K3s dans des
# conteneurs Docker. Il sera utilisé pour la partie p3.
# Télécharge d'abord le script officiel, puis l'exécute localement.
curl -fsSLo "$download_dir/install-k3d.sh" \
  https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh
bash "$download_dir/install-k3d.sh"

log "Ajout des complétions Bash"
# En langage simple : après avoir commencé une commande, la touche Tab peut
# proposer ou compléter automatiquement les options disponibles.
# Permet la complétion avec la touche Tab pour kubectl et k3d.
kubectl completion bash > /etc/bash_completion.d/kubectl
k3d completion bash > /etc/bash_completion.d/k3d

log "Versions installées"
# En langage simple : affiche ce qui a été installé et confirme que chaque
# commande peut réellement être lancée.
# Ces commandes servent aussi de dernier test : grâce à `set -e`, une commande
# absente fait échouer le provisioning au lieu de masquer une installation ratée.
git --version
vagrant --version
virsh --version
docker --version
kubectl version --client
k3d version

log "Installation terminée"
printf '%s\n' \
  'Déconnectez-vous puis reconnectez-vous pour appliquer les groupes docker/libvirt/kvm.' \
  'Lancez ensuite : cd /vagrant/vm_base && ./scripts/check-config.sh'
