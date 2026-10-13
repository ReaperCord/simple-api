'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../src/app');
const { createLogger } = require('../src/logger');

async function start(db) {
  const lines = [];
  const logger = createLogger({ write: (l) => lines.push(l) });
  const server = createApp({ db, logger }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { server, lines, base: `http://127.0.0.1:${server.address().port}` };
}

test('GET / retorna 200 e "API OK!" sem tocar no banco', async () => {
  const db = { query: async () => { throw new Error('nao deveria ser chamado'); } };
  const { server, base } = await start(db);
  try {
    const res = await fetch(`${base}/`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.message, 'API OK!');
    assert.equal(typeof body.request_id, 'string');
  } finally {
    server.close();
  }
});

test('GET /connect retorna 200 com a versao do banco', async () => {
  const db = { query: async () => ({ rows: [{ version: 'PostgreSQL 16.4 (teste)' }] }) };
  const { server, base } = await start(db);
  try {
    const res = await fetch(`${base}/connect`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.message, 'Conectado ao banco');
    assert.equal(body.version, 'PostgreSQL 16.4 (teste)');
    assert.equal(typeof body.request_id, 'string');
  } finally {
    server.close();
  }
});

test('GET /connect retorna 503 com mensagem generica quando o banco falha', async () => {
  const db = { query: async () => { throw new Error('connect ECONNREFUSED 10.0.0.5:5432'); } };
  const { server, base } = await start(db);
  try {
    const res = await fetch(`${base}/connect`);
    assert.equal(res.status, 503);
    const body = await res.json();
    assert.equal(body.message, 'Erro ao se conectar ao banco');
    assert.equal(JSON.stringify(body).includes('10.0.0.5'), false);
  } finally {
    server.close();
  }
});
