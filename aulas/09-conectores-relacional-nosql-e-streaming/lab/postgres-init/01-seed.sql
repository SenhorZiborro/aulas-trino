CREATE TABLE cliente (
    id       integer PRIMARY KEY,
    nome     varchar(100) NOT NULL,
    cidade   varchar(100),
    email    varchar(200),
    tags     text[],                 -- array: exige array-mapping
    metadata jsonb,                  -- jsonb -> JSON no Trino
    criado_em timestamptz
);

INSERT INTO cliente VALUES
 (1,'Alice','Sao Paulo','alice@ex.com', ARRAY['vip','web'],  '{"origem":"api"}',  '2026-09-01 10:00:00-03'),
 (2,'Bob','Rio de Janeiro','bob@ex.com', ARRAY['web'],       '{"origem":"loja"}', '2026-09-02 11:00:00-03'),
 (3,'Carol','Belo Horizonte','carol@ex.com', ARRAY['vip'],   '{"origem":"api"}',  '2026-09-03 12:00:00-03');

CREATE TABLE pedido (
    id         integer PRIMARY KEY,
    cliente_id integer REFERENCES cliente(id),
    valor      numeric(12,2) NOT NULL,
    status     varchar(20),
    criado_em  timestamp
);

INSERT INTO pedido
SELECT
    g,
    1 + (g % 3),
    round((random() * 1000)::numeric, 2),
    CASE WHEN g % 4 = 0 THEN 'cancelado' ELSE 'ok' END,
    timestamp '2026-01-01 00:00:00' + (g || ' hours')::interval
FROM generate_series(1, 50000) AS g;

CREATE INDEX idx_pedido_valor ON pedido(valor);

-- Estatisticas: sem ANALYZE na ORIGEM, o CBO do Trino fica sem informacao.
ANALYZE cliente;
ANALYZE pedido;
