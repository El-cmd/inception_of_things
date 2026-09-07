# P2 — K3s et trois applications

Cette partie crée une machine virtuelle contenant un serveur K3s et trois
applications web. Un Ingress choisit l'application à afficher grâce au nom
envoyé dans la requête HTTP :

```text
app1.com                 -> app1
app2.com                 -> app2 (3 réplicas)
autre nom ou adresse IP  -> app3
```

## Architecture simple

```text
Ordinateur physique
└── VirtualBox : iot-host
    └── QEMU/libvirt : nleoniS (192.168.56.110)
        └── K3s
            ├── app1
            ├── app2 x3
            ├── app3
            └── Ingress
```

VirtualBox sert uniquement à lancer la première VM `iot-host`. La VM de P2 est
ensuite créée dans `iot-host` avec Vagrant, libvirt et QEMU.

## Contenu du dossier

```text
P2/
├── Vagrantfile
├── scripts/
│   └── setup.sh
└── manifests/
    ├── app1.yaml
    ├── app2.yaml
    ├── app3.yaml
    └── ingress.yaml
```

- `Vagrantfile` décrit la machine virtuelle.
- `scripts/setup.sh` installe et configure K3s.
- Les fichiers YAML décrivent les applications, les Services et l'Ingress.

## Lancer P2

Depuis l'ordinateur physique, démarrer la VM principale puis s'y connecter :

```bash
cd vm_base
./bin/vagrant up
./bin/vagrant ssh
```

Dans la VM `iot-host`, aller dans P2 et créer la VM `nleoniS` :

```bash
cd /vagrant/P2
vagrant up --provider=libvirt
```

Le premier lancement est assez long. Vagrant doit télécharger Debian, créer la
VM, installer K3s et télécharger les images des applications.

Commandes Vagrant utiles :

```bash
vagrant status             # afficher l'état de la VM
vagrant ssh nleoniS        # entrer dans la VM de P2
vagrant halt               # arrêter proprement la VM
vagrant reload             # redémarrer la VM
vagrant provision          # relancer uniquement le script setup.sh
vagrant destroy -f         # supprimer complètement la VM et son disque
```

`destroy -f` efface la VM. Il ne supprime pas les fichiers du dépôt.

## Comprendre le Vagrantfile

### Choix du système

```ruby
config.vm.box = "debian/trixie64"
```

Une `box` est une image de départ utilisée par Vagrant. Ici, la VM utilise
Debian 13, aussi appelé Trixie.

### Dossier partagé par défaut désactivé

```ruby
config.vm.synced_folder ".", "/vagrant", disabled: true
```

Vagrant partage normalement tout le dossier du projet dans `/vagrant`. Ce
partage est désactivé pour la VM imbriquée. Seul le dossier `manifests` sera
envoyé avec `rsync` plus bas.

### Fournisseur et ressources

```ruby
config.vm.provider :libvirt do |v|
    v.driver = "qemu"
    v.cpu_mode = "custom"
    v.cpu_model = "qemu64"
    v.memory = 2048
    v.cpus = 2
end
```

- `libvirt` gère la VM à l'intérieur de `iot-host`.
- `qemu` émule le processeur. Il est plus lent que KVM, mais plus fiable dans
  une VM VirtualBox.
- `qemu64` fournit un modèle de processeur compatible.
- La VM reçoit 2 Gio de mémoire et 2 processeurs virtuels.

### Nom et adresse de la VM

```ruby
config.vm.define "nleoniS" do |node|
    node.vm.hostname = "nleoniS"
    node.vm.network "private_network", ip: "192.168.56.110"
end
```

La VM s'appelle `nleoniS` et reçoit l'adresse privée `192.168.56.110` demandée
par le sujet.

### Copie des manifests et provisioning

```ruby
node.vm.synced_folder "./manifests", "/home/vagrant/manifests", type: "rsync"
node.vm.provision "shell", path: "scripts/setup.sh"
```

- `rsync` copie les manifests dans `/home/vagrant/manifests` dans la VM.
- Le provisioner `shell` exécute ensuite `scripts/setup.sh` en tant que `root`.
- Ce partage n'est pas une synchronisation permanente. Après une modification,
  utiliser `vagrant rsync` ou relancer le provisioning.

## Comprendre scripts/setup.sh

### Arrêter le script en cas d'erreur

```bash
set -e
```

Si une commande importante échoue, le script s'arrête immédiatement. Cela évite
de continuer avec une installation incomplète.

### Installer curl

```bash
apt-get update -y
apt-get install -y curl
```

- `apt-get update` actualise la liste des paquets disponibles.
- `apt-get install` installe `curl`.
- `-y` répond automatiquement « oui » pendant l'installation.

`curl` servira à télécharger le programme d'installation de K3s.

### Configurer le réseau

```bash
ip addr add 192.168.56.110/24 dev eth1 2>/dev/null || true
ip link set eth1 up
```

- `ip addr add` ajoute l'adresse `192.168.56.110` à l'interface `eth1`.
- `/24` correspond au masque réseau `255.255.255.0`.
- `2>/dev/null` masque le message d'erreur si l'adresse existe déjà.
- `|| true` empêche le script de s'arrêter dans ce cas normal.
- `ip link set eth1 up` active l'interface réseau.

### Changer le nom de la machine

```bash
hostnamectl set-hostname nleoniS && sed -i 's/trixie/nleoniS/g' /etc/hosts
```

- `hostnamectl` définit le nom `nleoniS`.
- `&&` lance la deuxième commande seulement si la première réussit.
- `sed -i` remplace `trixie` par `nleoniS` directement dans `/etc/hosts`.

### Préparer les options de K3s

```bash
export INSTALL_K3S_EXEC="--node-ip=192.168.56.110 --flannel-iface=eth1 --token=K3S_TOKEN --write-kubeconfig-mode=644"
```

Cette variable donne plusieurs options à l'installateur :

- `--node-ip` indique l'adresse du serveur K3s.
- `--flannel-iface` choisit l'interface utilisée par le réseau Kubernetes.
- `--token` définit le secret du cluster.
- `--write-kubeconfig-mode=644` permet à l'utilisateur `vagrant` de lire la
  configuration de Kubernetes.

### Installer K3s

```bash
curl -sfL https://get.k3s.io | sh -
```

- `curl` télécharge le script officiel de K3s.
- `-s` réduit les messages affichés.
- `-f` signale une erreur si le téléchargement échoue.
- `-L` suit les redirections HTTP.
- `| sh -` transmet le script téléchargé à `sh` pour l'exécuter.

K3s installe un petit cluster Kubernetes. Il fournit aussi `kubectl` et Traefik,
le contrôleur Ingress utilisé par P2.

### Attendre que K3s soit prêt

```bash
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    sleep 1
done
```

La boucle vérifie chaque seconde si K3s a créé son fichier `node-token`. Tant
que le fichier n'existe pas, le script attend.

### Configurer kubectl

```bash
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc
```

- `mkdir -p` crée le dossier de configuration.
- `cp` copie la configuration générée par K3s.
- `chown` donne les fichiers à l'utilisateur `vagrant`.
- La dernière commande ajoute `KUBECONFIG` au prochain terminal Bash.

Grâce à cela, l'utilisateur `vagrant` peut utiliser directement `kubectl`.

### Installer automatiquement les manifests

```bash
mkdir -p /var/lib/rancher/k3s/server/manifests
cp /home/vagrant/manifests/*.yaml /var/lib/rancher/k3s/server/manifests/
```

K3s surveille le dossier `/var/lib/rancher/k3s/server/manifests`. Chaque fichier
YAML copié dans ce dossier est automatiquement appliqué au cluster.

## Comprendre les manifests des applications

Chaque fichier `app1.yaml`, `app2.yaml` ou `app3.yaml` contient deux objets
séparés par `---` :

```text
Deployment -> crée et surveille les Pods
Service    -> donne une adresse stable aux Pods
```

### Le Deployment

Exemple simplifié :

```yaml
kind: Deployment
metadata:
  name: app1
spec:
  replicas: 1
```

- `kind: Deployment` demande à Kubernetes de gérer l'application.
- `name` donne un nom à cette ressource.
- `replicas` indique combien de copies, appelées Pods, doivent fonctionner.

App1 et app3 ont un seul réplica. App2 en possède trois, comme demandé dans le
sujet :

```yaml
replicas: 3
```

### Les labels et selectors

```yaml
selector:
  matchLabels:
    app: app1
template:
  metadata:
    labels:
      app: app1
```

Un `label` est une étiquette placée sur un Pod. Le `selector` permet au
Deployment et au Service de retrouver les Pods portant la bonne étiquette.

Les valeurs doivent correspondre. Le Service d'app1 cherche donc les Pods
portant le label `app: app1`.

### Le conteneur

```yaml
containers:
- name: app1
  image: paulbouwer/hello-kubernetes:1.10
  env:
  - name: MESSAGE
    value: "Hello from app1"
  ports:
  - containerPort: 8080
```

- `image` est l'image de conteneur téléchargée pour démarrer l'application.
- `MESSAGE` change le texte affiché par l'application.
- L'application écoute sur le port `8080` dans le conteneur.

### Le Service

```yaml
kind: Service
spec:
  type: ClusterIP
  selector:
    app: app1
  ports:
  - port: 80
    targetPort: 8080
```

- `ClusterIP` rend le Service accessible uniquement dans le cluster.
- `selector` envoie le trafic vers les Pods de la bonne application.
- `port: 80` est le port du Service.
- `targetPort: 8080` est le port réellement utilisé dans le conteneur.

Pour app2, le Service distribue automatiquement les requêtes entre ses trois
Pods.

## Comprendre ingress.yaml

L'Ingress est la porte d'entrée HTTP du cluster :

```text
requête HTTP -> Ingress -> Service -> Pod
```

Cette règle envoie `app1.com` vers `app1-service` :

```yaml
- host: app1.com
  http:
    paths:
    - path: /
      pathType: Prefix
      backend:
        service:
          name: app1-service
          port:
            number: 80
```

- `host` est le nom demandé par le client HTTP.
- `path: /` accepte toutes les adresses commençant par `/`.
- `pathType: Prefix` indique que le début du chemin doit correspondre.
- `backend` désigne le Service qui recevra la requête.

Une deuxième règle fait la même chose pour `app2.com`. `defaultBackend` et la
règle sans `host` dirigent toutes les autres requêtes vers `app3-service`.

## Vérifier le cluster

Entrer d'abord dans la VM P2 :

```bash
cd /vagrant/P2
vagrant ssh nleoniS
```

Puis utiliser les commandes suivantes :

```bash
kubectl get nodes -o wide       # afficher le serveur K3s
kubectl get deployments        # afficher les trois Deployments
kubectl get pods -o wide        # afficher les cinq Pods attendus
kubectl get services           # afficher les Services
kubectl get ingress            # afficher l'Ingress
kubectl get all                # afficher les ressources principales
```

Cinq Pods d'application sont attendus : un pour app1, trois pour app2 et un
pour app3. Leur état doit devenir `Running`.

Pour suivre leur démarrage en direct :

```bash
kubectl get pods --watch
```

Quitter l'affichage avec `Ctrl+C`.

Pour obtenir des détails lorsqu'une ressource ne fonctionne pas :

```bash
kubectl describe pod NOM_DU_POD
kubectl logs NOM_DU_POD
kubectl describe ingress app-ingress
```

## Tester les trois applications

Depuis `iot-host` ou depuis `nleoniS` :

```bash
curl -H "Host: app1.com" http://192.168.56.110
curl -H "Host: app2.com" http://192.168.56.110
curl http://192.168.56.110
```

Résultats attendus :

- la première commande affiche `Hello from app1` ;
- la deuxième affiche `Hello from app2 (3 replicas)` ;
- la troisième affiche `Hello from default app (app3)`.

On peut aussi utiliser `--resolve`, qui associe temporairement un nom à l'IP et
envoie automatiquement le bon en-tête `Host` :

```bash
curl --resolve app1.com:80:192.168.56.110 http://app1.com/
curl --resolve app2.com:80:192.168.56.110 http://app2.com/
```

## Appliquer une modification

Pour tester rapidement une modification depuis la VM `nleoniS` :

```bash
kubectl apply -f /home/vagrant/manifests/
```

Si les fichiers ont été modifiés sur l'ordinateur physique, il faut d'abord les
recopier depuis `iot-host` :

```bash
cd /vagrant/P2
vagrant rsync
vagrant ssh nleoniS
kubectl apply -f /home/vagrant/manifests/
```

Après l'application d'un changement, contrôler le résultat :

```bash
kubectl get pods
kubectl get deployments
kubectl get ingress
```

## Résumé à retenir

```text
Vagrantfile  -> crée la VM nleoniS
setup.sh     -> installe K3s
Deployment  -> maintient le bon nombre de Pods
Service     -> donne un point d'accès stable aux Pods
Ingress     -> choisit l'application selon le nom HTTP
kubectl     -> permet d'observer et de modifier Kubernetes
curl        -> permet de tester les applications
```
