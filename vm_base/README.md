# Machine Vagrant IoT Host

Tous les fichiers de cette machine hôte sont regroupés dans `vm_base/`. Les
commandes de ce document doivent être lancées depuis ce dossier :

```bash
cd vm_base
```

Ce projet lance une machine virtuelle Debian 13 avec VirtualBox, sans droits
`sudo`. Il utilise uniquement VirtualBox : libvirt n'est ni configuré ni
nécessaire.

## Configuration de la machine

- Nom VirtualBox : `iot-host`
- Nom d'hôte Debian : `iot`
- Système : Debian 13 AMD64
- Mémoire : 12 Go
- Processeurs : 8
- Disque : 40 Go. Après une première importation, le wrapper contrôle la taille
  réelle du disque, l'agrandit si nécessaire, puis redémarre automatiquement la
  VM pour que Debian étende sa partition.
- Réseau : NAT, avec SSH redirigé vers `127.0.0.1:2222`
- Virtualisation imbriquée : activée
- IO-APIC : activé pour permettre à Debian d'utiliser les 8 processeurs

Le script `scripts/setup.sh` est exécuté en tant que `root` lors du premier
provisioning. Il prépare la VM hôte avec les outils nécessaires aux trois
parties du projet :

- Git, curl, jq et les utilitaires système ;
- QEMU/KVM, libvirt, Vagrant et le plugin `vagrant-libvirt` pour les VM
  imbriquées de `p1` et `p2` ;
- Docker, kubectl et K3d pour `p3` ;
- les groupes et services nécessaires au compte `vagrant`.

Il n'installe pas K3s directement : chaque partie devra fournir ses propres
scripts d'installation et de configuration de K3s, conformément au sujet.

Le script `scripts/check-config.sh` contrôle la configuration de la VM hôte sans
la modifier. Il est exécuté automatiquement après `setup.sh`, puis à chaque
`./bin/vagrant up`. Une ligne `[ERREUR]` fait échouer l'étape de provisioning
pour signaler que la configuration n'est pas compatible.

Pour le relancer manuellement depuis la VM :

```bash
cd /vagrant/vm_base
./scripts/check-config.sh
```

Il vérifie notamment les CPU, la mémoire, l'espace disque, les extensions
`vmx`/`svm`, l'accès à `/dev/kvm` et la présence des outils nécessaires au
projet. Une ligne `[ATTENTION]` indique un outil à installer ou un réglage
conseillé.

## Adaptations effectuées

L'ordinateur de l'école possède Vagrant 2.3.4 et VirtualBox 7.2. Cette version
de Vagrant refuse normalement VirtualBox 7.2, car elle ne reconnaît que les
versions allant jusqu'à 7.0.

Les scripts locaux suivants contournent ce contrôle sans modifier le système et
sans demander de droits administrateur :

- `bin/VBoxManage` présente la version 7.2 comme une version 7.0 uniquement lors
  du contrôle effectué par Vagrant ;
- `bin/vagrant` ajoute automatiquement ce wrapper au `PATH`, puis lance le vrai
  Vagrant installé dans `/usr/bin/vagrant`. Il sélectionne également VirtualBox
  comme fournisseur par défaut.

Il faut donc utiliser `./bin/vagrant` dans ce projet plutôt que la commande
globale `vagrant`. Il n'est pas nécessaire d'ajouter
`--provider=virtualbox` aux commandes.

Vagrant 2.3.4 choisissait également une image ARM64 incompatible avec cet
ordinateur x86_64. La box VirtualBox AMD64 a donc été installée explicitement
sous le nom local `cloud-image/debian-13-vbox-amd64`. Lors du premier
`./bin/vagrant up` d'une nouvelle session, le wrapper trouve la version AMD64
actuelle dans le catalogue officiel et crée automatiquement cet alias local.
L'erreur 404 sur ce nom ne doit donc plus apparaître et aucune connexion à
Vagrant Cloud n'est nécessaire.

Sur les postes de l'école, le wrapper place automatiquement les gros fichiers
de la VM dans un dossier propre à la session connectée :

```text
/goinfre/<login>/iot-virtualbox
```

Cela donne par exemple `/goinfre/vloth/iot-virtualbox`,
`/goinfre/msall/iot-virtualbox` ou `/goinfre/nleoni/iot-virtualbox`. Aucun login
n'est écrit en dur dans les scripts. Sur un ordinateur personnel où `/goinfre`
n'existe pas, le dossier VirtualBox configuré sur cet ordinateur est conservé.
Le wrapper recherche aussi les emplacements d'installation habituels de
Vagrant et VirtualBox sous Linux et macOS.

Pour imposer soi-même un emplacement, utilisez par exemple :

```bash
VAGRANT_VM_STORAGE=/chemin/avec/assez/de/place ./bin/vagrant up
```

Le dossier `.vagrant` est un état local : il contient notamment l'identifiant
de la VM du compte courant. Il est ignoré par Git et ne doit pas être envoyé à
un ami. Si le dépôt est déplacé, ou si cet identifiant pointe vers une VM dont
les fichiers ont disparu, le wrapper nettoie automatiquement cet état lors du
prochain `up`.

## Commandes principales

Toutes les commandes suivantes doivent être exécutées depuis `vm_base/`.

Afficher l'état de la machine :

```bash
./bin/vagrant status
```

Créer et démarrer la machine si elle n'existe pas, ou simplement la démarrer si
elle existe déjà :

```bash
./bin/vagrant up
```

Se connecter à Debian en SSH :

```bash
./bin/vagrant ssh
```

Éteindre proprement la machine :

```bash
./bin/vagrant halt
```

Redémarrer la machine et appliquer les changements du `Vagrantfile` :

```bash
./bin/vagrant reload
```

Suspendre la machine en conservant son état en mémoire :

```bash
./bin/vagrant suspend
```

Reprendre une machine suspendue :

```bash
./bin/vagrant resume
```

Relancer manuellement le script de provisioning :

```bash
./bin/vagrant provision
```

Le relancer pendant un démarrage :

```bash
./bin/vagrant up --provision
```

Supprimer complètement la machine virtuelle :

```bash
./bin/vagrant destroy
```

Vagrant demande alors une confirmation. Pour supprimer sans confirmation :

```bash
./bin/vagrant destroy -f
```

Attention : `destroy` supprime le disque de la VM et toutes les données qui y
ont été enregistrées. Le projet, le `Vagrantfile` et la box de base restent
présents.

## Recréer la machine depuis zéro

```bash
./bin/vagrant destroy -f
./bin/vagrant up
```

Pour forcer également l'exécution du provisioning :

```bash
./bin/vagrant destroy -f
./bin/vagrant up --provision
```

## Commandes complémentaires

Afficher la configuration SSH :

```bash
./bin/vagrant ssh-config
```

Afficher les boxes installées :

```bash
./bin/vagrant box list
```

Afficher les machines VirtualBox en cours d'exécution :

```bash
VBoxManage list runningvms
```

Vérifier Debian et les ressources depuis l'hôte :

```bash
./bin/vagrant ssh -c 'hostname; cat /etc/debian_version; nproc; free -h'
```

## Avertissement Guest Additions

Vagrant peut signaler que la version des Guest Additions de la box ne correspond
pas exactement à celle de VirtualBox. La machine et SSH fonctionnent malgré cet
avertissement. Il devient important uniquement si les dossiers partagés ou
d'autres intégrations VirtualBox ne fonctionnent pas correctement.
