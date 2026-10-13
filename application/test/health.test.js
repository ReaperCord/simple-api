'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../src/app');
const { createLogger } = require('../src/logger');

async function start(db) {
  const logger = createLogger({ write: () => {} });
  const server = createApp({ db, logger }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

const throwingDb = { query: async () => { throw new Error('banco fora do ar'); } };

test('GET /health retorna 200 {status:"ok"} mesmo com db que lanca', async () => {
  const { server, base } = await start(throwingDb);
  try {
    const res = await fetch(`${base}/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'ok' });
  } finally {
    server.close();
  }
});

test('resposta nao traz o header x-powered-by', async () => {
  const { server, base } = await start(throwingDb);
  try {
    const res = await fetch(`${base}/`);
    assert.equal(res.headers.has('x-powered-by'), false);
    await res.json();
  } finally {
    server.close();
  }
});

test('corpo JSON maior que 16 kb retorna 413 generico', async () => {
  const { server, base } = await start(throwingDb);
  try {
    const res = await fetch(`${base}/`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ x: 'a'.repeat(20 * 1024) }),
    });
    assert.equal(res.status, 413);
    const body = await res.json();
    assert.equal(body.message, 'Corpo da requisicao muito grande');
    assert.equal(typeof body.request_id, 'string');
  } finally {
    server.close();
  }
});

test('JSON invalido retorna 400 generico, sem stack', async () => {
  const { server, base } = await start(throwingDb);
  try {
    const res = await fetch(`${base}/`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{invalido',
    });
    assert.equal(res.status, 400);
    const text = await res.text();
    assert.equal(text.includes('SyntaxError'), false);
    assert.equal(text.includes('node_modules'), false);
  } finally {
    server.close();
  }
});
