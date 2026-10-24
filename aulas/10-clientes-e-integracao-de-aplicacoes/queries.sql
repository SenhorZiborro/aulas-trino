-- Aula 10 — clientes e integração
-- docker compose exec -it trino trino
--
-- Este arquivo é o "lado servidor" do lab: enquanto os scripts em cliente/
-- rodam, use estas queries para OBSERVAR o que chega ao cluster.

-- ===============================================================
-- 1. Quem está conectado e de onde
-- ===============================================================

-- ATENCAO: system.runtime.queries NAO tem coluna client_tags. As colunas sao:
--   query_id, state, user, source, query, resource_group_id,
--   queued_time_ms, analysis_time_ms, planning_time_ms,
--   created, started, last_heartbeat, end, error_type, error_code
DESCRIBE system.runtime.queries;

-- "source" e o campo que identifica a aplicacao. Sem ele, tudo vira nulo.
SELECT
    query_id,
    state,
    "user",
    source,
    resource_group_id,
    created,
    substr(query, 1, 60) AS inicio
FROM system.runtime.queries
ORDER BY created DESC
LIMIT 20;

-- Consumo por aplicação: só é possível porque o cliente se identifica
SELECT
    coalesce(source, '(desconhecido)') AS aplicacao,
    count(*)                            AS queries,
    count(*) FILTER (WHERE state = 'FAILED') AS falhas
FROM system.runtime.queries
GROUP BY 1
ORDER BY queries DESC;

-- E as client_tags? Elas NAO aparecem aqui. Servem para ROTEAR em resource
-- groups (aula A10) -- o efeito delas se observa em resource_group_id:
SELECT
    coalesce(source, '(nulo)')            AS aplicacao,
    resource_group_id,
    count(*)                              AS queries
FROM system.runtime.queries
GROUP BY 1, 2
ORDER BY queries DESC;

-- ===============================================================
-- 2. O schema que todo cliente JDBC precisa enxergar
-- ===============================================================

-- O schema system.jdbc expoe os metadados no formato que drivers JDBC
-- esperam -- util para entender o que uma ferramenta de BI consulta.
SHOW TABLES FROM system.jdbc;

-- É daqui que DBeaver, Power BI e afins leem a árvore de objetos
SELECT * FROM system.jdbc.catalogs;
SELECT * FROM system.jdbc.schemas WHERE table_catalog = 'tpch' LIMIT 10;
SELECT table_cat, table_schem, table_name, table_type
FROM system.jdbc.tables
WHERE table_cat = 'tpch' AND table_schem = 'tiny';
-- E por aqui que toda ferramenta JDBC descobre catalogos, schemas e colunas.
-- Bloquear system.jdbc no controle de acesso quebra o DBeaver, o Tableau e
-- qualquer cliente que liste objetos antes de consultar.

-- ===============================================================
-- 3. Queries órfãs: o efeito do timeout do cliente
-- ===============================================================

-- Em outro terminal, dispare uma consulta longa com timeout curto no cliente:
--   docker compose exec -T trino trino --client-request-timeout=5s \
--     --execute 'SELECT count(*) FROM tpch.sf10.lineitem'
-- O CLI desiste em 5s; a consulta abaixo mostra que ela CONTINUA rodando no
-- servidor. Desistir do cliente nao cancela a query.
SELECT query_id, state, "user", source, substr(query, 1, 50) AS inicio
FROM system.runtime.queries
WHERE state = 'RUNNING';
-- Para encerrar de fato e preciso matar pelo id (troque pelo que apareceu
-- acima). Fica comentado porque o id muda a cada execucao:
--   CALL system.runtime.kill_query(
--       query_id => '20260905_120000_00001_abcde',
--       message  => 'abandonada pelo cliente');

-- ===============================================================
-- 4. Propriedades de sessão vindas do cliente
-- ===============================================================

-- O script Python define query_max_run_time na conexão; confira o efeito
SHOW SESSION LIKE 'query_max_run_time';

-- ===============================================================
-- 5. Simulando o anti-padrão: muitas queries pequenas
-- ===============================================================
-- Rode no shell:
--   for i in $(seq 1 50); do
--     docker compose exec -T trino trino --execute 'SELECT 1' >/dev/null;
--   done
-- Depois observe o custo fixo por query:

SELECT
    count(*)                                   AS queries,
    count(*) FILTER (WHERE state = 'FINISHED') AS concluidas
FROM system.runtime.queries
WHERE source = 'trino-cli';
