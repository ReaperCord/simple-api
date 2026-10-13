'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const { once } = require('node:events');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { createDb } = require('../src/db');
const { createLogger } = require('../src/logger');

const SENHA = 'senha-de-teste-xyz';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

async function start(db, level = 'info') {
  const lines = [];
  const logger = createLogger({ level, write: (l) => lines.push(l) });
  const server = createApp({ db, logger }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { server, lines, base: `http://127.0.0.1:${server.address().port}` };
}

const okDb = { query: async () => ({ rows: [{ version: 'v' }] }) };

test('gera UUID quando nao ha x-request-id e devolve o header', async () => {
  const { server, base } = await start(okDb);
  try {
    const res = await fetch(`${base}/`);
    const body = await res.json();
    assert.match(body.request_id, UUID);
    assert.equal(res.headers.get('x-request-id'), body.request_id);
  } finally {
    server.close();
  }
});

test('reaproveita x-request-id valido', async () => {
  const { server, base } = await start(okDb);
  try {
    const res = await fetch(`${base}/`, { headers: { 'x-request-id': 'abc-123_X.y:z' } });
    const body = await res.json();
    assert.equal(body.request_id, 'abc-123_X.y:z');
    assert.equal(res.headers.get('x-request-id'), 'abc-123_X.y:z');
  } finally {
    server.close();
  }
});

test('x-request-id malformado ou longo demais e substituido por UUID', async () => {
  const { server, base } = await start(okDb);
  try {
    for (const bad of ['tem espaco', 'a'.repeat(129), '<script>']) {
      const res = await fetch(`${base}/`, { headers: { 'x-request-id': bad } });
      const body = await res.json();
      assert.match(body.request_id, UUID, `valor: ${bad}`);
    }
  } finally {
    server.close();
  }
});

test('requisicoes concorrentes recebem request_id diferentes', async () => {
  const { server, base } = await start(okDb);
  try {
    const bodies = await Promise.all(
      Array.from({ length: 20 }, () => fetch(`${base}/`).then((r) => r.json())),
    );
    assert.equal(new Set(bodies.map((b) => b.request_id)).size, 20);
  } finally {
    server.close();
  }
});

test('log por requisicao e JSON com ts, level, msg, method, path, status, duration_ms, request_id', async () => {
  const { server, lines, base } = await start(okDb);
  try {
    const res = await fetch(`${base}/?segredo=valor-na-query`);
    await res.json();
    await new Promise((r) => setImmediate(r));
    const entry = JSON.parse(lines.at(-1));
    for (const key of ['ts', 'level', 'msg', 'method', 'path', 'status', 'duration_ms', 'request_id']) {
      assert.ok(key in entry, `campo ausente: ${key}`);
    }
    assert.equal(entry.method, 'GET');
    assert.equal(entry.path, '/');
    assert.equal(entry.status, 200);
    assert.equal(lines.join('').includes('valor-na-query'), false);
  } finally {
    server.close();
  }
});

test('LOG_LEVEL=error suprime o log por requisicao (info)', async () => {
  const { server, lines, base } = await start(okDb, 'error');
  try {
    await (await fetch(`${base}/`)).json();
    await new Promise((r) => setImmediate(r));
    assert.equal(lines.length, 0);
  } finally {
    server.close();
  }
});

test('erro bruto do banco nao vai para o log: so name e code', async () => {
  const raw = Object.assign(new Error(`password authentication failed for ${SENHA} em 10.0.0.5`), {
    code: '28P01',
    detail: SENHA,
  });
  const { server, lines, base } = await start({ query: async () => { throw raw; } });
  try {
    const res = await fetch(`${base}/connect`);
    assert.equal(res.status, 503);
    await res.json();
    await new Promise((r) => setImmediate(r));
    const all = lines.join('\n');
    assert.equal(all.includes(SENHA), false);
    assert.equal(all.includes('10.0.0.5'), false);
    assert.equal(all.includes('stack'), false);
    const errLine = lines.map((l) => JSON.parse(l)).find((e) => e.err);
    assert.deepEqual(errLine.err, { name: 'Error', code: '28P01' });
  } finally {
    server.close();
  }
});

test('senha ausente de todo o log com banco real falhando (ECONNREFUSED)', async () => {
  // porta livre e fechada: a conexao e recusada na hora
  const probe = net.createServer().listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = probe.address().port;
  probe.close();
  await once(probe, 'close');

  const config = loadConfig({
    DB_HOST: '127.0.0.1',
    DB_PORT: String(port),
    DB_USER: 'u',
    DB_DATABASE: 'd',
    DB_PASSWORD: SENHA,
    DB_SSLMODE: 'disable',
  });
  const lines = [];
  const logger = createLogger({ level: 'debug', write: (l) => lines.push(l) });
  const db = createDb({ config, logger });
  const server = createApp({ db, logger }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/connect`);
    assert.equal(res.status, 503);
    await res.json();
    await new Promise((r) => setImmediate(r));
    const all = lines.join('\n');
    assert.ok(lines.length > 0);
    assert.equal(all.includes(SENHA), false);
    assert.equal(all.includes(`127.0.0.1:${port}`), false);
    assert.equal(all.includes('ECONNREFUSED') || all.includes('"err"'), true);
  } finally {
    server.close();
    await db.end();
  }
});
