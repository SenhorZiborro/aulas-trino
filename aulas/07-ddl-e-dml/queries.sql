-- Aula 7 — DDL e DML sobre arquivos (PARQUET, JSON, CSV) no MinIO
-- Interativo:  docker compose exec -it trino trino --catalog lake --schema loja
-- Batch:       docker compose exec -T trino trino --file /dev/stdin < queries.sql
--
-- Todo comando deste arquivo roda com sucesso. Onde o conector recusa alguma
-- operacao, o fato esta anotado em comentario -- nao em comando que falha.

-- Cria o schema de trabalho no catalogo lake. Sem WITH (location = ...): neste
-- lab o metastore e o de ARQUIVO, e ele exige que o diretorio fique dentro de
-- hive.metastore.catalog.dir.
CREATE SCHEMA IF NOT EXISTS lake.loja;

-- ===============================================================
-- 1. O destino: aqui tabela é arquivo
-- ===============================================================

-- Dois catalogos: `tpch` e a origem dos dados (gerados na hora, nada baixado) e
-- `lake` e o destino -- um conector Hive apontado para o MinIO.
SHOW CATALOGS;

-- O DDL do schema, com o local onde ele foi registrado no bucket.
SHOW CREATE SCHEMA lake.loja;

-- NOTA: escrever no tpch nao e possivel -- ele e um conector somente leitura.
-- Medido: INSERT INTO tpch.tiny.nation ... -> This connector does not support
-- inserts. Suporte a escrita e propriedade do CONECTOR, nao do Trino, e esse e
-- o fio condutor da aula.

-- ===============================================================
-- 2. CREATE TABLE: o formato faz parte do DDL
-- ===============================================================

-- Limpa execucoes anteriores das tres tabelas de formato.
DROP TABLE IF EXISTS lake.loja.pedido_parquet;
DROP TABLE IF EXISTS lake.loja.pedido_json;
DROP TABLE IF EXISTS lake.loja.pedido_csv;

-- PARQUET: binario colunar, aceita qualquer tipo do Trino. E o default deste
-- catalogo (hive.storage-format=PARQUET), entao vale sem o WITH tambem.
CREATE TABLE lake.loja.pedido_parquet (
    orderkey    BIGINT,
    custkey     BIGINT,
    orderstatus VARCHAR,
    totalprice  DOUBLE,
    orderdate   DATE
)
WITH (format = 'PARQUET');

-- JSON: um objeto por linha. Tambem aceita qualquer tipo, mas repete o nome da
-- coluna em CADA registro -- barato de escrever, caro de guardar e de ler.
CREATE TABLE lake.loja.pedido_json (
    orderkey    BIGINT,
    custkey     BIGINT,
    orderstatus VARCHAR,
    totalprice  DOUBLE,
    orderdate   DATE
)
WITH (format = 'JSON');

-- CSV so aceita VARCHAR SEM TAMANHO -- nem BIGINT, nem DATE, nem varchar(1).
-- Medido com os tipos acima: Hive CSV storage format only supports VARCHAR
-- (unbounded). Unsupported columns: orderkey bigint, custkey bigint,
-- orderstatus varchar(1), totalprice double, orderdate date.
-- O preco nao e sintatico, e de MODELO: a tabela perde a tipagem, e dai em
-- diante WHERE totalprice > 1000 e comparacao de texto ('999' vem depois de
-- '1000').
CREATE TABLE lake.loja.pedido_csv (
    orderkey    VARCHAR,
    custkey     VARCHAR,
    orderstatus VARCHAR,
    totalprice  VARCHAR,
    orderdate   VARCHAR
)
WITH (format = 'CSV');

-- As tres tabelas convivem no mesmo schema, com formatos de arquivo diferentes.
SHOW TABLES FROM lake.loja;

-- ===============================================================
-- 3. CREATE TABLE AS (CTAS): cria e grava numa passada
-- ===============================================================

-- Limpa execucoes anteriores das tabelas do CTAS.
DROP TABLE IF EXISTS lake.loja.nacao_parquet;
DROP TABLE IF EXISTS lake.loja.nacao_json;
DROP TABLE IF EXISTS lake.loja.nacao_csv;

-- CTAS infere os tipos da consulta e ja escreve os arquivos.
CREATE TABLE lake.loja.nacao_parquet WITH (format = 'PARQUET') AS
SELECT nationkey, name, regionkey FROM tpch.tiny.nation;

-- A MESMA consulta, outro formato. O SQL de leitura nao muda; o arquivo muda.
CREATE TABLE lake.loja.nacao_json WITH (format = 'JSON') AS
SELECT nationkey, name, regionkey FROM tpch.tiny.nation;

-- No CSV o CAST sai do DDL e vai para a CONSULTA -- aqui fica obvio que o
-- formato influencia a query, nao so o DDL.
CREATE TABLE lake.loja.nacao_csv WITH (format = 'CSV') AS
SELECT CAST(nationkey AS VARCHAR) AS nationkey,
       CAST(name      AS VARCHAR) AS name,
       CAST(regionkey AS VARCHAR) AS regionkey
FROM tpch.tiny.nation;

-- Mesmo conteudo logico nas tres: 25 linhas cada.
SELECT count(*) AS parquet FROM lake.loja.nacao_parquet;
SELECT count(*) AS json    FROM lake.loja.nacao_json;
SELECT count(*) AS csv     FROM lake.loja.nacao_csv;

-- O DDL que o conector gravou de fato. Compare o CSV com o que voce escreveu.
SHOW CREATE TABLE lake.loja.nacao_csv;

-- Prepara a tabela de demonstracao dos tipos inferidos.
DROP TABLE IF EXISTS lake.loja.tipos_inferidos;

-- CTAS nao pergunta, INFERE: 1 vira INTEGER, count(*) vira BIGINT e 1.5 vira
-- DECIMAL(2,1). Se o destino tem contrato de tipo, faca CAST no SELECT.
CREATE TABLE lake.loja.tipos_inferidos WITH (format = 'PARQUET') AS
SELECT 1 AS inteiro, count(*) AS contagem, 1.5 AS decimal_lit, 1.5E0 AS double_lit
FROM tpch.tiny.nation;

-- Os tipos que foram gravados no arquivo.
DESCRIBE lake.loja.tipos_inferidos;

-- Prepara a tabela sem dados.
DROP TABLE IF EXISTS lake.loja.nacao_vazia;

-- WITH NO DATA cria a estrutura e NAO escreve arquivo de dados.
CREATE TABLE lake.loja.nacao_vazia WITH (format = 'PARQUET') AS
SELECT * FROM tpch.tiny.nation WITH NO DATA;

-- Zero linhas, mas a tabela existe e tem schema.
SELECT count(*) AS linhas FROM lake.loja.nacao_vazia;

-- ===============================================================
-- 4. Onde os bytes foram parar
-- ===============================================================

-- "$path" e uma coluna OCULTA do conector Hive: devolve a URI do arquivo de
-- onde cada linha foi lida. E como se confere, sem sair do SQL, o que o DDL fez
-- no storage.
SELECT DISTINCT "$path" FROM lake.loja.nacao_parquet;

-- O JSON e o CSV saem com sufixo .gz. O codec default do catalogo e GZIP, entao
-- "formato de texto" NAO quer dizer "arquivo legivel".
SELECT DISTINCT "$path" FROM lake.loja.nacao_json;
SELECT DISTINCT "$path" FROM lake.loja.nacao_csv;

-- A propriedade que controla isso. Repare no prefixo: ela e DO CATALOGO
-- (lake.), nao global. Valores: NONE, SNAPPY, LZ4, ZSTD, GZIP.
SHOW SESSION LIKE 'lake.compression_codec';

-- Desligando a compressao, o proximo arquivo escrito sai em texto puro.
SET SESSION lake.compression_codec = 'NONE';

-- Prepara a versao sem compressao.
DROP TABLE IF EXISTS lake.loja.nacao_csv_plano;

-- Mesma tabela, sem compressao: e este arquivo que da para abrir no olho
-- (o README mostra o comando de leitura pelo MinIO).
CREATE TABLE lake.loja.nacao_csv_plano WITH (format = 'CSV') AS
SELECT CAST(nationkey AS VARCHAR) AS nationkey, CAST(name AS VARCHAR) AS name
FROM tpch.tiny.nation;

-- Agora sem o .gz no fim.
SELECT DISTINCT "$path" FROM lake.loja.nacao_csv_plano;

-- Devolve o codec ao default do catalogo.
RESET SESSION lake.compression_codec;

-- "$file_size" tambem e coluna oculta: da para comparar o custo dos formatos
-- sem sair do SQL.
SELECT DISTINCT "$file_size" AS bytes_parquet FROM lake.loja.nacao_parquet;
SELECT DISTINCT "$file_size" AS bytes_json    FROM lake.loja.nacao_json;

-- ===============================================================
-- 5. INSERT: cada carga vira um arquivo novo
-- ===============================================================

-- Carga em cima da tabela tipada que o bloco 2 criou.
INSERT INTO lake.loja.pedido_parquet
SELECT orderkey, custkey, orderstatus, totalprice, orderdate
FROM tpch.tiny.orders WHERE orderkey < 100;

-- As duas formas de INSERT: por posicao e nomeando as colunas. Nomear e o que
-- protege a carga de quebrar quando alguem acrescenta coluna na tabela.
INSERT INTO lake.loja.pedido_parquet (orderkey, custkey, orderstatus, totalprice, orderdate)
VALUES (999999, 1, 'N', 10.0, DATE '2026-01-01');

-- Um arquivo por INSERT: o DML aqui nao atualiza nada, ele ACRESCENTA arquivo.
SELECT count(DISTINCT "$path") AS arquivos, count(*) AS linhas
FROM lake.loja.pedido_parquet;

-- INSERT nao deduplica: repetir a carga duplica os dados, e no storage isso
-- aparece como mais um arquivo. Nao existe INSERT ... ON CONFLICT no Trino.
INSERT INTO lake.loja.pedido_parquet
SELECT orderkey, custkey, orderstatus, totalprice, orderdate
FROM tpch.tiny.orders WHERE orderkey < 100;

-- Mesmas chaves duas vezes, e um arquivo a mais.
SELECT count(DISTINCT "$path") AS arquivos, count(*) AS linhas
FROM lake.loja.pedido_parquet;

-- ===============================================================
-- 6. ALTER TABLE: o que é só metadado, e o que corrompe o arquivo
-- ===============================================================

-- ADD COLUMN e so metadado: os arquivos ja escritos NAO sao reescritos.
ALTER TABLE lake.loja.nacao_json ADD COLUMN continente VARCHAR;

-- A coluna aparece no schema...
DESCRIBE lake.loja.nacao_json;

-- ...e le como NULL nos dados antigos, porque nao existe no arquivo.
SELECT name, continente FROM lake.loja.nacao_json ORDER BY name LIMIT 3;

-- Prepara o par de sondas do RENAME COLUMN.
DROP TABLE IF EXISTS lake.loja.ren_parquet;
DROP TABLE IF EXISTS lake.loja.ren_csv;

-- Duas tabelas com o mesmo conteudo, formatos diferentes. O conector Hive casa
-- coluna com dado de forma DIFERENTE conforme o formato: PARQUET e JSON casam
-- por NOME, CSV casa por POSICAO. As sondas a seguir mostram a consequencia.
CREATE TABLE lake.loja.ren_parquet WITH (format = 'PARQUET') AS
SELECT 1 AS a, 'texto' AS b;

-- A gemea em CSV (tudo VARCHAR, como o formato exige).
CREATE TABLE lake.loja.ren_csv WITH (format = 'CSV') AS
SELECT CAST(1 AS VARCHAR) AS a, CAST('texto' AS VARCHAR) AS b;

-- RENAME COLUMN em PARQUET: o DDL passa, e o DADO VIRA NULL. O arquivo ainda
-- guarda a coluna com o nome antigo, e ninguem avisa.
ALTER TABLE lake.loja.ren_parquet RENAME COLUMN b TO b2;
SELECT * FROM lake.loja.ren_parquet;
-- Medido: a = 1, b2 = NULL. O 'texto' continua no arquivo, inacessivel.

-- O MESMO rename em CSV: o dado SOBREVIVE, porque o CSV casa por posicao.
ALTER TABLE lake.loja.ren_csv RENAME COLUMN b TO b2;
SELECT * FROM lake.loja.ren_csv;
-- Medido: a = 1, b2 = 'texto'.

-- Prepara o par de sondas do DROP COLUMN.
DROP TABLE IF EXISTS lake.loja.drop_parquet;
DROP TABLE IF EXISTS lake.loja.drop_csv;

-- Agora o inverso, com DROP COLUMN do MEIO. Primeiro em PARQUET.
CREATE TABLE lake.loja.drop_parquet WITH (format = 'PARQUET') AS
SELECT 1 AS a, 'meio' AS b, 9 AS c;

-- E a gemea em CSV.
CREATE TABLE lake.loja.drop_csv WITH (format = 'CSV') AS
SELECT CAST(1 AS VARCHAR) AS a, CAST('meio' AS VARCHAR) AS b, CAST(9 AS VARCHAR) AS c;

-- DROP COLUMN em PARQUET: correto, porque casa por nome.
ALTER TABLE lake.loja.drop_parquet DROP COLUMN b;
SELECT * FROM lake.loja.drop_parquet;
-- Medido: a = 1, c = 9. Certo.

-- DROP COLUMN em CSV: a coluna 'c' passa a mostrar o valor de 'b'. Casando por
-- posicao, tirar a coluna do meio DESLOCA tudo para a esquerda -- corrupcao
-- silenciosa, sem erro nenhum.
ALTER TABLE lake.loja.drop_csv DROP COLUMN b;
SELECT * FROM lake.loja.drop_csv;
-- Medido: a = 1, c = 'meio'. ERRADO, e sem aviso.

-- COMMENT, esse sim, e metadado puro e funciona sempre.
COMMENT ON TABLE lake.loja.nacao_parquet IS 'nacoes do tpch, em parquet';
SHOW CREATE TABLE lake.loja.nacao_parquet;

-- NOTA, duas que este conector nao faz (medido):
--   ALTER TABLE ... RENAME TO      -> S3 does not support directory renames
--   ALTER TABLE ... SET PROPERTIES -> This connector does not support setting
--                                     table properties
-- Renomear tabela gerenciada aqui significaria renomear DIRETORIO, e object
-- storage nao tem essa operacao.

-- ===============================================================
-- 7. Particionamento: um diretório por valor
-- ===============================================================

-- Prepara a tabela particionada da aula.
DROP TABLE IF EXISTS lake.loja.venda;

-- partitioned_by e DDL: cria um DIRETORIO por valor da coluna. No conector Hive
-- a coluna de particao vem por ULTIMO na lista de colunas -- a ordem e parte do
-- contrato, nao estilo.
CREATE TABLE lake.loja.venda (
    id     BIGINT,
    valor  DOUBLE,
    dia    DATE
)
WITH (format = 'PARQUET', partitioned_by = ARRAY['dia']);

-- Tres linhas em dois dias.
INSERT INTO lake.loja.venda VALUES
 (1, 10.0, DATE '2026-01-01'),
 (2, 20.0, DATE '2026-01-01'),
 (3, 30.0, DATE '2026-01-02');

-- O caminho carrega dia=<valor> no nome do diretorio.
SELECT dia, "$path" FROM lake.loja.venda ORDER BY id;

-- A tabela de metadado $partitions lista as particoes registradas.
SELECT * FROM lake.loja."venda$partitions" ORDER BY dia;

-- Com filtro na coluna de particao, o motor le so o diretorio certo -- procure
-- o "Physical input" no EXPLAIN ANALYZE.
EXPLAIN ANALYZE SELECT sum(valor) FROM lake.loja.venda WHERE dia = DATE '2026-01-02';

-- ===============================================================
-- 8. DELETE de partição: o único DML de remoção que existe aqui
-- ===============================================================
-- NOTA sobre o que este conector recusa (medido):
--   UPDATE                            -> Modifying Hive table rows is only
--   DELETE por coluna NAO-particionada    supported for transactional tables
--   MERGE
--   TRUNCATE TABLE                    -> This connector does not support
--                                        truncating tables
-- A razao e concreta: trocar ou apagar UMA linha exigiria reescrever o arquivo
-- que a contem, e o conector nao faz isso. As tres voltam a funcionar em
-- formatos com row-level delete -- Iceberg (aula 21) e Delta (aula 22).

-- O que FUNCIONA: filtrar so pela coluna de PARTICAO. O conector nao toca em
-- linha nenhuma -- ele descarta o DIRETORIO inteiro da particao.
DELETE FROM lake.loja.venda WHERE dia = DATE '2026-01-01';

-- Sobrou so a particao de 02: o Hive nao recusa APAGAR, recusa apagar LINHA.
SELECT dia, count(*) AS linhas FROM lake.loja.venda GROUP BY dia ORDER BY dia;

-- ===============================================================
-- 9. Sem UPDATE: os dois padrões idempotentes que sobram
-- ===============================================================

-- Prepara a tabela do full refresh.
DROP TABLE IF EXISTS lake.loja.cliente_atual;

-- Padrao 1 -- FULL REFRESH: derruba e recria o conjunto inteiro, ja
-- deduplicado com row_number(). Simples, e reescreve tudo.
CREATE TABLE lake.loja.cliente_atual WITH (format = 'PARQUET') AS
SELECT custkey, orderstatus, totalprice
FROM (
    SELECT *, row_number() OVER (PARTITION BY custkey ORDER BY totalprice DESC) AS rn
    FROM tpch.tiny.orders
)
WHERE rn = 1;

-- Uma linha por cliente, independente de quantas vezes voce rodar.
SELECT count(*) AS clientes FROM lake.loja.cliente_atual;

-- Padrao 2 -- REESCRITA DE PARTICAO: so a particao afetada e refeita. E o
-- padrao real de pipeline em data lake, e e o DELETE do bloco 8 + INSERT.
-- Medido aqui: 2026-01-02, 1 linha, soma 30.0 -- o estado antes da correcao.
SELECT dia, count(*) AS linhas, sum(valor) AS soma
FROM lake.loja.venda GROUP BY dia ORDER BY dia;

-- Apaga a particao do dia (descarta o diretorio)...
DELETE FROM lake.loja.venda WHERE dia = DATE '2026-01-02';

-- ...e grava o dia inteiro de novo, com o valor corrigido.
INSERT INTO lake.loja.venda VALUES (3, 99.0, DATE '2026-01-02');

-- Medido: 1 linha, soma 99.0 -- e continua 1 linha se voce repetir o par. E isso
-- que idempotente quer dizer, e e por isso que o particionamento e a UNIDADE DE
-- REPROCESSAMENTO do pipeline.
SELECT dia, count(*) AS linhas, sum(valor) AS soma
FROM lake.loja.venda GROUP BY dia ORDER BY dia;

-- ===============================================================
-- 10. Tabela EXTERNA: um arquivo que você criou, lido como tabela
-- ===============================================================
-- PRE-REQUISITO: os arquivos s3://lakehouse/entrada_csv/vendas.csv e
-- s3://lakehouse/entrada_json/vendas.json tem que existir. O Passo
-- correspondente do README mostra como cria-los pelo MinIO.

-- Prepara a primeira tabela externa.
DROP TABLE IF EXISTS lake.loja.entrada_csv;

-- external_location aponta a tabela para um diretorio que JA EXISTE. Nao houve
-- CTAS nem INSERT: o DDL so declarou como ler bytes que ja estavam la.
CREATE TABLE lake.loja.entrada_csv (
    id      VARCHAR,
    produto VARCHAR,
    preco   VARCHAR
)
WITH (format = 'CSV', external_location = 's3://lakehouse/entrada_csv/');

-- O arquivo que voce escreveu na mao, agora como tabela.
SELECT * FROM lake.loja.entrada_csv ORDER BY id;

-- Prepara a segunda tabela externa.
DROP TABLE IF EXISTS lake.loja.entrada_json;

-- O mesmo com JSON -- e aqui da para TIPAR, porque o JSON nao tem a restricao
-- do CSV. O conector casa a chave do objeto com o nome da coluna.
CREATE TABLE lake.loja.entrada_json (
    id      BIGINT,
    produto VARCHAR
)
WITH (format = 'JSON', external_location = 's3://lakehouse/entrada_json/');

-- Tipado de verdade: da para somar e comparar sem CAST.
SELECT id, produto FROM lake.loja.entrada_json ORDER BY id;

-- A diferenca que importa: em tabela EXTERNA o DROP TABLE remove so o registro
-- no metastore. Os ARQUIVOS ficam no bucket (confira pelo README).
DROP TABLE lake.loja.entrada_csv;

-- ===============================================================
-- 11. A sonda: descobrindo o suporte na marra
-- ===============================================================

-- Prepara a tabela-sonda.
DROP TABLE IF EXISTS lake.loja.sonda;

-- O habito que fica da aula: em vez de procurar na doc o que o conector faz,
-- PERGUNTE a ele com uma tabela descartavel, em ambiente de teste, onde um erro
-- nao custa nada. O README traz a matriz completa que saiu dessa sonda.
CREATE TABLE lake.loja.sonda WITH (format = 'PARQUET') AS SELECT 1 AS a, 'b' AS b;

-- Uma das perguntas que este conector responde com sim.
ALTER TABLE lake.loja.sonda ADD COLUMN c VARCHAR;

-- O que o conector aceitou de fato.
DESCRIBE lake.loja.sonda;

-- Metadados de tudo que a aula escreveu no bucket.
SELECT table_name
FROM lake.information_schema.tables
WHERE table_schema = 'loja'
ORDER BY table_name;

-- ===============================================================
-- 12. Limpeza
-- ===============================================================

-- Limpeza: as tabelas gerenciadas levam os ARQUIVOS junto no DROP; a externa
-- (entrada_json) deixa o arquivo no bucket de proposito.
DROP TABLE IF EXISTS lake.loja.sonda;
DROP TABLE IF EXISTS lake.loja.entrada_json;
DROP TABLE IF EXISTS lake.loja.cliente_atual;
DROP TABLE IF EXISTS lake.loja.venda;
DROP TABLE IF EXISTS lake.loja.drop_csv;
DROP TABLE IF EXISTS lake.loja.drop_parquet;
DROP TABLE IF EXISTS lake.loja.ren_csv;
DROP TABLE IF EXISTS lake.loja.ren_parquet;
DROP TABLE IF EXISTS lake.loja.nacao_vazia;
DROP TABLE IF EXISTS lake.loja.tipos_inferidos;
DROP TABLE IF EXISTS lake.loja.nacao_csv_plano;
DROP TABLE IF EXISTS lake.loja.nacao_csv;
DROP TABLE IF EXISTS lake.loja.nacao_json;
DROP TABLE IF EXISTS lake.loja.nacao_parquet;
DROP TABLE IF EXISTS lake.loja.pedido_csv;
DROP TABLE IF EXISTS lake.loja.pedido_json;
DROP TABLE IF EXISTS lake.loja.pedido_parquet;
DROP TABLE IF EXISTS lake.loja.ex_refresh;
DROP TABLE IF EXISTS lake.loja.ex_del;
DROP TABLE IF EXISTS lake.loja.ex_fmt_csv;
DROP TABLE IF EXISTS lake.loja.ex_fmt_json;
DROP TABLE IF EXISTS lake.loja.ex_fmt_parquet;
DROP TABLE IF EXISTS lake.loja.ex_insert;
DROP TABLE IF EXISTS lake.loja.ex_vazia;
DROP TABLE IF EXISTS lake.loja.ex_ctas;
DROP TABLE IF EXISTS lake.loja.ex_like;
DROP TABLE IF EXISTS lake.loja.ex_completa;
DROP TABLE IF EXISTS lake.loja.ex_alter;
DROP SCHEMA IF EXISTS lake.loja;
