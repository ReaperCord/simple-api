'use strict';

// Integracao contra Postgres real (SCRAM, como no RDS). Auto-skip sem
// INTEGRATION_DB_HOST. Variaveis: INTEGRATION_DB_HOST, INTEGRATION_DB_PORT
// (5432), INTEGRATION_DB_USER, INTEGRATION_DB_PASSWORD, INTEGRATION_DB_DATABASE.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createDb } = require('../src/db');
const { loadConfig } = require('../src/config');
const { createLogger } = require('../src/logger');
const { createSecretProvider } = require('../src/secret');

const env = process.env;
const enabled = Boolean(env.INTEGRATION_DB_HOST);
const skip = enabled ? false : 'defina INTEGRATION_DB_HOST para rodar a integracao';

function makeConfig(extra = {}) {
  return loadConfig({
    DB_HOST: env.INTEGRATION_DB_HOST,
    DB_PORT: env.INTEGRATION_DB_PORT || '5432',
    DB_USER: env.INTEGRATION_DB_USER,
    DB_DATABASE: env.INTEGRATION_DB_DATABASE,
    DB_PASSWORD: env.INTEGRATION_DB_PASSWORD,
    DB_SSLMODE: 'disable',
    DB_POOL_MAX: '2',
    ...extra,
  });
}

const logger = createLogger({ write: () => {} });

test('SELECT version() no Postgres real', { skip }, async () => {
  const db = createDb({ config: makeConfig(), logger });
  try {
    const result = await db.query('SELECT version()');
    assert.match(result.rows[0].version, /PostgreSQL/);
  } finally {
    await db.end();
  }
});

test('statement_timeout/query_timeout encerram consulta lenta em < 4 s', { skip, timeout: 8000 }, async () => {
  const db = createDb({ config: makeConfig(), logger });
  try {
    const started = Date.now();
    await assert.rejects(db.query('SELECT pg_sleep(10)'));
    assert.ok(Date.now() - started < 4000);
  } finally {
    await db.end();
  }
});

test('senha errada (SCRAM) gera 28P01; com segredo rotacionado, retry unico recupera', { skip, timeout: 10000 }, async () => {
  const passwords = ['senha-errada-de-teste', env.INTEGRATION_DB_PASSWORD];
  let calls = 0;
  const secretProvider = createSecretProvider({
    fetchSecret: async () => JSON.stringify({ password: passwords[Math.min(calls++, 1)] }),
  });
  const db = createDb({ config: makeConfig({ DB_PASSWORD: '', DB_SECRET_ARN: 'arn:teste' }), logger, secretProvider });
  try {
    const result = await db.query('SELECT 1 AS ok');
    assert.equal(result.rows[0].ok, 1);
    assert.equal(calls, 2);
  } finally {
    await db.end();
  }
});

test('sem retry (senha estatica errada) o erro 28P01 chega ao chamador', { skip, timeout: 10000 }, async () => {
  const db = createDb({ config: makeConfig({ DB_PASSWORD: 'senha-errada-de-teste' }), logger });
  try {
    await assert.rejects(db.query('SELECT 1'), (err) => err.code === '28P01');
  } finally {
    await db.end();
  }
});
