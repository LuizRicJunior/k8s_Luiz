#!/usr/bin/env bash
# bootstrap.sh — reconstrói o cluster kind do zero e instala toda a stack
#
# Uso:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# Pré-requisitos no Mac:
#   brew install kind kubectl helm
#   Docker Desktop rodando
#
set -euo pipefail

CLUSTER_NAME="pnp-hml"
REPO_URL="https://github.com/LuizRicJunior/k8s_Luiz.git"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Bootstrap — K8s PnP HML               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 0. destrói cluster anterior se existir ──────────────────────────────────
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "→ Deletando cluster anterior..."
  kind delete cluster --name "${CLUSTER_NAME}"
fi

# ── 1. cria o cluster com port mappings para ingress ────────────────────────
echo "→ Criando cluster kind com port mappings..."
kind create cluster --name "${CLUSTER_NAME}" --config kind/cluster.yaml
echo "✓ Cluster criado"

# ── 2. build e load da imagem da app ────────────────────────────────────────
echo "→ Build da pnp-api..."
docker build -t pnp-api:latest apps/pnp-api/
kind load docker-image pnp-api:latest --name "${CLUSTER_NAME}"
echo "✓ Imagem carregada no cluster"

# ── 3. ingress-nginx (precisa estar antes do ArgoCD para as portas funcionarem)
echo "→ Instalando ingress-nginx..."
kubectl apply -f manifests/ingress/ingress-nginx.yaml --server-side
echo "→ Aguardando ingress-nginx ficar Ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
echo "✓ ingress-nginx pronto"

# ── 4. ArgoCD ────────────────────────────────────────────────────────────────
echo "→ Instalando ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f argocd/install.yaml --server-side --force-conflicts
echo "→ Aguardando ArgoCD ficar Ready (pode demorar 2-3 min)..."
kubectl wait --namespace argocd \
  --for=condition=available deployment/argocd-server \
  --timeout=180s
echo "✓ ArgoCD pronto"

# ── 5. VPA via Helm ──────────────────────────────────────────────────────────
echo "→ Instalando VPA..."
helm repo add cowboysysop https://cowboysysop.github.io/charts/ --force-update
helm upgrade --install vpa cowboysysop/vertical-pod-autoscaler \
  --namespace kube-system \
  --set recommender.enabled=true \
  --set updater.enabled=false \
  --set admissionController.enabled=false \
  --wait
echo "✓ VPA pronto"

# ── 6. Goldilocks via Helm ───────────────────────────────────────────────────
echo "→ Instalando Goldilocks..."
helm repo add fairwinds-stable https://charts.fairwinds.com/stable --force-update
helm upgrade --install goldilocks fairwinds-stable/goldilocks \
  --namespace goldilocks \
  --create-namespace \
  --wait
echo "✓ Goldilocks pronto"

# ── 7. aplica os manifests base (namespace, app, ingress, vpa) ───────────────
echo "→ Aplicando manifests base..."
kubectl apply -f manifests/pnp-api/namespace.yaml
kubectl apply -f manifests/vpa/goldilocks-namespace.yaml   # namespace com label goldilocks
kubectl apply -f manifests/pnp-api/metrics-server.yaml --server-side
kubectl apply -f manifests/vpa/vpa-crds.yaml --server-side 2>/dev/null || true
kubectl apply -f manifests/pnp-api/deployment.yaml
kubectl apply -f manifests/pnp-api/service.yaml
kubectl apply -f manifests/pnp-api/hpa.yaml
kubectl apply -f manifests/ingress/ingress-pnp-api.yaml
kubectl apply -f manifests/vpa/vpa-pnp-api.yaml
echo "✓ Manifests aplicados"

# ── 8. ArgoCD Application (conecta o repo) ───────────────────────────────────
echo "→ Registrando Application no ArgoCD..."
kubectl apply -f argocd/app-pnp-api.yaml
echo "✓ ArgoCD sincronizando com o repo"

# ── 9. resumo ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Stack no ar! Próximos passos:          ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "1. Adicione ao /etc/hosts:"
echo "   sudo sh -c 'echo \"127.0.0.1  pnp.local\" >> /etc/hosts'"
echo ""
echo "2. Acesse a app:"
echo "   http://pnp.local"
echo "   http://pnp.local/stress?seconds=30"
echo "   http://pnp.local/metrics"
echo ""
echo "3. ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server 8090:443 -n argocd"
echo "   https://localhost:8090  (admin / senha abaixo)"
echo "   kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "4. Goldilocks UI:"
echo "   kubectl -n goldilocks port-forward svc/goldilocks-dashboard 8080:80"
echo "   http://localhost:8080"
echo ""