-- Aula 8 — anatomia de um catálogo
-- docker compose exec -it trino trino

-- ===============================================================
-- 1. Ponto de partida: nenhum catálogo de usuário
-- ===============================================================

-- Lista os catalogos visiveis na sessao.
-- Ponto de partida: com gestao dinamica e o diretorio de catalogos vazio, o
-- cluster sobe sem nenhum catalogo de dados -- so o 'system'.
SHOW CATALOGS;   -- só system

-- system.metadata.catalogs: lista os catalogos em forma de tabela, com o
-- conector de cada um -- da para filtrar e juntar, diferente do SHOW CATALOGS.
-- A listagem de catalogos em forma de tabela, com o conector de cada um.
-- A mesma listagem em forma de tabela, com o nome do conector de cada catalogo.
-- Ao contrario do SHOW CATALOGS, da para filtrar e juntar com outras consultas.
SELECT * FROM system.metadata.catalogs;

-- ===============================================================
-- 2. CREATE CATALOG: catálogo sem reiniciar o servidor
-- ===============================================================

-- Conector sem configuração
CREATE CATALOG treino USING tpch;

-- Lista os catalogos visiveis na sessao.
-- Depois do CREATE CATALOG, o catalogo ja esta utilizavel na mesma sessao.
SHOW CATALOGS;
SELECT count(*) FROM treino.tiny.nation;

-- O MESMO conector, outro catálogo, outra configuração
CREATE CATALOG treino_padrao USING tpch
WITH ("tpch.column-naming" = 'STANDARD');

-- O MESMO conector com outra configuracao: nomes de coluna no padrao TPC-H.
SELECT n_nationkey, n_name FROM treino_padrao.tiny.nation LIMIT 3;
SELECT nationkey,  name   FROM treino.tiny.nation LIMIT 3;

-- Cria por SQL um catalogo com conexao externa, sem reiniciar o servidor.
-- Catálogo com conexão externa
-- (propriedades com hífen vão entre ASPAS DUPLAS; valores em aspas simples)
CREATE CATALOG vendas USING postgresql
WITH (
    "connection-url"      = 'jdbc:postgresql://postgres:5432/vendas',
    "connection-user"     = 'trino',
    "connection-password" = 'trino'
);

-- Lista os catalogos visiveis na sessao.
-- Confere o catalogo externo recem-criado e os schemas que ele expoe.
SHOW CATALOGS;
SHOW SCHEMAS FROM vendas;
SHOW TABLES FROM vendas.public;
SELECT * FROM vendas.public.cliente ORDER BY id;

-- Catalogo de ESCRITA, criado por SQL: um conector Hive apontado para o MinIO,
-- gravando PARQUET. Repare que toda a configuracao do conector cabe no WITH --
-- metastore, credenciais de S3 e formato default -- e que propriedade com hifen
-- ou ponto vai entre ASPAS DUPLAS, com o valor em aspas simples.
CREATE CATALOG lake USING hive
WITH (
    "hive.metastore"             = 'file',
    "hive.metastore.catalog.dir" = 's3://lakehouse/warehouse',
    "fs.native-s3.enabled"       = 'true',
    "s3.endpoint"                = 'http://minio:9000',
    "s3.region"                  = 'us-east-1',
    "s3.path-style-access"       = 'true',
    "s3.aws-access-key"          = 'minio',
    "s3.aws-secret-key"          = 'minio123',
    "hive.storage-format"        = 'PARQUET'
);

-- Prova que o catalogo recem-criado escreve de verdade: o schema e a tabela
-- nascem no bucket, e "$path" mostra o arquivo Parquet que foi gravado.
CREATE SCHEMA IF NOT EXISTS lake.lab;

-- Materializa uma tabela do catalogo tpch dinamico no catalogo Hive dinamico.
CREATE TABLE IF NOT EXISTS lake.lab.nacao WITH (format = 'PARQUET') AS
SELECT nationkey, name FROM treino.tiny.nation;

-- O arquivo no MinIO, com o caminho completo.
SELECT DISTINCT "$path" FROM lake.lab.nacao;

-- ===============================================================
-- 3. Descobrindo o que o conector aceita, sem sair do SQL
-- ===============================================================

-- Propriedades aceitas em CREATE TABLE, por catálogo
SELECT catalog_name, property_name, default_value, description
FROM system.metadata.table_properties
WHERE catalog_name IN ('vendas', 'lake')
ORDER BY catalog_name, property_name;

-- Propriedades aceitas em CREATE SCHEMA
SELECT catalog_name, property_name, default_value
FROM system.metadata.schema_properties
ORDER BY catalog_name, property_name;

-- Propriedades aceitas em ANALYZE
SELECT * FROM system.metadata.analyze_properties;

-- Propriedades de SESSÃO específicas do conector (os interruptores de pushdown)
SHOW SESSION LIKE 'vendas%';

-- ===============================================================
-- 4. Propriedade de sessão por catálogo
-- ===============================================================

-- Estado atual
SHOW SESSION LIKE 'vendas.join_pushdown%';

-- Desliga o join pushdown SÓ nesta sessão (voltaremos a isso na aula A4)
SET SESSION vendas.join_pushdown_enabled = false;
SHOW SESSION LIKE 'vendas.join_pushdown%';

-- Devolve a propriedade de sessao ao default do catalogo.
RESET SESSION vendas.join_pushdown_enabled;

-- ===============================================================
-- 5. Federação: o pagamento pelo trabalho das aulas anteriores
-- ===============================================================

-- Join entre duas tabelas do catalogo Postgres recem-criado, para confirmar
-- que o catalogo dinamico funciona como qualquer outro.
SELECT
    c.nome,
    count(p.id)        AS pedidos,
    sum(p.valor)       AS total
FROM vendas.public.cliente c
LEFT JOIN vendas.public.pedido p ON p.cliente_id = c.id
GROUP BY c.nome
ORDER BY total DESC NULLS LAST;

-- Join entre a tabela do Postgres e a do tpch, em catalogos diferentes.
-- Join entre catálogos DIFERENTES (Postgres + TPC-H gerado em memória)
SELECT c.nome, n.name AS nacao
FROM vendas.public.cliente c
JOIN treino.tiny.nation n ON n.nationkey = c.id
ORDER BY c.id;

-- ===============================================================
-- 6. DROP CATALOG
-- ===============================================================

-- DROP CATALOG remove o catalogo dinamico em tempo de execucao, sem reiniciar.
DROP CATALOG treino_padrao;
-- Lista os catalogos visiveis na sessao.
SHOW CATALOGS;

-- Consultar o catálogo removido DEVE falhar
-- SELECT * FROM treino_padrao.tiny.nation;

-- ===============================================================
-- 7. Metadados do cluster
-- ===============================================================

-- system.metadata.catalogs: lista os catalogos em forma de tabela, com o
-- conector de cada um -- da para filtrar e juntar, diferente do SHOW CATALOGS.
SELECT * FROM system.metadata.catalogs;

-- Cruzando os metadados: lista cada catalogo com o conector que o implementa e
-- quantos schemas ele expoe. E o inventario que voce quer ter ao assumir um
-- cluster que nao foi voce quem montou.
SELECT table_catalog, count(*) AS schemas
FROM (
    SELECT 'vendas'  AS table_catalog, schema_name FROM vendas.information_schema.schemata
    UNION ALL
    SELECT 'treino', schema_name FROM treino.information_schema.schemata
)
GROUP BY table_catalog
ORDER BY table_catalog;

-- ===============================================================
-- 8. Limpeza
-- ===============================================================

-- Limpeza: remove os catalogos criados por SQL. Com catalog.store=file, isso
-- APAGA os arquivos .properties correspondentes do diretorio montado.
DROP TABLE IF EXISTS lake.lab.nacao;
DROP SCHEMA IF EXISTS lake.lab;
DROP CATALOG IF EXISTS lake;
DROP CATALOG IF EXISTS vendas;
DROP CATALOG IF EXISTS treino;
-- Lista os catalogos visiveis na sessao.
SHOW CATALOGS;
