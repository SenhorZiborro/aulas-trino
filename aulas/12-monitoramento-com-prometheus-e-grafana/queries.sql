-- Aula 12 — monitoramento com Prometheus e Grafana
-- docker compose exec -it trino trino

-- ===============================================================
-- 1. O cluster tem três nós, e isso muda o que se monitora
-- ===============================================================

-- Um coordinator e dois workers. Toda metrica de nó, daqui para a frente,
-- aparece tres vezes -- uma por processo.
SELECT node_id, coordinator, state, node_version
FROM system.runtime.nodes
ORDER BY coordinator DESC, node_id;

-- O trabalho acontece nos WORKERS: o coordinator subiu com
-- node-scheduler.include-coordinator=false, entao ele planeja e coordena, mas
-- nao recebe split. Esta consulta mostra onde as tasks estao caindo.
SELECT node_id, count(*) AS tasks, sum(splits) AS splits
FROM system.runtime.tasks
GROUP BY node_id
ORDER BY node_id;

-- Quanto cada nó já leu, pelo MBean de tasks de cada um. Diferenca grande
-- entre workers e o primeiro sinal de distribuicao torta (skew).
SELECT node, "inputdatasize.totalcount" AS bytes_lidos,
       "inputpositions.totalcount"      AS linhas_lidas,
       activetaskscount                 AS tasks_ativas
FROM jmx.current."trino.execution:name=sqltaskmanager"
ORDER BY node;

-- ===============================================================
-- 2. O número do dashboard é o número do nó
-- ===============================================================

-- Os contadores de admissao e falha, no coordinator. Sao exatamente as series
-- dos paineis 1 e 3 do dashboard do Grafana.
SELECT runningqueries AS rodando,
       queuedqueries  AS na_fila,
       "completedqueries.totalcount"              AS concluidas,
       "usererrorfailures.totalcount"             AS falha_de_usuario,
       "insufficientresourcesfailures.totalcount" AS falha_de_recurso,
       "internalfailures.totalcount"              AS falha_interna
FROM jmx.current."trino.execution:name=querymanager";

-- A pausa de coletor de lixo em cada um dos tres nos -- a serie do painel de
-- GC, lida direto da fonte.
SELECT node, name AS coletor, collectiontime AS ms_parado
FROM jmx.current."java.lang:*type=garbagecollector*"
WHERE name LIKE 'G1%Generation'
ORDER BY node, coletor;

-- O percentil de FILA existe no MBean, mas nao no /metrics -- e um dos motivos
-- de manter as duas portas abertas em producao.
SELECT round("queuedtime.alltime.p95")    AS fila_p95_ms,
       round("executiontime.alltime.p95") AS execucao_p95_ms
FROM jmx.current."trino.execution:name=querymanager";

-- ===============================================================
-- 3. O caminho inverso: consultar o Prometheus com SQL
-- ===============================================================

-- O catalogo `metrics` aponta para o Prometheus, e cada metrica vira tabela no
-- schema `default`. Sao milhares -- uma por serie coletada.
SELECT count(*) AS metricas
FROM metrics.information_schema.tables
WHERE table_schema = 'default';

-- A metrica `up` e do proprio Prometheus: 1 para cada alvo que respondeu na
-- ultima coleta. E a forma mais direta de responder "o cluster esta inteiro?".
SELECT labels['instance'] AS alvo,
       labels['papel']    AS papel,
       max_by(value, "timestamp") AS no_ar
FROM metrics.default.up
GROUP BY labels['instance'], labels['papel']
ORDER BY papel, alvo;

-- Os apelidos criados pelas regras de gravacao do Prometheus. Sem eles o
-- conector nao alcança as metricas do Trino, porque o Trino normaliza nome de
-- tabela para minusculas e as metricas tem maiusculas no nome.
SELECT labels['papel'] AS papel,
       CAST(round(max(value)) AS bigint) AS heap_pico_bytes,
       CAST(round(avg(value)) AS bigint) AS heap_medio_bytes
FROM metrics.default.trino_heap_usado_bytes
GROUP BY labels['papel']
ORDER BY papel;

-- E a serie temporal, como qualquer tabela: queries concluidas por minuto,
-- calculado em SQL sobre o que o Prometheus guardou.
SELECT date_trunc('minute', "timestamp") AS minuto,
       CAST(round(max(value) - min(value)) AS bigint) AS concluidas_no_minuto
FROM metrics.default.trino_queries_concluidas
GROUP BY date_trunc('minute', "timestamp")
ORDER BY minuto DESC
LIMIT 10;

-- ===============================================================
-- 4. Guardando a série além da retenção do Prometheus
-- ===============================================================

-- Cria o schema do lake: o metastore de arquivo exige que a tabela fique sob
-- hive.metastore.catalog.dir, entao o schema nasce sem location propria.
CREATE SCHEMA IF NOT EXISTS lake.obs;

-- Limpa execucao anterior.
DROP TABLE IF EXISTS lake.obs.consumo_por_papel;

-- Materializa em PARQUET o resumo que acabamos de calcular. E o padrao real
-- para guardar historico de capacidade por meses: o Prometheus mantem dias, o
-- lake mantem o que voce quiser, e a consulta continua sendo SQL. O CAST para
-- TIMESTAMP(3) sem fuso e exigencia do Hive, que nao aceita o tipo com fuso
-- que o conector Prometheus devolve.
CREATE TABLE lake.obs.consumo_por_papel AS
SELECT labels['papel'] AS papel,
       CAST(date_trunc('minute', "timestamp") AS TIMESTAMP(3)) AS minuto,
       CAST(round(max(value)) AS bigint) AS heap_pico_bytes
FROM metrics.default.trino_heap_usado_bytes
GROUP BY labels['papel'], date_trunc('minute', "timestamp");

-- Confere o que foi gravado no MinIO.
SELECT papel, count(*) AS minutos, max(heap_pico_bytes) AS maior_heap
FROM lake.obs.consumo_por_papel
GROUP BY papel
ORDER BY papel;

-- ===============================================================
-- 5. Limpeza
-- ===============================================================

-- Limpeza: derruba a tabela criada na aula.
DROP TABLE IF EXISTS lake.obs.consumo_por_papel;
