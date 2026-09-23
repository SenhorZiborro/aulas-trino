-- Aula 4 — tipos de dados
-- docker compose exec -it trino trino

-- ===============================================================
-- 1. Inteiros: faixas e literais
-- ===============================================================

SELECT
    CAST(127 AS TINYINT)        AS tinyint_max,
    CAST(32767 AS SMALLINT)     AS smallint_max,
    CAST(2147483647 AS INTEGER) AS integer_max,
    9223372036854775807         AS bigint_max;

-- Literais em outras bases e separador de legibilidade
SELECT 0xFF AS hexa, 0o17 AS octal, 0b1010 AS binario, 1_000_000 AS com_underscore;

-- Overflow é ERRO, não truncamento silencioso: esta query DEVE falhar
-- SELECT CAST(128 AS TINYINT);

-- O tipo do resultado importa: count(*) é BIGINT
SELECT typeof(count(*)) AS tipo_do_count FROM tpch.tiny.nation;

-- ===============================================================
-- 2. Ponto flutuante x decimal: o teste do dinheiro
-- ===============================================================

SELECT
    0.1E0 + 0.2E0                AS double_soma,     -- ponto flutuante
    0.1E0 + 0.2E0 = 0.3E0        AS double_igual,    -- false
    DECIMAL '0.1' + DECIMAL '0.2' AS decimal_soma,
    DECIMAL '0.1' + DECIMAL '0.2' = DECIMAL '0.3' AS decimal_igual;  -- true

-- Valores especiais de ponto flutuante
SELECT infinity() AS inf, -infinity() AS menos_inf, nan() AS nao_numero;

-- A armadilha do scale default: DECIMAL(10) é DECIMAL(10,0)
SELECT
    CAST(1.99 AS DECIMAL(10))    AS scale_default_zero,   -- 2
    CAST(1.99 AS DECIMAL(10,2))  AS scale_explicito;      -- 1.99

SELECT typeof(CAST(1.99 AS DECIMAL(10))) AS tipo;

-- ===============================================================
-- 3. Texto: VARCHAR, CHAR e a pegadinha do padding
-- ===============================================================

SELECT
    length(CAST('ab' AS CHAR(5)))     AS char_length,     -- 5
    length(CAST('ab' AS VARCHAR(5)))  AS varchar_length;  -- 2

-- CHAR compara com padding; ao virar VARCHAR os espaços à direita somem
SELECT
    CAST('ab' AS CHAR(5)) = CAST('ab' AS CHAR(2))        AS char_vs_char,
    CAST(CAST('ab' AS CHAR(5)) AS VARCHAR) = 'ab'        AS char_para_varchar;

-- Unicode com prefixo U&
SELECT U&'S\00E3o Paulo' AS cidade;

-- Aspas simples = string; aspas duplas = identificador
SELECT 'user' AS texto_literal;
-- SELECT "user";  -- procura uma COLUNA chamada user: falha aqui

-- Binário
SELECT X'65683F' AS bytes, from_utf8(X'65683F') AS texto;

-- ===============================================================
-- 4. Data e hora: precisão e fuso
-- ===============================================================

SELECT
    DATE '2026-09-05'                              AS data,
    TIME '10:30:00.123'                            AS hora,
    TIMESTAMP '2026-09-05 10:30:00.123'            AS ts_sem_fuso,
    TIMESTAMP '2026-09-05 10:30:00.123 America/Sao_Paulo' AS ts_com_fuso;

-- Precisao: o TIPO sem precisao e TIMESTAMP(3); o LITERAL herda os digitos escritos
SELECT
    typeof(CAST('2026-09-05 10:30:00.123456' AS TIMESTAMP)) AS tipo_sem_precisao,  -- timestamp(3)
    typeof(TIMESTAMP '2026-09-05 10:30:00.123456')          AS literal_6_digitos,  -- timestamp(6)
    typeof(TIMESTAMP '2026-09-05 10:30:00')                 AS literal_0_digitos,  -- timestamp(0)
    CAST('2026-09-05 10:30:00.123456' AS TIMESTAMP)         AS valor_truncado;     -- .123

-- Cast para menos precisão ARREDONDA; para mais, completa com zeros
SELECT
    CAST(TIMESTAMP '2026-09-05 10:30:00.567' AS TIMESTAMP(0)) AS arredondado,
    CAST(TIMESTAMP '2026-09-05 10:30:00.5'   AS TIMESTAMP(6)) AS com_zeros;

-- Intervalos
SELECT
    INTERVAL '2' YEAR                AS anos,
    INTERVAL '3' MONTH               AS meses,
    INTERVAL '1' DAY + INTERVAL '2' HOUR AS dia_e_horas,
    DATE '2026-01-31' + INTERVAL '1' MONTH AS soma_mes;

-- ===============================================================
-- 5. Estruturais: ARRAY, MAP, ROW
-- ===============================================================

-- Array é 1-based
SELECT
    ARRAY[10, 20, 30]        AS arr,
    ARRAY[10, 20, 30][1]     AS primeiro,
    cardinality(ARRAY[10,20,30]) AS tamanho;

-- SELECT ARRAY[10,20,30][0];  -- ERRO: índice começa em 1

SELECT
    MAP(ARRAY['a','b'], ARRAY[1,2])         AS mapa,
    MAP(ARRAY['a','b'], ARRAY[1,2])['a']    AS valor_de_a;

-- ROW: acesso posicional e nomeado
SELECT
    ROW(1, 'x')                                          AS row_anonima,
    CAST(ROW(1, 'x') AS ROW(id INTEGER, nome VARCHAR)).nome AS nome,
    CAST(ROW(1, 'x') AS ROW(id INTEGER, nome VARCHAR))[1]   AS por_posicao;

-- Aninhamento
SELECT CAST(
    ROW(1, ARRAY['a','b'], MAP(ARRAY['k'], ARRAY[10]))
    AS ROW(id INTEGER, tags ARRAY(VARCHAR), props MAP(VARCHAR, INTEGER))
) AS registro;

-- ===============================================================
-- 6. Rede, UUID e VARIANT
-- ===============================================================

SELECT
    IPADDRESS '10.0.0.1'                                 AS ipv4,
    IPADDRESS '2001:db8::1'                              AS ipv6,
    UUID '12151fd2-7586-11e9-8f9e-2a86e4085a59'          AS id;

-- IPv4 dentro de faixa IPv6-mapped (efeito do mapeamento RFC 4291)
SELECT CAST(IPADDRESS '10.0.0.1' AS VARCHAR) AS texto;

SELECT typeof(JSON '{"a":1}') AS tipo_json;

-- ===============================================================
-- 7. typeof: a ferramenta de diagnóstico
-- ===============================================================

SELECT
    typeof(1)               AS inteiro_literal,
    typeof(1.0)             AS decimal_literal,
    typeof(1.0E0)           AS double_literal,
    typeof('texto')         AS texto_literal,
    typeof(ARRAY[1,2])      AS array_literal,
    typeof(current_date)    AS data,
    typeof(now())           AS agora;

-- ===============================================================
-- 8. Type mapping na prática: os tipos que o conector expõe
-- ===============================================================

SELECT column_name, data_type
FROM tpch.information_schema.columns
WHERE table_schema = 'tiny' AND table_name = 'lineitem'
ORDER BY ordinal_position;

-- ===============================================================
-- 9. Escrita: o que o conector aceita
-- ===============================================================

CREATE SCHEMA IF NOT EXISTS memory.lab;

CREATE TABLE memory.lab.tipos (
    id          UUID,
    quantidade  INTEGER,
    valor       DECIMAL(12,2),
    aproximado  DOUBLE,
    nome        VARCHAR,
    codigo      CHAR(3),
    ativo       BOOLEAN,
    criado_em   TIMESTAMP(6),
    criado_tz   TIMESTAMP(3) WITH TIME ZONE,
    tags        ARRAY(VARCHAR),
    atributos   MAP(VARCHAR, VARCHAR),
    endereco    ROW(rua VARCHAR, numero INTEGER),
    origem      IPADDRESS
);

INSERT INTO memory.lab.tipos VALUES (
    UUID '12151fd2-7586-11e9-8f9e-2a86e4085a59',
    10,
    DECIMAL '1234.56',
    1234.56E0,
    'pedido teste',
    'BRL',
    true,
    TIMESTAMP '2026-09-05 10:30:00.123456',
    TIMESTAMP '2026-09-05 10:30:00.123 America/Sao_Paulo',
    ARRAY['a','b'],
    MAP(ARRAY['origem'], ARRAY['api']),
    ROW('Rua X', 100),
    IPADDRESS '10.0.0.1'
);

SELECT * FROM memory.lab.tipos;

DESCRIBE memory.lab.tipos;

-- ===============================================================
-- 10. Limpeza
-- ===============================================================

DROP TABLE IF EXISTS memory.lab.tipos;
