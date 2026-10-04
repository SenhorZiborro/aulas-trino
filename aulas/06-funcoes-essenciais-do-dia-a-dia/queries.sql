-- Aula 6 — funções essenciais
-- docker compose exec -it trino trino --catalog tpch --schema tiny

-- ===============================================================
-- 1. Texto: composição
-- ===============================================================

-- Composicao de texto: concat x concat_ws, e o que cada um faz com NULL.
SELECT
    concat('a', '-', 'b')                    AS concat_simples,
    'a' || '-' || 'b'                        AS operador,
    concat('a', CAST(NULL AS VARCHAR), 'b')  AS concat_com_null,   -- NULL
    concat_ws('-', 'a', NULL, 'b')           AS concat_ws_ignora_null;  -- a-b

-- Montando endereço com campos opcionais: o caso real do concat_ws
WITH e(rua, numero, complemento) AS (
    VALUES ('Rua A', '100', 'sala 3'),
           ('Rua B', '200', NULL)
)
SELECT
    concat(rua, ', ', numero, ', ', complemento) AS errado,
    concat_ws(', ', rua, numero, complemento)    AS certo
FROM e;

-- Preenchimento a esquerda e a direita -- como se gera codigo de tamanho fixo.
SELECT lpad('7', 3, '0') AS lpad, rpad('7', 3, '0') AS rpad;

-- ===============================================================
-- 2. Texto: extração e divisão
-- ===============================================================

-- Recorte e substituicao por posicao: substr, replace e overlay.
SELECT
    substr('engenharia', 1, 3)      AS primeiros_tres,   -- eng
    substr('engenharia', 4)         AS do_quarto,        -- enharia
    length('engenharia')            AS tamanho,
    reverse('engenharia')           AS invertido,
    replace('a-b-c', '-', '/')      AS substituido;

-- As quatro formas de quebrar texto: em array, campo a campo, em mapa e em multimapa.
SELECT
    split('a,b,c', ',')             AS como_array,
    split_part('a,b,c', ',', 2)     AS segundo_campo,
    element_at(split('a,b,c', ','), 3) AS terceiro;

-- split_to_map: chave duplicada gera ERRO
SELECT split_to_map('a=1,b=2', ',', '=') AS mapa;
-- Chave repetida em split_to_map: esta query FALHA de proposito.
-- Chave repetida em split_to_map: esta query FALHA de proposito.
-- Chave repetida em split_to_map: esta query FALHA de proposito.
-- SELECT split_to_map('a=1,a=2', ',', '=');  -- ERRO: chave duplicada
SELECT split_to_multimap('a=1,a=2', ',', '=') AS multimapa;

-- ===============================================================
-- 3. Texto: busca, similaridade e Unicode
-- ===============================================================

-- Busca e similaridade: posicao, prefixo/sufixo, e as distancias de edicao.
SELECT
    strpos('engenharia de dados', 'dados')   AS posicao,
    starts_with('engenharia', 'eng')         AS comeca_com,
    ends_with('engenharia', 'ria')           AS termina_com;

-- Fuzzy matching: deduplicação de cadastro
WITH nomes(a, b) AS (
    VALUES ('Silva', 'Silvia'), ('Souza', 'Sousa'), ('Costa', 'Costa')
)
SELECT a, b,
       levenshtein_distance(a, b) AS distancia,
       soundex(a) = soundex(b)    AS foneticamente_igual
FROM nomes;

-- Unicode: code point x caractere visual
SELECT
    length('café')                       AS tamanho_composto,
    length(normalize('café', NFD))       AS tamanho_decomposto,
    normalize('café', NFC) = normalize('cafe' || chr(769), NFC) AS iguais_apos_normalizar;

-- Conversao entre caractere e numero do code point.
SELECT codepoint('A') AS ponto_de_codigo, chr(233) AS caractere;

-- ===============================================================
-- 4. Matemática
-- ===============================================================

-- Divisão inteira trunca
SELECT
    5 / 2                       AS divisao_inteira,      -- 2
    5 / 2.0                     AS divisao_decimal,      -- 2.5
    CAST(5 AS DOUBLE) / 2       AS divisao_double;       -- 2.5

-- Divisão por zero é ERRO, não NULL
-- Divisao por zero e ERRO no Trino, nao NULL -- a query inteira aborta.
-- Divisao por zero e ERRO no Trino, nao NULL: a query inteira aborta.
-- SELECT 1 / 0;
SELECT 1 / NULLIF(0, 0)  AS protegido_por_nullif;        -- NULL
SELECT TRY(1 / 0)        AS protegido_por_try;           -- NULL

-- Aritmetica basica e arredondamento, com o cuidado da divisao inteira.
SELECT
    abs(-7)          AS absoluto,
    ceil(1.2)        AS teto,
    floor(1.8)       AS piso,
    round(2.567, 2)  AS arredondado,
    truncate(2.567)  AS truncado,
    mod(7, 3)        AS resto,
    power(2, 10)     AS potencia,
    sqrt(144)        AS raiz,
    sign(-3)         AS sinal;

-- Histograma sem CASE gigante
SELECT
    width_bucket(totalprice, 0, 500000, 5) AS faixa,
    count(*) AS pedidos
FROM orders
GROUP BY 1
ORDER BY 1;

-- ===============================================================
-- 5. Condicionais
-- ===============================================================

-- CASE pesquisado e CASE simples, lado a lado.
SELECT
    CASE
        WHEN totalprice > 300000 THEN 'alto'
        WHEN totalprice > 100000 THEN 'medio'
        ELSE 'baixo'
    END AS faixa,
    count(*) AS pedidos
FROM orders
GROUP BY 1
ORDER BY 1;

-- Os atalhos condicionais: if, coalesce, nullif, greatest e least.
SELECT
    if(1 > 0, 'sim', 'nao')                  AS condicional_curto,
    coalesce(CAST(NULL AS VARCHAR), 'padrao') AS primeiro_nao_nulo,
    nullif('x', 'x')                          AS null_se_igual,
    greatest(1, 5, 3)                         AS maior,
    least(1, 5, 3)                            AS menor;

-- Divisão segura, o idioma que você vai repetir a vida toda
WITH v(total, qtd) AS (VALUES (100, 4), (50, 0))
SELECT total, qtd, total / NULLIF(qtd, 0) AS media FROM v;

-- ===============================================================
-- 6. Conversão
-- ===============================================================

-- Conversao: CAST falha em dado invalido, TRY_CAST devolve NULL.
SELECT
    CAST('123' AS INTEGER)          AS cast_ok,
    TRY_CAST('abc' AS INTEGER)      AS try_cast_null,
    TRY_CAST('2026-09-05' AS DATE)  AS texto_para_data;

-- SELECT CAST('abc' AS INTEGER);   -- ERRO

-- Padrão de ingestão: TRY_CAST + métrica de qualidade
WITH bruto(valor_texto) AS (
    VALUES ('10'), ('20'), ('abc'), (''), ('30')
)
SELECT
    count(*)                                        AS total,
    count(TRY_CAST(valor_texto AS INTEGER))         AS convertidos,
    count(*) - count(TRY_CAST(valor_texto AS INTEGER)) AS rejeitados,
    round(100.0 * count(TRY_CAST(valor_texto AS INTEGER)) / count(*), 1) AS pct_ok
FROM bruto;

-- Formatacao para leitura humana: format, format_number e typeof.
SELECT
    format('%s tem %d pedidos', 'cliente', 42) AS formatado,
    format_number(1234567)                     AS numero_legivel,
    typeof(1.0)                                AS tipo;

-- ===============================================================
-- 7. Expressões regulares
-- ===============================================================

-- Parsing de log com regex: extrai data, nivel, usuario e codigo de uma linha
-- nao estruturada -- o uso mais comum de regex em engenharia de dados.
WITH logs(linha) AS (
    VALUES
        ('2026-09-05 10:00:01 ERROR user=alice code=500 msg="timeout"'),
        ('2026-09-05 10:00:02 INFO  user=bob   code=200 msg="ok"'),
        ('2026-09-05 10:00:03 ERROR user=carol code=503 msg="unavailable"')
)
SELECT
    regexp_extract(linha, '\d{4}-\d{2}-\d{2}')          AS data,
    regexp_extract(linha, '(ERROR|INFO|WARN)')          AS nivel,
    regexp_extract(linha, 'user=(\w+)', 1)              AS usuario,
    CAST(regexp_extract(linha, 'code=(\d+)', 1) AS INTEGER) AS codigo,
    regexp_like(linha, 'ERROR')                         AS eh_erro
FROM logs;

-- As demais funcoes de regex numa query so: contar, extrair todas, achar
-- posicao da n-esima ocorrencia e dividir pelo padrao.
SELECT
    regexp_count('a1b2c3', '\d')                AS quantos_digitos,
    regexp_extract_all('a1b2c3', '\d')          AS todos_digitos,
    regexp_position('abcabc', 'b')              AS primeira_posicao,
    regexp_position('abcabc', 'b', 1, 2)        AS segunda_ocorrencia,
    regexp_split('a1b22c333d', '\d+')           AS partes;

-- Substituição com referência a grupo de captura
-- Substituicao com grupo de captura: $1, $2 e $3 reinserem o que casou --
-- aqui, reordena a data de ISO para o formato brasileiro.
SELECT regexp_replace('2026-09-05', '(\d{4})-(\d{2})-(\d{2})', '$3/$2/$1') AS data_br;

-- Substituição com LAMBDA sobre os grupos
-- Um regexp_replace com LAMBDA: em vez de texto fixo, uma funcao recebe o grupo
-- capturado e calcula o substituto -- aqui, dobra cada numero encontrado.
-- regexp_replace com LAMBDA: em vez de texto fixo, uma funcao recebe o grupo
-- capturado e calcula o substituto. Aqui, dobra cada numero encontrado.
-- regexp_replace com LAMBDA: em vez de texto fixo, uma funcao recebe o grupo
-- capturado e calcula o substituto. Aqui, dobra cada numero encontrado.
SELECT regexp_replace('preco: 100, taxa: 20', '(\d+)',
                      x -> CAST(CAST(x[1] AS INTEGER) * 2 AS VARCHAR)) AS dobrado;

-- Remoção
SELECT regexp_replace('a1b2c3', '\d') AS sem_digitos;

-- ===============================================================
-- 8. Regex x LIKE: o custo escondido
-- ===============================================================

-- Compare os planos destas duas (aula A4 explica o pushdown)
EXPLAIN SELECT count(*) FROM customer WHERE name LIKE 'Customer#0000001%';
EXPLAIN SELECT count(*) FROM customer WHERE regexp_like(name, '^Customer#0000001');
