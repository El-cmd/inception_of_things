# Bonus — GitLab local

Ce bonus reprend exactement la P3, mais Argo CD lit maintenant les manifests
depuis un GitLab local au lieu de GitHub.

```text
GitLab local (namespace gitlab)
              ↓
Argo CD (namespace argocd)
              ↓
Application (namespace dev)
```

Le script utilise l'image officielle la plus récente `gitlab/gitlab-ce:latest`.
Cette installation simple est prévue uniquement pour le projet et non pour un
serveur de production.

Attention : `setup.sh` supprime et recrée le cluster K3d `iot-cluster`. Les
données de l'ancien cluster sont donc supprimées.

## Installation

Sur l'ordinateur physique, appliquer d'abord le nouveau port GitLab. Utiliser
`up` pour une première création, ou `reload` si `iot-host` fonctionne déjà :

```bash
cd vm_base
./bin/vagrant up
# ou : ./bin/vagrant reload
./bin/vagrant ssh
```

Dans la VM `iot-host` :

```zsh
cd /vagrant/bonus
./scripts/setup.sh
```

Le script effectue automatiquement les opérations suivantes :

1. il recrée la P3 et le cluster `iot-cluster` ;
2. il crée le namespace `gitlab` ;
3. il installe GitLab CE ;
4. il crée le projet public `root/iot-app` ;
5. il ajoute le manifest utilisant l'image v1 ;
6. il connecte Argo CD au dépôt GitLab local.

GitLab est assez lourd. Son premier démarrage peut prendre 10 à 20 minutes.

## Ouvrir GitLab

Dans `iot-host`, lancer :

```zsh
cd /vagrant/bonus
./scripts/gitlab-ui.sh
```

Garder ce terminal ouvert, puis visiter sur l'ordinateur physique :

```text
http://localhost:8929
```

Le script affiche l'utilisateur `root` et son mot de passe local.

## Tester l'application

```zsh
curl http://localhost:8888/
```

Au départ, l'application utilise la version v1.

## Passer de v1 à v2

Dans un autre terminal de `iot-host` :

```zsh
cd /vagrant/bonus
./scripts/switch-version.sh v2
curl http://localhost:8888/
```

Le script crée un vrai commit dans le GitLab local. Argo CD détecte ensuite ce
commit et déploie l'image v2.

Pour revenir en v1 :

```zsh
./scripts/switch-version.sh v1
```

## Vérifications pour l'évaluation

```zsh
kubectl get namespaces
kubectl get pods -n gitlab
kubectl get pods -n argocd
kubectl get pods -n dev
kubectl get application iot-app -n argocd
kubectl get deployment iot-app -n dev \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

Les trois namespaces importants doivent exister : `gitlab`, `argocd` et `dev`.
