# Dépannage Vagrant sur une nouvelle session

### Origine de l'erreur 404

La commande `./bin/vagrant up` cherchait la box suivante :

```text
cloud-image/debian-13-vbox-amd64
```

Ce nom correspondait à une box installée uniquement dans le cache de
l'ancienne session. Ce n'est pas une box publique de Vagrant Cloud. Comme la
nouvelle session ne possédait aucune box, Vagrant tentait de télécharger une
adresse inexistante et recevait une erreur HTTP 404.

Le diagnostic initial a été réalisé avec :

```bash
./bin/vagrant --version
./bin/vagrant box list
```

La machine utilisait Vagrant 2.3.4 et la liste des boxes était vide.

### Téléchargement de la box Debian 13 AMD64

Une box publique Bento Debian 13 pour VirtualBox AMD64 a été choisie. Cette
première commande a été testée :

```bash
./bin/vagrant box add \
  --name cloud-image/debian-13-vbox-amd64 \
  https://vagrantcloud.com/bento/boxes/debian-13/versions/202510.26.0/providers/virtualbox/amd64/vagrant.box
```

Vagrant 2.3.4 a mal interprété le fichier compressé comme des métadonnées JSON
et a affiché `The metadata for the box was malformed`. Le fichier a donc été
téléchargé séparément :

```bash
mkdir -p .cache/vagrant-boxes
curl --fail --location --progress-bar \
  --output .cache/vagrant-boxes/debian-13-amd64.box \
  https://vagrantcloud.com/bento/boxes/debian-13/versions/202510.26.0/providers/virtualbox/amd64/vagrant.box
```

### Utilisation de `/goinfre`

L'import suivant a révélé que le disque personnel était plein. `/home/msall`
avait atteint 100 % de ses 4,7 Go, alors que `/goinfre` disposait de plus de
120 Go libres. Les contrôles employés étaient :

```bash
df -h "$HOME" /goinfre
du -sh "$HOME/.vagrant.d" .cache/vagrant-boxes
```

Les dossiers de stockage ont alors été créés dans `/goinfre` :

```bash
mkdir -p \
  /goinfre/msall/vagrant-home \
  /goinfre/msall/vagrant-boxes \
  /goinfre/msall/iot-virtualbox

mv .cache/vagrant-boxes/debian-13-amd64.box \
  /goinfre/msall/vagrant-boxes/debian-13-amd64.box
```

Les fichiers temporaires laissés dans `~/.vagrant.d/tmp` par les imports
échoués ont été déplacés hors du disque personnel, libérant environ 700 Mo.

### Installation locale de la box

La box a été ajoutée dans le cache placé sur `/goinfre`, sous le nom exact
attendu par le `Vagrantfile` :

```bash
VAGRANT_HOME=/goinfre/msall/vagrant-home \
  ./bin/vagrant box add \
  --name cloud-image/debian-13-vbox-amd64 \
  /goinfre/msall/vagrant-boxes/debian-13-amd64.box
```

Sa présence a été contrôlée avec :

```bash
VAGRANT_HOME=/goinfre/msall/vagrant-home ./bin/vagrant box list
```

### Premier démarrage

Le cache Vagrant et les fichiers de la VM ont été explicitement dirigés vers
`/goinfre` lors du premier lancement :

```bash
VAGRANT_HOME=/goinfre/msall/vagrant-home \
VAGRANT_VM_STORAGE=/goinfre/msall/iot-virtualbox \
  ./bin/vagrant up
```

Le wrapper `bin/vagrant` a ensuite été corrigé afin qu'il utilise
automatiquement, pour chaque utilisateur connecté :

```text
/goinfre/<login>/vagrant-home
/goinfre/<login>/iot-virtualbox
```

L'ancien wrapper testait les droits d'écriture directement sur `/goinfre`.
Cette racine appartient à `root`, mais `/goinfre/<login>` appartient à
l'utilisateur. Le nouveau test porte donc sur le sous-dossier personnel et ne
demande aucun droit `sudo`.

Les commandes normales fonctionnent maintenant sans variables supplémentaires :

```bash
./bin/vagrant up
./bin/vagrant status
./bin/vagrant ssh
./bin/vagrant halt
```

### Vérifications finales

La VM a été contrôlée avec les commandes suivantes :

```bash
./bin/vagrant box list
./bin/vagrant status
./bin/vagrant ssh -c 'hostname; cat /etc/debian_version; nproc; free -h'
./bin/vagrant ssh -c 'test -c /dev/kvm && echo /dev/kvm:OK'
```

Résultat obtenu :

```text
État               : running
Nom d'hôte         : iot
Debian             : 13.1 AMD64
Processeurs        : 8
Mémoire            : environ 12 Gio
Virtualisation KVM : disponible
```

Le provisioning a aussi validé Git, curl, Vagrant, libvirt, Docker, kubectl et
K3d. L'avertissement sur la différence de version des Guest Additions
VirtualBox est attendu et n'empêche pas cette VM de fonctionner.
