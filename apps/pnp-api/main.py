import time
import math
import os
from fastapi import FastAPI
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response

app = FastAPI(title="pnp-api")

# --- métricas Prometheus ---
REQUEST_COUNT = Counter(
    "pnp_requests_total",
    "Total de requests recebidos",
    ["endpoint"]
)
STRESS_DURATION = Histogram(
    "pnp_stress_duration_seconds",
    "Duração dos requests de stress"
)

POD_NAME = os.getenv("POD_NAME", "unknown")
POD_NAMESPACE = os.getenv("POD_NAMESPACE", "unknown")


@app.get("/")
def health():
    # Sempre retorna 200 — o K8s usa isso no livenessProbe
    REQUEST_COUNT.labels(endpoint="/").inc()
    return {
        "status": "ok",
        "pod": POD_NAME,
        "namespace": POD_NAMESPACE,
    }


@app.get("/stress")
def stress(seconds: int = 10):
    """
    Consome CPU por N segundos.
    Usado para acionar o HPA (Horizontal Pod Autoscaler).

    Exemplo: GET /stress?seconds=30
    """
    REQUEST_COUNT.labels(endpoint="/stress").inc()

    with STRESS_DURATION.time():
        deadline = time.time() + seconds
        # loop de cálculo — garante 100% de 1 core
        while time.time() < deadline:
            math.factorial(10000)

    return {
        "stressed_for_seconds": seconds,
        "pod": POD_NAME,
    }


@app.get("/metrics")
def metrics():
    """
    Endpoint padrão Prometheus.
    O KEDA e o ServiceMonitor vão raspar aqui.
    """
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )