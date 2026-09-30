-- Aula 5 — SELECT em profundidade
-- docker compose exec -it trino trino --catalog tpch --schema tiny

-- ===============================================================
-- 1. Ordem lógica de execução
-- ===============================================================

-- Alias do SELECT NÃO existe no WHERE: esta query DEVE falhar
-- SELECT totalprice * 0.1 AS imposto FROM orders WHERE imposto > 100;

-- Formas corretas
SELECT totalprice * 0.1 AS imposto
FROM orders
WHERE totalprice * 0.1 > 10000;

SELECT imposto FROM (
    SELECT totalprice * 0.1 AS imposto FROM orders
) WHERE imposto > 10000;

-- Agregado no WHERE não existe: DEVE falhar
-- SELECT custkey FROM orders WHERE count(*) > 5 GROUP BY custkey;

SELECT custkey, count(*) AS pedidos
FROM orders
GROUP BY custkey
HAVING count(*) > 20
ORDER BY pedidos DESC
LIMIT 5;

-- ===============================================================
-- 2. WITH: CTE, WITH SESSION, WITH RECURSIVE
-- ===============================================================

WITH pedidos_grandes AS (
    SELECT orderkey, custkey, totalprice
    FROM orders
    WHERE totalprice > 300000
)
SELECT count(*) AS qtd, round(avg(totalprice), 2) AS ticket_medio
FROM pedidos_grandes;

-- WITH SESSION: propriedade válida SÓ nesta query
WITH SESSION query_max_run_time = '10m'
SELECT count(*) FROM lineitem;

-- Recursão: sequência 1..5 (default de profundidade é 10)
WITH RECURSIVE serie(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM serie WHERE n < 5
)
SELECT * FROM serie;

-- ===============================================================
-- 3. SELECT: DISTINCT, alias, row.*
-- ===============================================================

SELECT DISTINCT nationkey FROM customer ORDER BY nationkey LIMIT 5;

-- Expandindo os campos de um ROW em colunas.
-- ATENCAO: precisa QUALIFICAR com o alias da relacao (t.r.*).
-- "SELECT r.*" falha com: Unable to resolve reference r
SELECT t.r.*
FROM (SELECT CAST(ROW(1, 'exemplo') AS ROW(id INTEGER, nome VARCHAR)) AS r) t;

-- Forma alternativa, sem subquery
SELECT (CAST(ROW(1, 'exemplo') AS ROW(id INTEGER, nome VARCHAR))).*;

-- ===============================================================
-- 4. FROM: joins, UNNEST, LATERAL, TABLESAMPLE
-- ===============================================================

-- Todos os tipos de join, lado a lado
SELECT count(*) AS inner_join
FROM customer c JOIN orders o ON o.custkey = c.custkey;

SELECT count(*) AS left_join
FROM customer c LEFT JOIN orders o ON o.custkey = c.custkey;

SELECT count(*) AS full_join
FROM customer c FULL JOIN orders o ON o.custkey = c.custkey;

-- Clientes sem nenhum pedido (padrão anti-join)
SELECT count(*) AS clientes_sem_pedido
FROM customer c
LEFT JOIN orders o ON o.custkey = c.custkey
WHERE o.orderkey IS NULL;

-- UNNEST: array vira linhas
SELECT id, tag
FROM (VALUES (1, ARRAY['a','b','c']), (2, ARRAY['x','y'])) AS t(id, tags)
CROSS JOIN UNNEST(tags) AS u(tag);

-- UNNEST com ordinalidade
SELECT id, tag, pos
FROM (VALUES (1, ARRAY['a','b','c'])) AS t(id, tags)
CROSS JOIN UNNEST(tags) WITH ORDINALITY AS u(tag, pos);

-- UNNEST de MAP
SELECT chave, valor
FROM (VALUES (MAP(ARRAY['a','b'], ARRAY[1,2]))) AS t(m)
CROSS JOIN UNNEST(m) AS u(chave, valor);

-- LATERAL: a subquery enxerga a linha corrente do lado esquerdo
SELECT c.name, ultimo.orderdate, ultimo.totalprice
FROM customer c
CROSS JOIN LATERAL (
    SELECT o.orderdate, o.totalprice
    FROM orders o
    WHERE o.custkey = c.custkey
    ORDER BY o.orderdate DESC
    LIMIT 1
) AS ultimo
LIMIT 10;

-- TABLESAMPLE: BERNOULLI (linha a linha) x SYSTEM (por bloco)
SELECT count(*) AS amostra_bernoulli FROM orders TABLESAMPLE BERNOULLI (10);
SELECT count(*) AS amostra_system    FROM orders TABLESAMPLE SYSTEM (10);
SELECT count(*) AS total             FROM orders;

-- ===============================================================
-- 5. WHERE e a semântica de NULL
-- ===============================================================

SELECT
    NULL = NULL                      AS igualdade_com_null,      -- NULL
    NULL IS NOT DISTINCT FROM NULL   AS null_safe,               -- true
    1 IS DISTINCT FROM NULL          AS distinto_de_null;        -- true

-- O filtro que descarta linhas em silêncio
WITH dados(id, valor) AS (VALUES (1, 10), (2, NULL), (3, 30))
SELECT * FROM dados WHERE valor <> 10;          -- devolve só id=3

WITH dados(id, valor) AS (VALUES (1, 10), (2, NULL), (3, 30))
SELECT * FROM dados WHERE valor IS DISTINCT FROM 10;  -- devolve id=2 e id=3

-- Quantificadores
SELECT 5 < ALL (VALUES 6, 7, 8) AS menor_que_todos,
       5 = ANY (VALUES 4, 5, 6) AS igual_a_algum;

-- ===============================================================
-- 6. GROUP BY: ordinal, ROLLUP, CUBE, GROUPING SETS, grouping()
-- ===============================================================

-- Agrupamento por posição ordinal
SELECT orderstatus, orderpriority, count(*)
FROM orders
GROUP BY 1, 2
ORDER BY 1, 2;

-- ROLLUP: subtotais hierárquicos + total geral, em UMA varredura
SELECT
    orderstatus,
    orderpriority,
    count(*) AS pedidos
FROM orders
GROUP BY ROLLUP (orderstatus, orderpriority)
ORDER BY orderstatus, orderpriority;

-- CUBE: todas as combinações
SELECT orderstatus, orderpriority, count(*) AS pedidos
FROM orders
GROUP BY CUBE (orderstatus, orderpriority)
ORDER BY orderstatus, orderpriority;

-- GROUPING SETS: exatamente os agrupamentos que você quer
SELECT orderstatus, orderpriority, count(*) AS pedidos
FROM orders
GROUP BY GROUPING SETS ((orderstatus, orderpriority), (orderstatus), ())
ORDER BY orderstatus, orderpriority;

-- grouping(): distingue "NULL de verdade" de "coluna fora do agrupamento"
SELECT
    orderstatus,
    orderpriority,
    grouping(orderstatus, orderpriority) AS mascara,
    count(*) AS pedidos
FROM orders
GROUP BY ROLLUP (orderstatus, orderpriority)
ORDER BY mascara, orderstatus, orderpriority;

-- ===============================================================
-- 7. WINDOW nomeada
-- ===============================================================

SELECT
    orderkey,
    quantity,
    sum(quantity) OVER w AS total_do_pedido,
    rank()        OVER w AS posicao
FROM lineitem
WHERE orderkey < 100
WINDOW w AS (PARTITION BY orderkey ORDER BY quantity DESC)
ORDER BY orderkey, posicao;

-- ===============================================================
-- 8. Operações de conjunto
-- ===============================================================

-- DISTINCT é o default: 1 linha
SELECT 1 UNION SELECT 1;

-- ALL mantém duplicata: 2 linhas
SELECT 1 UNION ALL SELECT 1;

-- Casamento POSICIONAL: repare que as colunas se misturam
SELECT 1 AS a, 'x' AS b
UNION ALL
SELECT 2 AS a, 'y' AS b;

-- INTERSECT e EXCEPT
SELECT nationkey FROM customer
INTERSECT
SELECT nationkey FROM supplier;

SELECT nationkey FROM nation
EXCEPT
SELECT nationkey FROM customer;

-- ===============================================================
-- 9. ORDER BY, OFFSET, LIMIT, FETCH WITH TIES
-- ===============================================================

SELECT name, acctbal
FROM customer
ORDER BY acctbal DESC NULLS LAST
LIMIT 5;

-- Paginação com OFFSET (didática, não escalável)
SELECT custkey, name
FROM customer
ORDER BY custkey
OFFSET 10 ROWS
LIMIT 5;

-- FETCH ... WITH TIES traz os empatados na última posição.
-- Em tpch.tiny.lineitem isso devolve 1192 linhas, nao 5.
SELECT orderkey, quantity
FROM lineitem
ORDER BY quantity DESC
FETCH FIRST 5 ROWS WITH TIES;

-- ===============================================================
-- 10. Subqueries
-- ===============================================================

-- EXISTS
SELECT count(*) AS clientes_com_pedido
FROM customer c
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.custkey = c.custkey);

-- IN
SELECT count(*) AS pedidos_do_brasil
FROM orders o
WHERE o.custkey IN (
    SELECT c.custkey FROM customer c
    JOIN nation n ON n.nationkey = c.nationkey
    WHERE n.name = 'BRAZIL'
);

-- Subquery escalar: zero linhas devolve NULL
SELECT (SELECT max(totalprice) FROM orders)                     AS maior_pedido,
       (SELECT totalprice FROM orders WHERE orderkey = -1)      AS inexistente;
