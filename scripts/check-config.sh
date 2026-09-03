#!/usr/bin/env bash

# BUT DE CE SCRIPT : répondre simplement à la question « est-ce que cette VM
# peut servir de machine hôte pour le projet IoT ? ». Il ne modifie rien : il
# observe la configuration et affiche [OK], [ATTENTION] ou [ERREUR].

# En langage simple : évite qu'une faute dans le nom d'une variable passe
# inaperçue pendant les vérifications.
# Signale l'utilisation d'une variable non définie, tout en laissant le script
# poursuivre les différents contrôles lorsqu'un test retourne un résultat négatif.
set -u

# En langage simple : mémorise combien de problèmes ont été trouvés.
# Compteurs utilisés pour construire le résumé et le code de sortie final.
errors=0
warnings=0

# En langage simple : vert signifie « tout va bien », jaune « à surveiller » et
# rouge « cela peut empêcher le projet de fonctionner ».
# Les séquences \033 colorent les statuts dans le terminal et les logs Vagrant.
ok() {
  printf '\033[32m[OK]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[33m[ATTENTION]\033[0m %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf '\033[31m[ERREUR]\033[0m %s\n' "$1"
  errors=$((errors + 1))
}

section() {
  printf '\n== %s ==\n' "$1"
}

command_version() {
  local command_name=$1
  local version_output
  shift

  # En langage simple : cherche le programme, puis affiche sa version s'il existe.
  # command -v teste la présence d'un exécutable sans réellement le lancer.
  if command -v "$command_name" >/dev/null 2>&1; then
    version_output=$("$@" 2>/dev/null | head -n 1)
    ok "$command_name est installé : $version_output"
  else
    warn "$command_name n'est pas installé"
  fi
}

section "Système"

# En langage simple : identifie le système installé dans la VM.
# /etc/os-release est le fichier standard décrivant une distribution Linux.
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  ok "Système détecté : ${PRETTY_NAME:-inconnu}"
else
  fail "Impossible d'identifier la distribution Linux"
fi

architecture=$(uname -m)
if [[ "$architecture" == "x86_64" ]]; then
  ok "Architecture : $architecture"
else
  fail "Architecture inattendue : $architecture (x86_64 est requis)"
fi

section "Ressources"

# En langage simple : vérifie que la VM a assez de puissance pour faire tourner
# les futures VM, Docker, K3s, K3d et Argo CD.
# nproc indique combien de CPU sont réellement visibles par Debian. VirtualBox
# peut en configurer 8 mais Debian n'en voir qu'un si l'IO-APIC est désactivé.
cpu_count=$(nproc)
if (( cpu_count >= 8 )); then
  ok "$cpu_count processeurs disponibles"
elif (( cpu_count >= 4 )); then
  warn "$cpu_count processeurs disponibles ; 8 sont prévus dans le Vagrantfile"
else
  fail "Seulement $cpu_count processeur(s) disponible(s)"
fi

# MemTotal est exprimé en Kio ; la division par 1024 donne des Mio.
memory_mib=$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)
if (( memory_mib >= 11000 )); then
  ok "Mémoire disponible : ${memory_mib} Mio"
elif (( memory_mib >= 7000 )); then
  warn "Mémoire disponible : ${memory_mib} Mio ; environ 12 Gio sont recommandés"
else
  fail "Mémoire insuffisante : ${memory_mib} Mio"
fi

# Avec -P et -k, df fournit une sortie stable en Kio. Deux divisions par 1024
# donnent approximativement l'espace disponible en Gio.
free_disk_gib=$(df -Pk / | awk 'NR == 2 { print int($4 / 1024 / 1024) }')
if (( free_disk_gib >= 20 )); then
  ok "Espace libre sur / : ${free_disk_gib} Gio"
elif (( free_disk_gib >= 10 )); then
  warn "Espace libre limité sur / : ${free_disk_gib} Gio"
else
  fail "Espace libre insuffisant sur / : ${free_disk_gib} Gio"
fi

section "Virtualisation imbriquée"

# En langage simple : vérifie que `iot-host` a le droit et la capacité de lancer
# d'autres machines virtuelles à l'intérieur d'elle-même.
# La présence de vmx (Intel) ou svm (AMD) prouve que VirtualBox transmet les
# extensions matérielles nécessaires à KVM dans la VM hôte.
if grep -Eqm1 '(vmx|svm)' /proc/cpuinfo; then
  if grep -qm1 vmx /proc/cpuinfo; then
    ok "Extension Intel VT-x (vmx) visible dans la VM"
  else
    ok "Extension AMD-V (svm) visible dans la VM"
  fi
else
  fail "Aucune extension vmx/svm visible : la virtualisation imbriquée ne fonctionnera pas"
fi

# En langage simple : /dev/kvm est la « porte d'accès » au processeur pour les
# VM imbriquées. Sans elle, elles seraient impossibles ou extrêmement lentes.
# /dev/kvm est l'interface utilisée par QEMU/libvirt pour accélérer les VM.
if [[ -e /dev/kvm ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    ok "/dev/kvm existe et est accessible par l'utilisateur actuel"
  else
    warn "/dev/kvm existe mais n'est pas accessible par l'utilisateur actuel"
  fi
else
  fail "/dev/kvm est absent : les VM KVM imbriquées ne pourront pas démarrer"
fi

# Cette information doit normalement valoir "oracle" dans une VM VirtualBox.
if command -v systemd-detect-virt >/dev/null 2>&1; then
  virtualization=$(systemd-detect-virt 2>/dev/null || true)
  ok "Environnement virtualisé détecté : ${virtualization:-aucun}"
fi

section "Outils du projet IoT"

# En langage simple : confirme que les commandes dont nous aurons besoin sont
# présentes. Une commande absente pourra généralement être installée plus tard.
# Une absence est un avertissement plutôt qu'une erreur de virtualisation.
command_version git git --version
command_version curl curl --version
command_version vagrant vagrant --version
command_version virsh virsh --version
command_version docker docker --version
command_version kubectl kubectl version --client
command_version k3d k3d version

section "Résumé"

# En langage simple : zéro erreur signifie que l'on peut commencer le projet.
# Au moins une erreur signifie qu'il faut corriger la VM avant de continuer.
# Un code de sortie non nul fait apparaître le provisioning comme échoué dans
# Vagrant. Les avertissements seuls conservent un code de sortie égal à zéro.
if (( errors == 0 )); then
  ok "Configuration compatible avec la suite du projet"
else
  # Affiche le bilan sans rappeler fail(), sinon le résumé compterait lui-même
  # comme une erreur supplémentaire.
  printf '\033[31m[ERREUR]\033[0m %s erreur(s) bloquante(s) détectée(s)\n' "$errors"
fi

if (( warnings > 0 )); then
  warn "$warnings avertissement(s) à examiner"
fi

exit "$errors"
