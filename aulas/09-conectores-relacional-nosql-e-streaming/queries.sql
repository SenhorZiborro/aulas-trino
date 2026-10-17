-- Aula 9 — conectores: relacional, NoSQL e streaming
-- docker compose exec -it trino trino
--
-- Tres familias de fonte, um lab so. O que muda de uma para outra nao e a
-- sintaxe do SELECT -- e o que o Trino consegue EMPURRAR para a origem, o que
-- consegue ESCREVER, e de onde vem o schema.
--
-- PRE-REQUISITO: o Postgres e o Mongo sao semeados sozinhos pelo compose. O
-- TOPICO do Kafka e carregado no Passo 4 do README; sem isso a Parte 3 roda,
-- mas devolve zero linhas.

-- Os cinco catalogos do lab: um Postgres (duas vezes, com configuracoes
-- diferentes), um Mongo, dois Kafka e o lake em Parquet.
SHOW CATALOGS;

-- ===============================================================
-- 1. Descoberta e mapeamento de tipos
-- ===============================================================

-- No conector JDBC o 'schema' do Trino e o schema do banco (aqui, public).
SHOW SCHEMAS FROM vendas;
SHOW TABLES FROM vendas.public;

-- Type mapping na pratica: cada tipo do Postgres virou um tipo do Trino.
DESCRIBE vendas.public.cliente;

-- ===============================================================
-- 2. Os tipos difíceis
-- ===============================================================

-- Estas colunas SO aparecem porque o catalogo tem array-mapping=AS_ARRAY e
-- unsupported-type-handling=CONVERT_TO_VARCHAR. Sem isso, a coluna de array
-- seria recusada e o tipo desconhecido sumiria da tabela.
SELECT id, nome, tags, metadata, criado_em
FROM vendas.public.cliente
ORDER BY id;

-- metadata chega como JSON (veio de jsonb): json_format devolve o texto do
-- documento e json_value extrai um caminho dele.
SELECT
    id,
    cardinality(tags)                              AS qtd_tags,
    contains(tags, 'vip')                          AS eh_vip,
    json_value(json_format(metadata), 'lax $.origem' RETURNING VARCHAR) AS origem,
    typeof(criado_em)                              AS tipo_timestamp
FROM vendas.public.cliente
ORDER BY id;

-- ===============================================================
-- 3. Pushdown, o assunto central de performance
-- ===============================================================
-- Pushdown e o Trino delegar trabalho ao banco em vez de trazer linhas. Neste
-- conector ele empurra: filtro de igualdade e de faixa em NUMERO, igualdade em
-- TEXTO, agregacao com e sem GROUP BY, e LIMIT/Top-N. Nao empurra FAIXA EM
-- TEXTO -- a ordenacao de texto depende da collation da origem, que pode nao
-- ser a do Trino, e empurrar mudaria o resultado.

-- No plano, o filtro empurrado aparece DENTRO do TableScan; quando nao e
-- empurrado, aparece num FilterProject do proprio Trino. E assim que se
-- confere qualquer caso.
EXPLAIN SELECT count(*) FROM vendas.public.pedido WHERE status = 'ok';

-- ===============================================================
-- 4. Join pushdown e escrita
-- ===============================================================
-- Join tambem pode ser empurrado: o Trino manda o JOIN inteiro como SQL para o
-- Postgres, em vez de ler as duas tabelas e juntar aqui. Quem decide e o
-- otimizador de custo, caso a caso -- ligar o pushdown nao garante obte-lo.
SELECT c.nome, count(*) AS pedidos
FROM vendas.public.cliente c
JOIN vendas.public.pedido p ON p.cliente_id = c.id
GROUP BY c.nome ORDER BY c.nome;

-- ===============================================================
-- 5. Escrita e o limite da chave primária
-- ===============================================================

-- CREATE SCHEMA aqui cria o schema DENTRO do Postgres: o Trino repassa o
-- comando para o banco de origem.
CREATE SCHEMA IF NOT EXISTS vendas.lab;

-- Prepara a tabela de destino no banco remoto.
DROP TABLE IF EXISTS vendas.lab.destino;

-- CTAS remoto: a tabela e criada e preenchida no Postgres.
CREATE TABLE vendas.lab.destino AS
SELECT id, cliente_id, valor, status FROM vendas.public.pedido WHERE id <= 100;

-- INSERT remoto: por padrao o conector usa tabela temporaria e so publica no fim.
INSERT INTO vendas.lab.destino
SELECT id, cliente_id, valor, status FROM vendas.public.pedido WHERE id BETWEEN 101 AND 200;

-- Confirma o que foi gravado no Postgres.
SELECT count(*) AS linhas_no_postgres FROM vendas.lab.destino;

-- UPDATE com CONSTANTE: funciona, vira um UPDATE simples no Postgres.
UPDATE vendas.lab.destino SET status = 'revisado' WHERE id = 1;

-- DELETE com predicado EMPURRAVEL: funciona pela mesma razao.
DELETE FROM vendas.lab.destino WHERE id = 2;

-- Confere o resultado das duas operacoes.
SELECT count(*) AS apos_update_e_delete FROM vendas.lab.destino;
-- O limite da escrita JDBC: UPDATE com EXPRESSAO (SET valor = valor * 1.1) ou
-- DELETE com funcao no WHERE (WHERE lower(status) = 'ok') caem no caminho de
-- MERGE em nivel de linha, que precisa identificar cada linha e por isso exige
-- CHAVE PRIMARIA no destino. Uma tabela criada por CTAS nasce sem PK. A causa
-- real e o TIPO DO PREDICADO: constante empurravel vira comando simples;
-- expressao ou funcao viram merge linha a linha.

-- ===============================================================
-- 6. As válvulas de escape
-- ===============================================================

-- query(): table function que manda SQL NATIVO da origem, sem parsing do
-- Trino. Serve para o que o Trino nao expressa -- aqui, DISTINCT ON.
SELECT * FROM TABLE(vendas.system.query(
    query => 'SELECT DISTINCT ON (cliente_id) cliente_id, id, valor
              FROM pedido ORDER BY cliente_id, valor DESC'
));
-- ATENCAO: query() NAO passa pelo controle de acesso do Trino, e o resultado
-- NAO tem ordem garantida mesmo com ORDER BY dentro do SQL nativo.

-- ===============================================================
-- 7. O schema que o Trino inferiu
-- ===============================================================

-- No MongoDB nao existe schema declarado: o conector expoe cada BANCO como um
-- schema e cada COLECAO como tabela.
SHOW SCHEMAS FROM loja;
SHOW TABLES FROM loja.loja;

-- O schema que o conector INFERIU amostrando os documentos.
DESCRIBE loja.loja.pedido;

-- Le a colecao como tabela comum.
SELECT * FROM loja.loja.cliente ORDER BY _id;

-- ===============================================================
-- 8. O campo que só existe em um documento
-- ===============================================================

-- O documento _id=3 tem o campo "cupom"; os outros nao. Repare que ele NAO
-- aparece: a inferencia amostrou os documentos e nao o registrou. Numa fonte
-- sem schema, o schema e um PALPITE do conector.
SELECT * FROM loja.loja.pedido ORDER BY _id;
-- O conector grava o schema inferido dentro do proprio MongoDB, na colecao
-- _schema. O Passo correspondente do README mostra como ler essa colecao.

-- ===============================================================
-- 9. Documentos aninhados viram ROW e ARRAY
-- ===============================================================

-- cardinality(array): numero de elementos. Conta os itens aninhados de cada
-- pedido sem precisar de UNNEST.
SELECT
    _id,
    cliente,
    total,
    canal,
    cardinality(itens) AS qtd_itens
FROM loja.loja.pedido
ORDER BY _id;

-- UNNEST de ARRAY(ROW(...)) expande o ROW em UMA COLUNA POR CAMPO, entao o
-- alias precisa nomear todas: AS t(sku, qtd). Com AS t(i) o erro e
-- "Column alias list has 1 entries but 't' has 2 columns available".
SELECT p._id, sku, qtd
FROM loja.loja.pedido p
CROSS JOIN UNNEST(p.itens) AS t(sku, qtd)
ORDER BY p._id, sku;

-- ===============================================================
-- 10. Pushdown e query nativa
-- ===============================================================

-- O pushdown aqui e mais modesto que no JDBC: com
-- mongodb.projection-pushdown-enabled=true existe PROJECAO -- so os campos
-- pedidos sao trazidos -- e nao existe pushdown de agregacao nem de join.
SELECT _id, cliente FROM loja.loja.pedido ORDER BY _id;

-- A mesma ideia da query() do Postgres, com a sintaxe do Mongo: o filtro vai
-- cru para a origem, sem parsing do Trino.
SELECT * FROM TABLE(loja.system.query(
    database => 'loja',
    collection => 'pedido',
    filter => '{ "canal": "web" }'
));

-- ===============================================================
-- 11. Escrita
-- ===============================================================

-- O conector Mongo aceita escrita: CREATE TABLE cria a colecao.
CREATE TABLE IF NOT EXISTS loja.loja.evento (
    _id       BIGINT,
    tipo      VARCHAR,
    valor     DOUBLE
);

-- INSERT grava documentos na colecao.
INSERT INTO loja.loja.evento VALUES (1, 'clique', 1.0), (2, 'compra', 150.0);

-- E DELETE tambem funciona -- o que nao e regra entre fontes NoSQL.
DELETE FROM loja.loja.evento WHERE _id = 1;

-- Confere o que sobrou na colecao.
SELECT * FROM loja.loja.evento ORDER BY _id;

-- ===============================================================
-- 12. Tópico como tabela
-- ===============================================================

-- No conector Kafka cada TOPICO vira uma tabela, e o schema NAO vem do Kafka:
-- vem do JSON de descricao montado em /etc/trino/kafka.
SHOW SCHEMAS FROM stream;
SHOW TABLES FROM stream.default;

-- As colunas vieram desse JSON -- inclusive 'cidade', mapeada de um campo
-- ANINHADO do payload (endereco/cidade).
DESCRIBE stream.default.pedido;

-- Le o topico como tabela.
SELECT id, cliente, valor, canal, cidade
FROM stream.default.pedido
ORDER BY id;

-- ===============================================================
-- 13. As colunas internas e a mensagem corrompida
-- ===============================================================

-- Colunas internas do conector: particao, offset, timestamp do registro, se o
-- decoder falhou (_message_corrupt) e o payload cru (_message).
SELECT
    _partition_id,
    _partition_offset,
    _timestamp,
    _message_corrupt,
    _message
FROM stream.default.pedido
ORDER BY _partition_offset;

-- Com uma mensagem malformada no topico, _message_corrupt vira true e as
-- colunas decodificadas vem NULL -- a query NAO falha, o lixo passa adiante
-- silenciosamente. Por isso todo consumo serio filtra por essa coluna.
SELECT count(*) AS mensagens_validas
FROM stream.default.pedido
WHERE NOT _message_corrupt;

-- ===============================================================
-- 14. Não leia a retenção inteira
-- ===============================================================

-- Cada leitura varre o topico do inicio: nao existe cursor nem offset guardado
-- pelo Trino. Este count le tudo.
SELECT count(*) AS total FROM stream.default.pedido;

-- Filtrando por OFFSET: le so o trecho recente.
SELECT count(*) AS ultimas
FROM stream.default.pedido
WHERE _partition_offset >= 2;

-- Filtrando por TIMESTAMP da mensagem, quando o que importa e a janela de tempo.
SELECT count(*) AS ultima_hora
FROM stream.default.pedido
WHERE _timestamp > current_timestamp - INTERVAL '1' HOUR;

-- Agregacao sobre o stream: e um INSTANTANEO, nao uma consulta continua.
SELECT canal, count(*) AS eventos, round(sum(valor), 2) AS total
FROM stream.default.pedido
WHERE NOT _message_corrupt
GROUP BY canal
ORDER BY total DESC;

-- ===============================================================
-- 15. Escrita: e por que o Kafka tem dois catálogos
-- ===============================================================
-- O conector acrescenta 9 colunas INTERNAS a cada tabela. Elas sao a
-- ferramenta de depuracao do bloco 13 -- mas o caminho de ESCRITA nao as
-- aceita na lista de colunas, e o INSERT falha com "Unexpected columns!".
-- Como quem controla isso e uma propriedade de CATALOGO, e nao de sessao, o
-- unico jeito de ter leitura com as internas visiveis E escrita e mapear o
-- mesmo topico duas vezes:
--
--   stream    -> hide-internal-columns=false -> internas no DESCRIBE; LEITURA
--   stream_w  -> hide-internal-columns=true  -> aceita INSERT
--
-- Nao e estilo, e limitacao do conector. Repare que o topico e o MESMO: o que
-- muda e so como cada catalogo apresenta as colunas.

-- Produz uma mensagem pelo catalogo de escrita. A coluna `chave` e a chave
-- Kafka da mensagem, e e ela que decide a particao.
INSERT INTO stream_w.default.pedido (chave, id, cliente, valor, canal, cidade)
VALUES ('k1', 100, 'trino', 10.0, 'api', 'Sao Paulo');

-- Confere a mensagem recem-produzida pelo proprio Trino.
SELECT id, cliente, canal FROM stream.default.pedido WHERE id = 100;
-- ATENCAO: a semantica e AT-LEAST-ONCE. Retentativa do producer duplica, entao
-- o consumidor precisa ser idempotente.

-- ===============================================================
-- 16. Federando as três, e quando parar de federar
-- ===============================================================

-- Uma query tocando as tres familias de fonte ao mesmo tempo -- o ponto da
-- federacao.
SELECT
    (SELECT count(*) FROM vendas.public.pedido)   AS pedidos_postgres,
    (SELECT count(*) FROM loja.loja.pedido)       AS pedidos_mongo,
    (SELECT count(*) FROM stream.default.pedido)  AS eventos_kafka,
    (SELECT count(*) FROM tpch.tiny.orders)       AS pedidos_tpch;

-- Federar toda hora cobra caro: cada execucao vai de novo ao banco
-- operacional, ao Mongo e ao topico inteiro. A saida e MATERIALIZAR.
CREATE SCHEMA IF NOT EXISTS lake.lab;

-- Prepara a copia.
DROP TABLE IF EXISTS lake.lab.pedido_kafka;

-- A copia vai para PARQUET no object storage. Guardar particao e offset e o
-- que permite retomar de onde parou na proxima carga.
CREATE TABLE lake.lab.pedido_kafka WITH (format = 'PARQUET') AS
SELECT
    _partition_id,
    _partition_offset,
    _timestamp AS ingerido_em,
    id, cliente, valor, canal, cidade
FROM stream.default.pedido
WHERE NOT _message_corrupt;

-- Daqui em diante o dashboard consulta a copia, nao a fonte operacional.
SELECT count(*) AS linhas_na_copia FROM lake.lab.pedido_kafka;

-- O arquivo que foi gravado no MinIO.
SELECT DISTINCT "$path" FROM lake.lab.pedido_kafka;

-- O offset mais alto por particao: o marcador de retomada.
SELECT _partition_id, max(_partition_offset) AS ultimo_offset
FROM lake.lab.pedido_kafka
GROUP BY _partition_id
ORDER BY _partition_id;

-- ===============================================================
-- 17. Limpeza
-- ===============================================================

-- Limpeza: cada fonte guarda o que foi criado nela, entao a limpeza tambem e
-- por fonte. O TOPICO do Kafka continua existindo -- quem o apaga e o
-- 'docker compose down -v'.
DROP TABLE IF EXISTS lake.lab.pedido_kafka;
DROP SCHEMA IF EXISTS lake.lab;
DROP TABLE IF EXISTS loja.loja.evento;
DROP TABLE IF EXISTS vendas.lab.destino;
DROP TABLE IF EXISTS vendas.lab.com_pk;
DROP SCHEMA IF EXISTS vendas.lab;
