-- Três tabelas no schema publico: duas liberadas e uma sensível.
CREATE SCHEMA publico;

CREATE TABLE publico.cliente (
    id       int PRIMARY KEY,
    nome     text,
    segmento text
);
INSERT INTO publico.cliente VALUES
    (1, 'Acme',     'corporativo'),
    (2, 'Bodega',   'varejo'),
    (3, 'Cimento',  'corporativo'),
    (4, 'Doceria',  'varejo');

CREATE TABLE publico.pedido (
    id         int PRIMARY KEY,
    cliente_id int,
    valor      numeric(10,2),
    status     text
);
INSERT INTO publico.pedido
SELECT i,
       1 + (i % 4),
       (100 + i * 7)::numeric(10,2),
       CASE WHEN i % 5 = 0 THEN 'cancelado' ELSE 'ok' END
FROM generate_series(1, 40) AS s(i);

-- A tabela que ninguém da trilha deve ler pelo Trino.
CREATE TABLE publico.salario (
    id        int PRIMARY KEY,
    pessoa    text,
    bruto     numeric(10,2)
);
INSERT INTO publico.salario VALUES
    (1, 'Ana',   9500.00),
    (2, 'Beto', 12300.00),
    (3, 'Carla',18750.00);

-- O usuário de conexão do catálogo: SELECT só em cliente e pedido.
CREATE USER trino_leitura WITH PASSWORD 'leitura';
GRANT USAGE ON SCHEMA publico TO trino_leitura;
GRANT SELECT ON publico.cliente, publico.pedido TO trino_leitura;
