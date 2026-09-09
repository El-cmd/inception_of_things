#!/usr/bin/env bash

# Installe le bonus à partir de la P3, puis remplace GitHub par GitLab local.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BONUS_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
PROJECT_DIR=$(cd -- "$BONUS_DIR/.." && pwd)
GITLAB_DEPLOYMENT="deployment/gitlab"
GITLAB_API="http://127.0.0.1/api/v4"

log() {
  printf '\n[bonus] %s\n' "$1"
}

for command_name in kubectl openssl base64; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Erreur : %s est nécessaire. Lancez ce script dans iot-host.\n' \
      "$command_name" >&2
    exit 1
  fi
done

log "Création de la P3 et du cluster K3d"
"$PROJECT_DIR/p3/scripts/setup.sh"

log "Création du namespace et du mot de passe GitLab"
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -
root_password=$(openssl rand -hex 16)
kubectl create secret generic gitlab-root-password \
  --namespace gitlab \
  --from-literal="root_password=$root_password" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Installation de GitLab CE (cette étape peut prendre 10 à 20 minutes)"
kubectl apply -f "$BONUS_DIR/confs/gitlab.yaml"
kubectl rollout status "$GITLAB_DEPLOYMENT" \
  --namespace gitlab --timeout=20m

log "Création du jeton d'automatisation"
automation_token="glpat-$(openssl rand -hex 16)"
rails_command="user = User.find_by_username('root'); user.personal_access_tokens.where(name: 'iot-bonus').delete_all; token = user.personal_access_tokens.create!(scopes: ['api'], name: 'iot-bonus', expires_at: 30.days.from_now); token.set_token('$automation_token'); token.save!"
kubectl exec --namespace gitlab "$GITLAB_DEPLOYMENT" -- \
  gitlab-rails runner "$rails_command"

kubectl create secret generic gitlab-automation \
  --namespace gitlab \
  --from-literal="token=$automation_token" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Création du projet GitLab root/iot-app"
kubectl exec --namespace gitlab "$GITLAB_DEPLOYMENT" -- \
  curl -fsS --request POST \
  --header "Host: localhost:8929" \
  --header "PRIVATE-TOKEN: $automation_token" \
  --data-urlencode "name=iot-app" \
  --data-urlencode "path=iot-app" \
  --data-urlencode "visibility=public" \
  --data-urlencode "initialize_with_readme=true" \
  --data-urlencode "default_branch=main" \
  "$GITLAB_API/projects" >/dev/null

log "Ajout du manifest v1 dans GitLab"
repository_content=$(base64 -w 0 "$BONUS_DIR/repository/app.yaml")
kubectl exec --namespace gitlab "$GITLAB_DEPLOYMENT" -- \
  curl -fsS --request POST \
  --header "Host: localhost:8929" \
  --header "PRIVATE-TOKEN: $automation_token" \
  --data-urlencode "branch=main" \
  --data-urlencode "commit_message=Déploie la version v1" \
  --data-urlencode "content=$repository_content" \
  --data-urlencode "encoding=base64" \
  "$GITLAB_API/projects/root%2Fiot-app/repository/files/app%2Eyaml" \
  >/dev/null

log "Connexion d'Argo CD au GitLab local"
kubectl apply -f "$BONUS_DIR/confs/application.yaml"
kubectl annotate application iot-app --namespace argocd \
  argocd.argoproj.io/refresh=hard --overwrite

log "Attente du déploiement de l'application"
for _ in $(seq 1 60); do
  image=$(kubectl get deployment iot-app --namespace dev \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
  if [[ "$image" == "vloth2602/iot-app:v1" ]]; then
    break
  fi
  sleep 5
done

image=$(kubectl get deployment iot-app --namespace dev \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
if [[ "$image" != "vloth2602/iot-app:v1" ]]; then
  printf 'Erreur : Argo CD n\x27a pas déployé la version v1.\n' >&2
  kubectl get application iot-app --namespace argocd || true
  exit 1
fi
kubectl rollout status deployment/iot-app --namespace dev --timeout=5m

log "Bonus prêt"
printf '%s\n' \
  "GitLab     : http://localhost:8929" \
  "Utilisateur: root" \
  "Mot de passe: $root_password" \
  "Application: http://localhost:8888" \
  '' \
  'Ouvrez GitLab avec : ./scripts/gitlab-ui.sh' \
  'Passez en v2 avec : ./scripts/switch-version.sh v2'
