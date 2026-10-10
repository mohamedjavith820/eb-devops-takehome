#!/usr/bin/env bash
set -euo pipefail

CLUSTER=demo
NS=demo
IMAGE=demo-svc
TAG=1.0.0
# Pinned ingress-nginx kind manifest. Verify this tag exists before submitting.
INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml"

cd "$(dirname "$0")"

echo "==> kind cluster"
if kind get clusters | grep -qx "$CLUSTER"; then
  echo "cluster '$CLUSTER' already exists, reusing"
else
  cat <<KINDCFG | kind create cluster --name "$CLUSTER" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
KINDCFG
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> ingress-nginx"
kubectl apply -f "$INGRESS_MANIFEST"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo "==> build + load image"
docker build -t "$IMAGE:$TAG" service/
kind load docker-image "$IMAGE:$TAG" --name "$CLUSTER"

echo "==> helm install"
helm upgrade --install demo chart \
  --namespace "$NS" --create-namespace \
  --set image.repository="$IMAGE" --set image.tag="$TAG" \
  --wait --timeout 120s

echo "==> done. Verify:"
echo "  kubectl -n $NS get pods,svc,ingress"
echo "  curl -s -H 'Host: demo.local' http://localhost/"
echo "  curl -s -H 'Host: demo.local' http://localhost/healthz"
