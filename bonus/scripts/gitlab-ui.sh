#!/usr/bin/env bash

# Garde un tunnel ouvert entre la VM iot-host et le Service GitLab.
set -Eeuo pipefail

password=$(kubectl get secret gitlab-root-password --namespace gitlab \
  -o jsonpath='{.data.root_password}' | base64 --decode)

printf '%s\n' \
  'GitLab : http://localhost:8929' \
  'Utilisateur : root' \
  "Mot de passe : $password" \
  '' \
  'Gardez ce terminal ouvert.'

kubectl port-forward --address 0.0.0.0 \
  service/gitlab --namespace gitlab 8929:80
