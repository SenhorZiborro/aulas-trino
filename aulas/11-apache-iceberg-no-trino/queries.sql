-- Aula 11 — Apache Iceberg
-- docker compose exec -it trino trino --catalog lake

-- ===============================================================
-- 1. Criando com particionamento OCULTO
-- ===============================================================

-- Cria o schema Iceberg apontando para um prefixo do bucket S3.
CREATE SCHEMA IF NOT EXISTS lake.vendas
WITH (location = 's3://lakehouse/iceberg/');

-- Recria a tabela de pedidos usada em toda a aula.
DROP TABLE IF EXISTS lake.vendas.pedido;

-- A sintaxe de tabela Iceberg: particionamento OCULTO e ordenacao na escrita.
-- Repare: NAO existe coluna "dia". O particionamento e derivado de criado_em,
-- e a coluna de particao NAO precisa ser a ultima.
CREATE TABLE lake.vendas.pedido (
    orderkey    BIGINT,
    custkey     BIGINT,
    orderstatus VARCHAR,
    totalprice  DOUBLE,
    criado_em   TIMESTAMP(6)
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['day(criado_em)'],
    sorted_by = ARRAY['custkey']
);

-- Primeira carga: um mes de pedidos.
INSERT INTO lake.vendas.pedido
SELECT orderkey, custkey, orderstatus, totalprice,
       CAST(orderdate AS TIMESTAMP(6))
FROM tpch.sf1.orders
WHERE orderdate >= DATE '1996-01-01' AND orderdate < DATE '1996-02-01';

-- Veja o resultado: as linhas carregadas.
SELECT count(*) FROM lake.vendas.pedido;

-- Veja o resultado do particionamento oculto: uma particao por dia, sem que
-- nenhuma coluna "dia" exista na tabela.
SELECT count(*) AS particoes FROM lake.vendas."pedido$partitions";

-- E assim que se consulta: o filtro usa a coluna NATURAL, criado_em, e o
-- pruning de particao acontece sozinho -- a query nao cita a particao.
SELECT count(*) FROM lake.vendas.pedido
WHERE criado_em >= TIMESTAMP '1996-01-15 00:00:00'
  AND criado_em <  TIMESTAMP '1996-01-16 00:00:00';

-- ===============================================================
-- 2. Snapshots: toda escrita cria um
-- ===============================================================

-- E assim que se olha o historico: $snapshots lista um commit por escrita.
SELECT * FROM lake.vendas."pedido$snapshots" ORDER BY committed_at;

-- E $history mostra qual snapshot era o corrente em cada momento.
SELECT * FROM lake.vendas."pedido$history" ORDER BY made_current_at;

-- Segunda carga: mais um mes, e portanto mais um snapshot.
INSERT INTO lake.vendas.pedido
SELECT orderkey, custkey, orderstatus, totalprice, CAST(orderdate AS TIMESTAMP(6))
FROM tpch.sf1.orders
WHERE orderdate >= DATE '1996-02-01' AND orderdate < DATE '1996-03-01';

-- Veja o resultado na tabela: as duas cargas somadas.
SELECT count(*) AS apos_segunda_carga FROM lake.vendas.pedido;  -- 37466

-- E veja o resultado nos metadados: 3 snapshots -- o CREATE TABLE (vazio) e as
-- duas cargas. Toda escrita cria um.
SELECT count(*) AS qtd_snapshots FROM lake.vendas."pedido$snapshots";  -- 3

-- ===============================================================
-- 3. Time travel
-- ===============================================================

-- Primeiro escolha o ponto no tempo: guarde o snapshot_id da PRIMEIRA carga.
SELECT snapshot_id, committed_at, operation
FROM lake.vendas."pedido$snapshots"
ORDER BY committed_at;

-- E assim que se le um snapshot pelo id (fica comentado porque o id muda a
-- cada execucao -- troque pelo da linha acima):
--   SELECT count(*) FROM lake.vendas.pedido FOR VERSION AS OF <snapshot_id>;
-- E assim que se le por instante. O ponteiro tem que estar ESTRITAMENTE no
-- passado: com current_timestamp puro a query pode empatar com o commit e
-- abortar com "Pointer value '...' is not in the past". Um segundo para tras
-- resolve, e ainda cai dentro da vida da tabela.
SELECT count(*) AS agora_por_timestamp
FROM lake.vendas.pedido FOR TIMESTAMP AS OF (current_timestamp - INTERVAL '1' SECOND);

-- ☠ Cuidado com timestamp ANTERIOR a existencia da tabela: nao devolve zero
-- nem NULL, ABORTA a query:
--   SELECT count(*) FROM lake.vendas.pedido
--   FOR TIMESTAMP AS OF (current_timestamp - INTERVAL '1' MINUTE);
--     -> No version history table vendas.pedido at or before 2026-09-05T16:51:35.127Z
-- Em pipeline que faz time travel por data, trate esse erro: uma tabela
-- recriada perde todo o historico anterior. A consulta abaixo e a defesa:
-- pergunte aos metadados desde quando existe historico.
SELECT min(committed_at) AS historico_comeca_em
FROM lake.vendas."pedido$snapshots";

-- ===============================================================
-- 4. UPDATE, DELETE e MERGE — o que o Hive não faz
-- ===============================================================

-- UPDATE no Iceberg: reescreve so os arquivos afetados (copy-on-write)
-- e gera um novo snapshot.
UPDATE lake.vendas.pedido
SET orderstatus = 'REVISADO'
WHERE orderkey = 3;

-- Veja o resultado: a linha alterada.
SELECT orderkey, orderstatus FROM lake.vendas.pedido WHERE orderkey = 3;

-- DELETE por predicado, tambem suportado.
DELETE FROM lake.vendas.pedido WHERE totalprice < 1000;

-- Veja o resultado: 37466 -> 37461, as 5 linhas com preco < 1000 sairam.
SELECT count(*) AS apos_delete FROM lake.vendas.pedido;

-- O MERGE e o upsert de verdade. Primeiro, a origem de CDC.
DROP TABLE IF EXISTS lake.vendas.origem_cdc;

-- Monta a origem de CDC para o MERGE: 200 chaves com preco 10% maior.
CREATE TABLE lake.vendas.origem_cdc AS
SELECT
    orderkey,
    custkey,
    'ATUALIZADO' AS orderstatus,
    totalprice * 1.1 AS totalprice,
    CAST(orderdate AS TIMESTAMP(6)) AS criado_em
FROM tpch.sf1.orders
WHERE orderkey BETWEEN 1 AND 200;

-- REGRA do MERGE: a origem NAO pode ter chave duplicada (aula 7). Esta
-- consulta e o teste -- zero linhas significa origem valida.
SELECT orderkey, count(*) FROM lake.vendas.origem_cdc
GROUP BY orderkey HAVING count(*) > 1;

-- O MERGE: atualiza o que casa, insere o que nao casa, numa passada.
MERGE INTO lake.vendas.pedido d
USING lake.vendas.origem_cdc o
    ON d.orderkey = o.orderkey
WHEN MATCHED THEN UPDATE
    SET orderstatus = o.orderstatus, totalprice = o.totalprice
WHEN NOT MATCHED THEN INSERT (orderkey, custkey, orderstatus, totalprice, criado_em)
    VALUES (o.orderkey, o.custkey, o.orderstatus, o.totalprice, o.criado_em);

-- Veja o resultado: 55 atualizados. Os outros ~145 orderkeys da origem NAO
-- existiam na janela carregada (jan+fev/1996) e cairam no INSERT.
SELECT count(*) FILTER (WHERE orderstatus = 'ATUALIZADO') AS atualizados
FROM lake.vendas.pedido;

-- ☠ E veja o efeito colateral: cada linha inserida tem criado_em de um ano
-- diferente, entao day(criado_em) criou ~145 particoes novas com UM arquivo
-- de 856 bytes cada. O MERGE de um CDC pequeno e uma das principais fabricas
-- de arquivos minusculos do lakehouse -- e o motivo de o optimize entrar na
-- rotina (bloco 10).
SELECT count(*) AS arquivos, min(file_size_in_bytes) AS menor_arquivo_bytes
FROM lake.vendas."pedido$files";

-- ===============================================================
-- 5. Rollback: desfazendo uma carga ruim
-- ===============================================================

-- Para voltar ao estado anterior ao MERGE, chame a procedure com o id da linha
-- desejada -- fica comentada porque o id muda a cada execucao:
--   CALL lake.system.rollback_to_snapshot('vendas', 'pedido', <snapshot_id>);
-- Partindo de (1,'C'),(2,'A'),(3,'B'), o rollback para o snapshot do primeiro
-- INSERT devolve exatamente (1,'A'),(2,'A') -- a linha 3 e o UPDATE somem. E o
-- rollback NAO apaga snapshots: cria um novo estado apontando para o antigo,
-- entao da para "voltar do rollback" enquanto o expire_snapshots nao passar.
SELECT snapshot_id, committed_at, operation
FROM lake.vendas."pedido$snapshots" ORDER BY committed_at;

-- ===============================================================
-- 6. Schema evolution segura
-- ===============================================================

-- Adicionar coluna no Iceberg e so metadado, nao reescreve dados.
ALTER TABLE lake.vendas.pedido ADD COLUMN canal VARCHAR;

-- Veja o resultado no schema: a coluna existe.
DESCRIBE lake.vendas.pedido;

-- E veja o resultado nos dados antigos: leem NULL na coluna nova, sem
-- reescrita de arquivo.
SELECT canal, count(*) FROM lake.vendas.pedido GROUP BY canal;

-- Renomear tambem e so metadado -- colunas tem ID, nao posicao.
ALTER TABLE lake.vendas.pedido RENAME COLUMN canal TO origem_canal;

-- Veja o resultado: mesmo ID, nome novo.
DESCRIBE lake.vendas.pedido;

-- E remover uma coluna nao desloca a leitura das outras.
ALTER TABLE lake.vendas.pedido DROP COLUMN origem_canal;

-- Veja o resultado: a tabela voltou ao schema original, e nenhum arquivo foi
-- reescrito em nenhuma das tres operacoes.
DESCRIBE lake.vendas.pedido;

-- ===============================================================
-- 7. Partition evolution
-- ===============================================================

-- Muda o particionamento SEM reescrever o que ja existe.
ALTER TABLE lake.vendas.pedido
SET PROPERTIES partitioning = ARRAY['month(criado_em)', 'bucket(custkey, 8)'];

-- Veja o resultado: o DDL atual, ja com o particionamento evoluido.
SHOW CREATE TABLE lake.vendas.pedido;

-- Nova carga: ela ja usa o layout mensal.
INSERT INTO lake.vendas.pedido
SELECT orderkey, custkey, orderstatus, totalprice, CAST(orderdate AS TIMESTAMP(6))
FROM tpch.sf1.orders
WHERE orderdate >= DATE '1996-03-01' AND orderdate < DATE '1996-04-01';

-- Veja o resultado: as duas especificacoes de particao convivendo na mesma
-- tabela -- os dados antigos mantem o layout diario, e o Iceberg le os dois.
SELECT * FROM lake.vendas."pedido$partitions" LIMIT 10;

-- ===============================================================
-- 8. Write-Audit-Publish (e o que o Trino 483 faz e nao faz)
-- ===============================================================

-- O Iceberg tem BRANCHES (como no git). O Trino 483 sabe LER um branch,
-- mas NAO cria nem publica branch:
--   CREATE BRANCH staging IN TABLE lake.vendas.pedido;
--     -> Query ... failed: This connector does not support creating branches
--   SHOW BRANCHES FROM TABLE lake.vendas.pedido;  -> 0 rows
-- Assim se listam as referencias que existem -- uma linha, name='main',
-- type='BRANCH', com o snapshot_id atual. Branch criado por outro motor
-- (Spark, por exemplo) apareceria aqui e seria legivel.
SELECT * FROM lake.vendas."pedido$refs";

-- E assim se le um branch pelo nome, em vez do snapshot_id.
SELECT count(*) AS via_ref_main FROM lake.vendas.pedido FOR VERSION AS OF 'main';

-- O WAP possivel hoje no Trino e com TABELA DE STAGING.
DROP TABLE IF EXISTS lake.vendas.pedido_staging;

-- Passo 1 do WAP -- WRITE: a carga vai para a staging, que nenhum consumidor le.
CREATE TABLE lake.vendas.pedido_staging
WITH (format = 'PARQUET', partitioning = ARRAY['day(criado_em)']) AS
SELECT orderkey, custkey, 'NOVO' AS orderstatus, totalprice,
       CAST(orderdate AS TIMESTAMP(6)) AS criado_em
FROM tpch.sf1.orders
WHERE orderdate >= DATE '1996-04-01' AND orderdate < DATE '1996-04-05';

-- Passo 2 -- AUDIT: os testes de qualidade rodam ANTES de tocar a publicada.
SELECT
    count(*)                                        AS linhas,
    count(*) FILTER (WHERE totalprice IS NULL)      AS preco_nulo,
    count(*) FILTER (WHERE totalprice < 0)          AS preco_negativo,
    count(DISTINCT orderkey)                        AS chaves_distintas
FROM lake.vendas.pedido_staging;

-- A contagem da tabela publicada, para comparar depois.
SELECT count(*) AS main_antes FROM lake.vendas.pedido;

-- Passo 3 -- PUBLISH, so se a auditoria passou. O INSERT vira UM snapshot:
-- ou entra inteiro, ou nao entra.
INSERT INTO lake.vendas.pedido (orderkey, custkey, orderstatus, totalprice, criado_em)
SELECT orderkey, custkey, orderstatus, totalprice, criado_em
FROM lake.vendas.pedido_staging;

-- Veja o resultado: tudo entrou num unico snapshot. E se a publicacao tivesse
-- sido ruim, o snapshot anterior continua la (bloco 5).
SELECT count(*) AS main_apos_publicacao FROM lake.vendas.pedido;

-- Fim do ciclo: a staging nao e dado, e andaime.
DROP TABLE IF EXISTS lake.vendas.pedido_staging;

-- ===============================================================
-- 9. As tabelas de metadados
-- ===============================================================

-- Assim se olham as propriedades efetivas da tabela.
SELECT * FROM lake.vendas."pedido$properties";

-- Assim se olham os manifests -- os indices que apontam para os arquivos.
SELECT * FROM lake.vendas."pedido$manifests" LIMIT 5;

-- E assim se olha o log de versoes de metadado da tabela.
SELECT * FROM lake.vendas."pedido$metadata_log_entries" LIMIT 5;

-- $files e a melhor ferramenta de diagnostico do lakehouse: um arquivo por
-- linha, do menor para o maior.
SELECT file_path, record_count, file_size_in_bytes
FROM lake.vendas."pedido$files"
ORDER BY file_size_in_bytes
LIMIT 10;

-- E assim se faz o diagnostico de arquivos pequenos em uma consulta.
SELECT
    count(*)                                    AS arquivos,
    round(avg(file_size_in_bytes)/1024/1024, 2) AS tamanho_medio_mb,
    round(min(file_size_in_bytes)/1024/1024, 2) AS menor_mb,
    round(max(file_size_in_bytes)/1024/1024, 2) AS maior_mb
FROM lake.vendas."pedido$files";

-- ===============================================================
-- 10. Manutenção
-- ===============================================================

-- optimize compacta arquivos pequenos e aplica os delete files.
ALTER TABLE lake.vendas.pedido EXECUTE optimize;

-- Veja o resultado: 137 arquivos antes, 80 depois. O optimize NAO junta
-- arquivos de particoes diferentes -- as ~145 particoes de 1 linha continuam
-- separadas. Compactar nao conserta particionamento errado.
SELECT count(*) AS arquivos_apos_optimize FROM lake.vendas."pedido$files";

-- optimize_manifests agrupa os manifests por particao.
ALTER TABLE lake.vendas.pedido EXECUTE optimize_manifests;

-- Antes de expirar snapshot, conte o que existe.
SELECT count(*) AS snapshots_antes FROM lake.vendas."pedido$snapshots";

-- expire_snapshots libera espaco e PERDE o time travel do que apagar.
ALTER TABLE lake.vendas.pedido EXECUTE expire_snapshots(retention_threshold => '1m');

-- Veja o resultado: 9 antes, 9 depois -- NADA expirou. O retention_threshold e
-- "apague o que for MAIS VELHO que isto", e todos os snapshots tinham menos de
-- 1 minuto. Nao e bug, e a rede de seguranca: o piso vem do catalogo
-- (iceberg.expire-snapshots.min-retention) e pedir menos que ele e recusado.
SELECT count(*) AS snapshots_depois FROM lake.vendas."pedido$snapshots";

-- remove_orphan_files apaga o que nenhum snapshot referencia (PERIGOSO com
-- escrita concorrente de outro motor).
ALTER TABLE lake.vendas.pedido EXECUTE remove_orphan_files(retention_threshold => '1m');

-- ===============================================================
-- 11. Materialized view
-- ===============================================================

-- Materialized view: FUNCIONA aqui porque o catalogo e hive_metastore.
CREATE MATERIALIZED VIEW IF NOT EXISTS lake.vendas.mv_por_status
GRACE PERIOD INTERVAL '5' MINUTE
WHEN STALE INLINE
AS
SELECT orderstatus, count(*) AS pedidos, sum(totalprice) AS total
FROM lake.vendas.pedido
GROUP BY orderstatus;

-- Veja o resultado antes do refresh: ja responde, porque a MV nasce STALE e o
-- Trino cai de volta na query de definicao enquanto ela estiver assim.
SELECT count(*) AS antes_do_refresh FROM lake.vendas.mv_por_status;

-- O refresh materializa o resultado de verdade.
REFRESH MATERIALIZED VIEW lake.vendas.mv_por_status;

-- Veja o resultado depois: agora a leitura vem da tabela materializada.
SELECT * FROM lake.vendas.mv_por_status ORDER BY orderstatus;

-- ===============================================================
-- 12. Migrando uma tabela Hive para Iceberg
-- ===============================================================

-- Um schema no catalogo HIVE, para montar a tabela legada.
CREATE SCHEMA IF NOT EXISTS hive.legado WITH (location = 's3://lakehouse/legado/');

-- Recria a tabela legada do zero.
DROP TABLE IF EXISTS hive.legado.antiga;

-- A tabela HIVE que vai ser convertida.
CREATE TABLE hive.legado.antiga
WITH (format = 'PARQUET') AS
SELECT nationkey, name, regionkey FROM tpch.tiny.nation;

-- Confere a tabela legada antes da migracao.
SELECT count(*) FROM hive.legado.antiga;

-- migrate converte METADADOS e mantem os arquivos onde estao.
CALL lake.system.migrate(schema_name => 'legado', table_name => 'antiga');

-- Veja o resultado: as mesmas 25 linhas, agora pelo catalogo Iceberg.
SELECT count(*) FROM lake.legado.antiga;

-- E veja por que foi barato: um unico snapshot, operacao "append". O migrate
-- so escreveu metadado -- nenhum byte de dado foi reescrito.
SELECT * FROM lake.legado."antiga$snapshots";

-- ===============================================================
-- 13. Limpeza
-- ===============================================================

-- Derruba tudo que a aula criou, para poder rodar de novo do zero.
DROP TABLE IF EXISTS lake.vendas.ex_sintaxe;
DROP MATERIALIZED VIEW IF EXISTS lake.vendas.mv_por_status;
DROP TABLE IF EXISTS lake.legado.antiga;
DROP TABLE IF EXISTS lake.vendas.pedido_staging;
DROP TABLE IF EXISTS lake.vendas.origem_cdc;
DROP TABLE IF EXISTS lake.vendas.pedido;
