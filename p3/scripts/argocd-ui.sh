#!/usr/bin/env bash

# Ouvre localement l'interface Web d'Argo CD. Gardez ce terminal ouvert, puis
# visitez https://localhost:8080 (l'avertissement TLS est normal en local).
set -Eeuo pipefail

printf '%s\n' \
  'Interface Argo CD : https://localhost:8080' \
  'Utilisateur : admin' \
  'Mot de passe :'
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
printf '\n'

kubectl port-forward --address 0.0.0.0 \
  service/argocd-server -n argocd 8080:443
