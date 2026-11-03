-- Aula 13 — Controle de acesso e usuários
-- docker compose exec -e TRINO_PASSWORD=senha-carla -it trino trino \
--   --server https://localhost:8443 --insecure --user carla --password \
--   --catalog vendas --schema publico

-- ===============================================================
-- 1. Quem sou eu, e o que eu enxergo
-- ===============================================================

-- O usuario autorizado da sessao.
SELECT current_user;

-- SHOW CATALOGS e FILTRADO pelas regras: so aparece o que o usuario pode usar.
SHOW CATALOGS;

-- E a lista de tabelas tambem.
SHOW TABLES FROM vendas.publico;

-- ===============================================================
-- 2. A mesma pergunta como a analista
-- ===============================================================

-- SET SESSION AUTHORIZATION troca o usuario da sessao sem reconectar. So
-- funciona porque regras.json autoriza a carla a assumir ana e beto.
SET SESSION AUTHORIZATION 'ana';

-- Agora a sessao responde como ela.
SELECT current_user;

-- O tpch desapareceu: a regra dela cobre vendas e system.
SHOW CATALOGS;

-- E salario desapareceu da lista, sem nenhum erro.
SHOW TABLES FROM vendas.publico;

-- O que a regra dela permite ler.
SELECT segmento, count(*) AS clientes
FROM vendas.publico.cliente
GROUP BY segmento
ORDER BY segmento;

-- ===============================================================
-- 3. E como o auditor, que tem escopo de coluna
-- ===============================================================

-- Troca de novo, sem sair do CLI.
SET SESSION AUTHORIZATION 'beto';

-- A sessao agora e dele.
SELECT current_user;

-- Para ele existe UMA tabela no schema.
SHOW TABLES FROM vendas.publico;

-- E nela, uma coluna a menos: a regra tambem filtra o information_schema.
SELECT count(*) AS colunas_visiveis
FROM vendas.information_schema.columns
WHERE table_name = 'pedido';

-- A leitura dele, so com as colunas liberadas.
SELECT id, cliente_id, status
FROM vendas.publico.pedido
ORDER BY id
LIMIT 5;

-- ===============================================================
-- 4. Voltando a ser admin
-- ===============================================================

-- RESET devolve a sessao ao usuario que autenticou.
RESET SESSION AUTHORIZATION;

-- De volta a carla, com o escopo dela.
SELECT current_user;

-- ===============================================================
-- 5. A segunda camada: quem o Postgres ve conectado
-- ===============================================================

-- Os tres usuarios acima falam com o Postgres pelo MESMO usuario, o
-- connection-user do catalogo -- e ainda assim enxergam coisas diferentes.
-- Prova de que o escopo por pessoa e do Trino, nao da fonte.
SELECT * FROM TABLE(vendas.system.query(query =>
    'SELECT current_user AS usuario_no_postgres'));

-- E o teto do catalogo: os GRANTs desse usuario na fonte.
SELECT * FROM TABLE(vendas.system.query(query =>
    'SELECT table_name, privilege_type FROM information_schema.table_privileges
     WHERE grantee = ''trino_leitura'' ORDER BY table_name, privilege_type'));

-- ===============================================================
-- 6. Auditoria: quem rodou o que
-- ===============================================================

-- A coluna user de system.runtime.queries registra quem pediu cada query --
-- inclusive as que rodaram sob SET SESSION AUTHORIZATION.
SELECT "user", count(*) AS queries
FROM system.runtime.queries
GROUP BY "user"
ORDER BY queries DESC;
