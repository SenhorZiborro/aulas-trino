-- Aula 1 — validação da primeira subida
-- Executar com:
--   docker compose exec trino trino --file /dev/stdin < queries.sql
-- ou colar bloco a bloco no CLI interativo:
--   docker compose exec -it trino trino

-- 1. O servidor responde e sabe quem é
SELECT version();

-- 2. Catálogos registrados (deve listar tpch e system)
SHOW CATALOGS;

-- 3. Schemas do catálogo tpch (tiny, sf1, sf100, ...)
SHOW SCHEMAS FROM tpch;

-- 4. Tabelas do schema tiny
SHOW TABLES FROM tpch.tiny;

-- 5. Primeira leitura de dados
SELECT nationkey, name, regionkey
FROM tpch.tiny.nation
ORDER BY nationkey
LIMIT 5;

-- 6. Uma agregação, para o motor realmente executar trabalho
SELECT r.name AS region, count(*) AS nations
FROM tpch.tiny.nation n
JOIN tpch.tiny.region r ON r.regionkey = n.regionkey
GROUP BY r.name
ORDER BY region;

-- 7. Conferindo a identidade e a configuração do nó pelo catálogo system
SELECT node_id, http_uri, node_version, coordinator, state
FROM system.runtime.nodes;

-- 8. As queries que já rodaram nesta sessão do cluster
SELECT query_id, state, substr(query, 1, 60) AS query_inicio
FROM system.runtime.queries
ORDER BY created DESC
LIMIT 10;
