"""O protocolo de cliente na mao: POST /v1/statement e polling de nextUri.

Mostra por que o cliente PRECISA continuar buscando, e como cancelar.

Executar:  docker compose exec cliente python 02_protocolo_http.py
"""
import time
import requests

BASE = "http://trino:8080"
HEADERS = {
    "X-Trino-User": "aula10",
    "X-Trino-Catalog": "tpch",
    "X-Trino-Schema": "tiny",
    "X-Trino-Source": "lab-protocolo",
}

SQL = "SELECT nationkey, name FROM nation ORDER BY nationkey"

# 1. POST inicial: a resposta ja chega ANTES de a query terminar
resp = requests.post(f"{BASE}/v1/statement", data=SQL, headers=HEADERS).json()
print("id:", resp["id"], "| estado inicial:", resp["stats"]["state"])

linhas = []
paginas = 0

# 2. Polling: seguir nextUri ate ele desaparecer
while "nextUri" in resp:
    paginas += 1
    resp = requests.get(resp["nextUri"], headers=HEADERS).json()
    linhas.extend(resp.get("data") or [])
    time.sleep(0.05)

print(f"paginas percorridas: {paginas}")
print(f"linhas recebidas: {len(linhas)}")
print("estado final:", resp["stats"]["state"])
print("primeiras linhas:", linhas[:3])

# 3. Cancelamento: DELETE no nextUri
resp2 = requests.post(
    f"{BASE}/v1/statement",
    data="SELECT count(*) FROM tpch.sf1.lineitem",
    headers=HEADERS,
).json()
if "nextUri" in resp2:
    requests.delete(resp2["nextUri"], headers=HEADERS)
    print("query", resp2["id"], "cancelada por DELETE")
