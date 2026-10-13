'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createDb } = require('../src/db');
const { loadConfig } = require('../src/config');
const { createLogger } = require('../src/logger');

class FakePool {
  constructor(options) {
    this.options = options;
    this.handlers = {};
    this.ended = false;
    FakePool.last = this;
  }
  on(event, fn) { this.handlers[event] = fn; return this; }
  async query() { return { rows: [{ version: 'fake' }] }; }
  async end() { this.ended = true; }
}

const env = { DB_HOST: 'h', DB_USER: 'u', DB_DATABASE: 'd', DB_PASSWORD: 'senha-de-teste-xyz' };

test('Pool recebe max, timeouts de conexao/ocioso e de statement/query', () => {
  const config = loadConfig({ ...env, DB_SSLMODE: 'disable', DB_POOL_MAX: '3' });
  createDb({ config, PoolClass: FakePool });
  const o = FakePool.last.options;
  assert.equal(o.max, 3);
  assert.equal(o.connectionTimeoutMillis, 2000);
  assert.equal(o.idleTimeoutMillis, 10000);
  assert.equal(o.statement_timeout, 3000);
  assert.equal(o.query_timeout, 3000);
  assert.equal(o.host, 'h');
  assert.equal(o.password, 'senha-de-teste-xyz');
});

test('DB_SSLMODE=disable nao passa ssl ao Pool', () => {
  const config = loadConfig({ ...env, DB_SSLMODE: 'disable' });
  createDb({ config, PoolClass: FakePool });
  assert.equal('ssl' in FakePool.last.options, false);
});

test('verify-full passa ca do arquivo e rejectUnauthorized true', () => {
  const config = loadConfig({ ...env, DB_SSL_CA_FILE: '/certs/rds-global-bundle.pem' });
  const asked = [];
  createDb({
    config,
    PoolClass: FakePool,
    readFile: (file) => { asked.push(file); return 'PEM-DE-TESTE'; },
  });
  assert.deepEqual(asked, ['/certs/rds-global-bundle.pem']);
  assert.deepEqual(FakePool.last.options.ssl, { ca: 'PEM-DE-TESTE', rejectUnauthorized: true });
});

test('rejectUnauthorized nunca e false em nenhum modo', () => {
  for (const sslMode of ['verify-full', 'disable']) {
    const config = loadConfig({ ...env, DB_SSLMODE: sslMode, DB_SSL_CA_FILE: '/c.pem' });
    createDb({ config, PoolClass: FakePool, readFile: () => 'PEM' });
    const ssl = FakePool.last.options.ssl;
    assert.notEqual(ssl && ssl.rejectUnauthorized, false);
  }
});

test('pool.on("error") registra so name/code, nunca o objeto bruto', () => {
  const lines = [];
  const logger = createLogger({ write: (l) => lines.push(l) });
  const config = loadConfig({ ...env, DB_SSLMODE: 'disable' });
  createDb({ config, logger, PoolClass: FakePool });
  const raw = Object.assign(new Error('senha-de-teste-xyz em 10.0.0.5'), { code: 'ECONNRESET' });
  FakePool.last.handlers.error(raw);
  assert.equal(lines.length, 1);
  const entry = JSON.parse(lines[0]);
  assert.deepEqual(entry.err, { name: 'Error', code: 'ECONNRESET' });
  assert.equal(lines[0].includes('senha-de-teste-xyz'), false);
  assert.equal(lines[0].includes('10.0.0.5'), false);
});

test('end() encerra o pool', async () => {
  const config = loadConfig({ ...env, DB_SSLMODE: 'disable' });
  const db = createDb({ config, PoolClass: FakePool });
  await db.end();
  assert.equal(FakePool.last.ended, true);
});
