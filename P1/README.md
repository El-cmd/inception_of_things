# P1 depuis la machine `vm_base`

## Architecture utilisée

Sur les postes de l'école, le projet utilise plusieurs niveaux :

```text
Ordinateur de l'école
└── VirtualBox : VM iot-host (vm_base)
    └── libvirt : VM nleoniS et VM vlothSW (P1)
```

Le dépôt de l'ordinateur physique est partagé dans `iot-host` sous `/vagrant`.
P1 est donc disponible dans la première VM à cet emplacement :

```bash
cd /vagrant/P1
```

Il n'est pas nécessaire de refaire un `git clone` dans `iot-host`.

## Machines de P1

- `nleoniS` est le serveur K3s, à l'adresse `192.168.56.110` ;
- `vlothSW` est le worker K3s, à l'adresse `192.168.56.111`.

Le worker dépend du serveur. Il est donc préférable de ne pas créer les deux
machines en parallèle.

## Réseau libvirt utilisé par Vagrant

Vagrant attend une adresse DHCP de libvirt pour se connecter en SSH aux VM. Le
plugin crée automatiquement un réseau de gestion nommé `vagrant-libvirt`. On
peut contrôler les réseaux système avec :

```bash
sudo virsh -c qemu:///system net-list --all
```

Après une tentative de création, le résultat doit notamment montrer :

```text
vagrant-libvirt   active
```

Le réseau nommé `default` peut également être activé, mais ce n'est pas lui qui
fournit l'adresse de gestion utilisée ici. Son activation n'a donc pas corrigé
le plantage KVM constaté.

Il faut préciser `qemu:///system`. Sans cette option, `virsh` peut consulter la
session personnelle `qemu:///session` et afficher une liste vide alors que les
réseaux utilisés par Vagrant existent bien.

## Pourquoi KVM a échoué dans VirtualBox

Le premier essai utilisait :

```ruby
v.driver = "kvm"
```

Cela demande une virtualisation matérielle imbriquée : KVM fonctionne alors à
l'intérieur d'une VM VirtualBox. Sur le poste testé, le noyau de `iot-host` a
planté dans `kvm_intel` avec une erreur `vmx_vmexit`.

La VM `nleoniS` restait enregistrée dans libvirt, mais son système ne démarrait
pas et ne recevait aucune adresse DHCP. Vagrant affichait donc :

```text
nleoniS   inaccessible (libvirt)
```

Dans ce cas, `inaccessible` ne signifiait pas que le domaine avait disparu :
son UUID existait encore, mais Vagrant ne pouvait pas obtenir son adresse IP.

## Utiliser QEMU sur les postes de l'école

Dans `P1/Vagrantfile`, remplacez le pilote KVM par cette configuration :

```ruby
config.vm.provider :libvirt do |v|
    # KVM imbriqué plante sur le couple VirtualBox/noyau utilisé à l'école.
    # QEMU émule le processeur : il est plus lent, mais évite ce plantage.
    v.driver = "qemu"
    v.cpu_mode = "custom"
    v.cpu_model = "qemu64"
    v.memory = 1024
    v.cpus = 1
end
```

QEMU sans accélération KVM est sensiblement plus lent. Plusieurs minutes par
machine peuvent être normales, particulièrement au premier lancement.

Sur un PC personnel Linux qui utilise libvirt directement, sans passer par une
VM VirtualBox, KVM reste le meilleur choix :

```ruby
v.driver = "kvm"
```

## Nettoyer une création KVM bloquée

Ces commandes arrêtent et suppriment la VM serveur défectueuse et son disque.
Elles sont à utiliser uniquement si cette première création est bloquée et ne
contient aucune donnée à conserver :

```bash
cd /vagrant/P1
sudo virsh -c qemu:///system destroy P1_nleoniS 2>/dev/null || true
sudo virsh -c qemu:///system undefine P1_nleoniS --remove-all-storage
rm -rf .vagrant/machines/nleoniS
```

Si le worker a également été créé et est bloqué, appliquez le même nettoyage :

```bash
sudo virsh -c qemu:///system destroy P1_vlothSW 2>/dev/null || true
sudo virsh -c qemu:///system undefine P1_vlothSW --remove-all-storage
rm -rf .vagrant/machines/vlothSW
```

## Lancer P1

Depuis l'ordinateur physique, entrez d'abord dans la VM hôte :

```bash
cd vm_base
./bin/vagrant up
./bin/vagrant ssh
```

Puis, dans `iot-host` :

```bash
cd /vagrant/P1
vagrant up --provider=libvirt --no-parallel
```

L'option s'écrit `--no-parallel` avec la lettre `o`. Elle force Vagrant à finir
la création et le provisioning du serveur avant de passer au worker.

Il est aussi possible de lancer explicitement les machines l'une après l'autre :

```bash
vagrant up nleoniS --provider=libvirt
vagrant up vlothSW --provider=libvirt
```

## Commandes utiles

Afficher l'état des deux machines :

```bash
vagrant status
```

Se connecter au serveur ou au worker :

```bash
vagrant ssh nleoniS
vagrant ssh vlothSW
```

Afficher les domaines libvirt :

```bash
sudo virsh -c qemu:///system list --all
```

Afficher les adresses distribuées par DHCP :

```bash
sudo virsh -c qemu:///system net-dhcp-leases vagrant-libvirt
```

Arrêter les deux machines :

```bash
vagrant halt
```

Supprimer complètement les deux machines et leurs disques :

```bash
vagrant destroy -f
```

## Interpréter l'attente d'une adresse IP

Le message suivant est normal pendant quelques dizaines de secondes :

```text
Waiting for domain to get an IP address...
```

S'il reste affiché plusieurs minutes :

1. vérifiez les réseaux avec `sudo virsh -c qemu:///system net-list --all` ;
2. vérifiez les baux avec `sudo virsh -c qemu:///system net-dhcp-leases vagrant-libvirt` ;
3. vérifiez les domaines avec `sudo virsh -c qemu:///system list --all` ;
4. sur une VM VirtualBox, vérifiez que P1 utilise QEMU et non KVM.
