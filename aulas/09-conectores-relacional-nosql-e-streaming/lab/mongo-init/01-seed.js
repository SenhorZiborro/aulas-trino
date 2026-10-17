// Executado na inicializacao do container Mongo.
db = db.getSiblingDB('loja');

db.pedido.insertMany([
  { _id: 1, cliente: 'alice', total: 150.50, itens: [ { sku: 'A1', qtd: 2 }, { sku: 'B2', qtd: 1 } ],
    canal: 'web',  criado_em: new Date('2026-09-01T10:00:00Z') },
  { _id: 2, cliente: 'bob',   total: 89.90,  itens: [ { sku: 'C3', qtd: 5 } ],
    canal: 'app',  criado_em: new Date('2026-09-02T11:00:00Z') },
  { _id: 3, cliente: 'carol', total: 320.00, itens: [ { sku: 'A1', qtd: 1 } ],
    canal: 'web',  criado_em: new Date('2026-09-03T12:00:00Z'), cupom: 'PROMO10' }
]);

// Documento com campo EXTRA (cupom) so no ultimo: o schema inferido pode
// nao incluir esse campo. E exatamente o ponto da aula.

db.cliente.insertMany([
  { _id: 1, nome: 'alice', cidade: 'Sao Paulo',      vip: true  },
  { _id: 2, nome: 'bob',   cidade: 'Rio de Janeiro', vip: false },
  { _id: 3, nome: 'carol', cidade: 'Belo Horizonte', vip: true  }
]);
