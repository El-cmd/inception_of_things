# p3 — K3d, Argo CD et GitOps

Cette partie installe K3d dans la VM `iot-host`, déploie Argo CD et lui demande
de synchroniser automatiquement l'application depuis le dépôt GitHub public
[`harmoos/iot-app-nleoni`](https://github.com/harmoos/iot-app-nleoni).

## Architecture

```text
GitHub public (Deployment, Service, Ingress)
                    │
                    ▼
Argo CD ── synchronisation automatique ──► namespace dev
                                                │
                                                ▼
                                    http://localhost:8888
```

Les images publiques utilisées sont :

- `vloth2602/iot-app:v1` ;
- `vloth2602/iot-app:v2`.

## Installation complète

Dans la VM `iot-host` :

```bash
cd /vagrant/p3
./scripts/setup.sh
```

Le script installe les outils manquants, crée le cluster `iot-cluster`, crée les
namespaces `argocd` et `dev`, installe Argo CD et attend que l'application soit
réellement disponible.

Il recrée entièrement le cluster à chaque exécution. Cette propriété permet de
rejouer facilement la démonstration depuis un état propre.

## Vérifications utiles

```bash
kubectl get namespaces
kubectl get pods -n argocd
kubectl get pods -n dev
kubectl get application -n argocd
kubectl get ingress,service,deployment -n dev
curl http://localhost:8888/
```

Pour ouvrir l'interface d'Argo CD :

```bash
cd /vagrant/p3
./scripts/argocd-ui.sh
```

Puis ouvrir `https://localhost:8080`. Avec `vm_base`, les ports `8888` et `8080`
sont transmis au poste physique : ces deux adresses sont donc également
accessibles dans son navigateur après un `vagrant reload`. L'utilisateur Argo CD
est `admin` et le script affiche le mot de passe initial. L'avertissement du
navigateur sur le certificat local est normal.

## Démontrer la mise à jour v1 vers v2

Au début de la démonstration, le fichier `deploy.yaml` du dépôt GitOps utilise :

```yaml
image: vloth2602/iot-app:v1
```

1. Remplacer `v1` par `v2` dans ce dépôt GitHub public.
2. Committer et pousser le changement.
3. Observer la synchronisation :

```bash
kubectl annotate application iot-app -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
kubectl get application iot-app -n argocd -w
```

4. Vérifier la nouvelle version :

```bash
curl http://localhost:8888/
```

La page passe d'un thème bleu `v1` à un thème violet `v2`, avec un titre et un
message différents. Pour refaire la démonstration, remettre ensuite le tag `v1`
dans `deploy.yaml` et pousser un nouveau commit.

## Reconstruire les images

Cette étape n'est nécessaire que lorsque le code dans `app/` change :

```bash
docker login
cd /vagrant/p3
./scripts/build-images.sh
```

Le script construit la même application avec deux contenus visuellement
différents, puis publie les tags `v1` et `v2` sur Docker Hub.
