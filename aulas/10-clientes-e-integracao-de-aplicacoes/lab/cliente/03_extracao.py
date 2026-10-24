"""Extracao paginada para CSV, com LIMIT explicito e contagem.

Executar:  docker compose exec cliente python 03_extracao.py
"""
import csv
import trino

conn = trino.dbapi.connect(
    host="trino", port=8080, user="aula10",
    catalog="tpch", schema="sf1",
    source="lab-extracao", client_tags=["extracao"],
)
cur = conn.cursor()

# LIMIT explicito: protege contra extracao acidental de milhoes de linhas
cur.execute("SELECT orderkey, custkey, totalprice, orderdate FROM orders LIMIT 50000")

with open("/app/saida.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow([c[0] for c in cur.description])
    total = 0
    while True:
        lote = cur.fetchmany(5000)
        if not lote:
            break
        w.writerows(lote)
        total += len(lote)
        print(f"gravadas {total} linhas...")

print("arquivo /app/saida.csv escrito com", total, "linhas")
conn.close()
