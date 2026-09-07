#!/usr/bin/env bash
set -e

CLUSTER_NAME="iot-cluster"

k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true

k3d cluster create "$CLUSTER_NAME" --port "8888:8888@loadbalancer" --port "8080:80@loadbalancer"

kubectl create namespace argocd
kubectl create namespace dev

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

kubectl apply -f manifests/application.yaml

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vloth2602/iot-app-ingress
  namespace: dev
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: vloth2602/iot-app-service
            port:
              number: 8888
EOF

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
