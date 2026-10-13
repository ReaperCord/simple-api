'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createSecretProvider, createAwsSecretFetcher } = require('../src/secret');
const { createDb } = require('../src/db');
const { createLogger } = require('../src/logger');
const { loadConfig } = require('../src/config');

const FIVE_MIN = 5 * 60 * 1000;

function fakeFetcher(passwords) {
  const state = { calls: 0 };
  const fn = async () => {
    const password = passwords[Math.min(state.calls, passwords.length - 1)];
    state.calls += 1;
    return JSON.stringify({ username: 'u', password });
  };
  return { fn, state };
}

test('cache: dentro de 5 min so uma chamada ao segredo', async () => {
  let t = 1000;
  const { fn, state } = fakeFetcher(['p1']);
  const provider = createSecretProvider({ fetchSecret: fn, now: () => t });
  assert.equal(await provider.getPassword(), 'p1');
  t += FIVE_MIN - 1;
  assert.equal(await provider.getPassword(), 'p1');
  assert.equal(state.calls, 1);
});

test('cache expira depois de 5 min: segunda chamada ao segredo', async () => {
  let t = 1000;
  const { fn, state } = fakeFetcher(['p1', 'p2']);
  const provider = createSecretProvider({ fetchSecret: fn, now: () => t });
  assert.equal(await provider.getPassword(), 'p1');
  t += FIVE_MIN;
  assert.equal(await provider.getPassword(), 'p2');
  assert.equal(state.calls, 2);
});

test('invalidate() forca releitura', async () => {
  const { fn, state } = fakeFetcher(['p1', 'p2']);
  const provider = createSecretProvider({ fetchSecret: fn, now: () => 1 });
  assert.equal(await provider.getPassword(), 'p1');
  provider.invalidate();
  assert.equal(await provider.getPassword(), 'p2');
  assert.equal(state.calls, 2);
});

test('leituras concorrentes compartilham uma unica chamada', async () => {
  const { fn, state } = fakeFetcher(['p1']);
  const provider = createSecretProvider({ fetchSecret: fn, now: () => 1 });
  const all = await Promise.all([provider.getPassword(), provider.getPassword(), provider.getPassword()]);
  assert.deepEqual(all, ['p1', 'p1', 'p1']);
  assert.equal(state.calls, 1);
});

test('segredo invalido gera erro sem vazar o conteudo', async () => {
  const bad = createSecretProvider({ fetchSecret: async () => 'valor-secreto-nao-json', now: () => 1 });
  await assert.rejects(bad.getPassword(), (err) => !err.message.includes('valor-secreto'));
  const noField = createSecretProvider({ fetchSecret: async () => '{"user":"u"}', now: () => 1 });
  await assert.rejects(noField.getPassword(), /campo password/);
});

// Pool falso: falha com 28P01 enquanto a senha usada for a antiga.
function poolFactory(validPassword, seen) {
  return class FakePool {
    constructor(options) { this.options = options; }
    on() { return this; }
    async query() {
      const used = await this.options.password();
      seen.push(used);
      if (used !== validPassword) {
        throw Object.assign(new Error(`falha de senha para ${used}`), { code: '28P01' });
      }
      return { rows: [{ version: 'v' }] };
    }
    async end() {}
  };
}

const baseEnv = { DB_HOST: 'h', DB_USER: 'u', DB_DATABASE: 'd', DB_SECRET_ARN: 'arn:x', DB_SSLMODE: 'disable' };

test('28P01: invalida o cache e repete UMA vez com a senha nova', async () => {
  const seen = [];
  const { fn, state } = fakeFetcher(['antiga', 'nova']);
  const secretProvider = createSecretProvider({ fetchSecret: fn, now: () => 1 });
  const db = createDb({
    config: loadConfig(baseEnv),
    secretProvider,
    PoolClass: poolFactory('nova', seen),
  });
  const result = await db.query('SELECT 1');
  assert.equal(result.rows[0].version, 'v');
  assert.deepEqual(seen, ['antiga', 'nova']);
  assert.equal(state.calls, 2);
});

test('28P01 duas vezes: erro, sem laco de tentativas', async () => {
  const seen = [];
  const { fn, state } = fakeFetcher(['antiga', 'ainda-antiga', 'nunca-usada']);
  const secretProvider = createSecretProvider({ fetchSecret: fn, now: () => 1 });
  const db = createDb({
    config: loadConfig(baseEnv),
    secretProvider,
    PoolClass: poolFactory('nova', seen),
  });
  await assert.rejects(db.query('SELECT 1'), (err) => err.code === '28P01');
  assert.equal(seen.length, 2);
  assert.equal(state.calls, 2);
});

test('valor do segredo ausente do log quando a consulta falha', async () => {
  const lines = [];
  const logger = createLogger({ level: 'debug', write: (l) => lines.push(l) });
  const { fn } = fakeFetcher(['senha-de-teste-xyz']);
  const secretProvider = createSecretProvider({ fetchSecret: fn, now: () => 1 });
  const db = createDb({
    config: loadConfig(baseEnv),
    logger,
    secretProvider,
    PoolClass: poolFactory('outra', []),
  });
  const { createApp } = require('../src/app');
  const { once } = require('node:events');
  const server = createApp({ db, logger }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/connect`);
    assert.equal(res.status, 503);
    await res.json();
    await new Promise((r) => setImmediate(r));
    assert.equal(lines.join('\n').includes('senha-de-teste-xyz'), false);
  } finally {
    server.close();
  }
});

test('createAwsSecretFetcher: SDK ausente gera erro claro; SDK falso e usado via send', async () => {
  const missing = () => { throw Object.assign(new Error('Cannot find module'), { code: 'MODULE_NOT_FOUND' }); };
  assert.throws(
    () => createAwsSecretFetcher('arn:x', { loadSdk: missing }),
    /@aws-sdk\/client-secrets-manager nao esta instalado/,
  );

  const sent = [];
  const sdk = {
    SecretsManagerClient: class { async send(cmd) { sent.push(cmd); return { SecretString: '{"password":"p"}' }; } },
    GetSecretValueCommand: class { constructor(input) { this.input = input; } },
  };
  const fetcher = createAwsSecretFetcher('arn:segredo', { loadSdk: () => sdk });
  assert.equal(await fetcher(), '{"password":"p"}');
  assert.deepEqual(sent[0].input, { SecretId: 'arn:segredo' });
});
