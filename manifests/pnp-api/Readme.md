# Bloco 1 — Kubernetes core

## Estrutura

```
apps/pnp-api/        → código da aplicação Python
manifests/pnp-api/   → objetos Kubernetes
```

## Fluxo completo

### 1. Build da imagem
```bash
docker build -t pnp-api:latest apps/pnp-api/
```

### 2. Carregar a imagem no kind
# O kind roda em containers Docker isolados — ele não enxerga as imagens
# do seu Docker Desktop. Esse comando "empurra" a imagem para dentro do cluster.
```bash
kind load docker-image pnp-api:latest --name pnp-hml
```

### 3. Aplicar os manifests (ordem importa)
```bash
kubectl apply -f manifests/pnp-api/namespace.yaml
kubectl apply -f manifests/pnp-api/deployment.yaml
kubectl apply -f manifests/pnp-api/service.yaml
```

### 4. Verificar o estado
```bash
# Pods rodando?
kubectl get pods -n pnp

# Deployment saudável?
kubectl get deployment pnp-api -n pnp

# Ver logs de um Pod
kubectl logs -n pnp -l app=pnp-api --follow
```

### 5. Acessar a app (port-forward)
```bash
kubectl port-forward svc/pnp-api 8080:80 -n pnp
# Agora acesse: http://localhost:8080
# Stress test:  http://localhost:8080/stress?seconds=30
# Métricas:     http://localhost:8080/metrics
```

### 6. Testar o label selector na prática
# Mate um Pod na mão e observe o ReplicaSet subir outro:
```bash
kubectl delete pod <nome-do-pod> -n pnp
kubectl get pods -n pnp -w   # -w = watch, fica observando
```

### 7. Testar rollout
# Edite algo no deployment.yaml (ex: replicas: 3) e reaplique:
```bash
kubectl apply -f manifests/pnp-api/deployment.yaml
kubectl rollout status deployment/pnp-api -n pnp

# Ver histórico de rollouts
kubectl rollout history deployment/pnp-api -n pnp

# Desfazer o último rollout
kubectl rollout undo deployment/pnp-api -n pnp
```

## O que observar em cada passo

| Comando | O que você está vendo |
|---|---|
| `kubectl get pods` | Estado atual das réplicas |
| `kubectl describe pod <nome>` | Eventos, probes, recursos alocados |
| `kubectl get replicaset -n pnp` | O RS criado pelo Deployment |
| `kubectl get endpoints -n pnp` | IPs dos Pods registrados no Service |