"""Cliente Python oficial (fala o protocolo HTTP por baixo).

Executar:  docker compose exec cliente python 01_cliente_python.py
"""
import trino

conn = trino.dbapi.connect(
    host="trino",
    port=8080,
    user="aula10",
    catalog="tpch",
    schema="tiny",
    # Identificacao: aparece em system.runtime.queries e nos resource groups
    source="lab-aula10",
    client_tags=["turma-trino", "lab10"],
    # Propriedades de sessao ja na conexao
    session_properties={"query_max_run_time": "10m"},
)

cur = conn.cursor()

# 1. Query simples
cur.execute("SELECT nationkey, name FROM nation ORDER BY nationkey LIMIT 5")
for linha in cur.fetchall():
    print(linha)

# 2. Query PARAMETRIZADA (nunca concatene texto)
cur.execute(
    "SELECT name FROM nation WHERE regionkey = ? AND nationkey < ?",
    params=(1, 10),
)
print("parametrizada:", cur.fetchall())

# 3. Metadados da execucao
print("query id:", cur.stats.get("queryId"))
print("estado:", cur.stats.get("state"))

conn.close()
