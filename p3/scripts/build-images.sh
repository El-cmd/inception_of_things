#!/usr/bin/env bash

# Construit et publie les deux versions demandées par le sujet.
# Exécuter d'abord `docker login` avec le compte vloth2602.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd -- "$SCRIPT_DIR/../app" && pwd)
IMAGE_NAME="vloth2602/iot-app"

command -v docker >/dev/null 2>&1 || {
  printf 'Docker est nécessaire.\n' >&2
  exit 1
}

for version in v1 v2; do
  printf '\n[images] Construction de %s:%s\n' "$IMAGE_NAME" "$version"
  docker build \
    --build-arg "APP_VERSION=$version" \
    --tag "$IMAGE_NAME:$version" \
    "$APP_DIR"
  docker push "$IMAGE_NAME:$version"
done

printf '\n[images] Images v1 et v2 publiées.\n'
