#!/bin/sh
# Gerador de carga. Sem ele o dashboard e uma linha reta e a aula nao mostra
# nada. Roda em loop, com usuario e `source` diferentes por query -- e o
# `source` que permite atribuir consumo por time depois.
#
# A ULTIMA query do loop e invalida de proposito: e o que alimenta o painel de
# falhas e mostra a turma que ela cai em USER_ERROR, o balde que nao e
# incidente. Os passos da aula sao todos de caminho feliz.

SERVIDOR=http://trino:8080

echo "aguardando o cluster responder..."
until trino --server $SERVIDOR --user carga --execute 'SELECT 1' >/dev/null 2>&1; do
  sleep 5
done

echo "aguardando os dois workers entrarem..."
i=0
while [ $i -lt 60 ]; do
  N=$(trino --server $SERVIDOR --user carga --output-format=CSV_UNQUOTED \
        --execute "SELECT count(*) FROM system.runtime.nodes WHERE coordinator = false" 2>/dev/null)
  [ "$N" = "2" ] && break
  i=$((i + 1))
  sleep 5
done

echo "gerando carga"
while true; do
  trino --server $SERVIDOR --user bi --source dashboard \
    --execute 'SELECT count(*) FROM tpch.tiny.orders' >/dev/null 2>&1

  trino --server $SERVIDOR --user bi --source dashboard \
    --execute 'SELECT orderstatus, count(*) FROM tpch.sf1.orders GROUP BY orderstatus' >/dev/null 2>&1

  trino --server $SERVIDOR --user analista --source notebook \
    --execute 'SELECT c.mktsegment, count(*) AS pedidos, sum(o.totalprice) AS valor
               FROM tpch.sf1.orders o JOIN tpch.sf1.customer c ON c.custkey = o.custkey
               GROUP BY c.mktsegment' >/dev/null 2>&1

  trino --server $SERVIDOR --user analista --source notebook \
    --execute 'SELECT * FROM tpch.sf1.tabela_que_nao_existe' >/dev/null 2>&1

  sleep 5
done
