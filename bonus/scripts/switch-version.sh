#!/usr/bin/env bash

# Crée un commit dans GitLab pour passer simplement l'application en v1 ou v2.
set -Eeuo pipefail

if [[ $# -ne 1 || ( "$1" != "v1" && "$1" != "v2" ) ]]; then
  printf 'Utilisation : %s v1|v2\n' "$0" >&2
  exit 1
fi

version=$1
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BONUS_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
GITLAB_DEPLOYMENT="deployment/gitlab"
GITLAB_API="http://127.0.0.1/api/v4"

token=$(kubectl get secret gitlab-automation --namespace gitlab \
  -o jsonpath='{.data.token}' | base64 --decode)

current_version=$(kubectl exec --namespace gitlab "$GITLAB_DEPLOYMENT" -- \
  curl -fsS \
  --header "Host: localhost:8929" \
  --header "PRIVATE-TOKEN: $token" \
  "$GITLAB_API/projects/root%2Fiot-app/repository/files/app%2Eyaml/raw?ref=main" \
  | sed -n 's/.*image: vloth2602\/iot-app:\(v[12]\).*/\1/p' | head -n 1)

if [[ "$current_version" == "$version" ]]; then
  printf 'GitLab contient déjà la version %s.\n' "$version"
  exit 0
fi

repository_content=$(sed -E \
  "s#image: vloth2602/iot-app:v[12]#image: vloth2602/iot-app:$version#" \
  "$BONUS_DIR/repository/app.yaml" | base64 -w 0)

kubectl exec --namespace gitlab "$GITLAB_DEPLOYMENT" -- \
  curl -fsS --request PUT \
  --header "Host: localhost:8929" \
  --header "PRIVATE-TOKEN: $token" \
  --data-urlencode "branch=main" \
  --data-urlencode "commit_message=Passe l'application en $version" \
  --data-urlencode "content=$repository_content" \
  --data-urlencode "encoding=base64" \
  "$GITLAB_API/projects/root%2Fiot-app/repository/files/app%2Eyaml" \
  >/dev/null

kubectl annotate application iot-app --namespace argocd \
  argocd.argoproj.io/refresh=hard --overwrite

printf 'Commit GitLab créé. Attente du déploiement de %s...\n' "$version"
for _ in $(seq 1 60); do
  deployed_image=$(kubectl get deployment iot-app --namespace dev \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
  if [[ "$deployed_image" == "vloth2602/iot-app:$version" ]]; then
    kubectl rollout status deployment/iot-app --namespace dev --timeout=5m
    printf 'Version %s déployée : http://localhost:8888\n' "$version"
    exit 0
  fi
  sleep 5
done

printf 'Erreur : Argo CD n\x27a pas déployé %s dans le délai prévu.\n' \
  "$version" >&2
exit 1
