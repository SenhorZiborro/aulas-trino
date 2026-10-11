CREATE TABLE cliente (
    id     integer PRIMARY KEY,
    nome   varchar(100),
    cidade varchar(100)
);

INSERT INTO cliente VALUES
    (1, 'Alice', 'Sao Paulo'),
    (2, 'Bob',   'Rio de Janeiro'),
    (3, 'Carol', 'Belo Horizonte');

CREATE TABLE pedido (
    id         integer PRIMARY KEY,
    cliente_id integer REFERENCES cliente(id),
    valor      numeric(12,2),
    criado_em  timestamp
);

INSERT INTO pedido VALUES
    (1, 1, 150.50, timestamp '2026-09-01 10:00:00'),
    (2, 1,  89.90, timestamp '2026-09-02 11:00:00'),
    (3, 2, 320.00, timestamp '2026-09-03 12:00:00');
