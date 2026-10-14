'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { prewarm } = require('../src/prewarm');
const { createLogger } = require('../src/logger');

function capture() {
  const lines = [];
  return { lines, logger: createLogger({ write: (l) => lines.push(JSON.parse(l)) }) };
}

test('gera o token e abre a primeira conexao, nessa ordem', async () => {
  const order = [];
  const provider = { getPassword: async () => { order.push('token'); return 't'; } };
  const db = { query: async (q) => { order.push(`query:${q}`); return { rows: [] }; } };
  const { lines, logger } = capture();
  assert.equal(await prewarm({ provider, db, logger }), true);
  assert.deepEqual(order, ['token', 'query:SELECT 1']);
  assert.equal(lines[0].msg, 'pre-aquecimento do token IAM concluido');
});

test('falha ao gerar o token: aviso, sem lancar e sem tocar no banco', async () => {
  let queried = false;
  const provider = { getPassword: async () => { throw Object.assign(new Error('sem credenciais'), { code: 'CredentialsProviderError' }); } };
  const db = { query: async () => { queried = true; return { rows: [] }; } };
  const { lines, logger } = capture();
  assert.equal(await prewarm({ provider, db, logger }), false);
  assert.equal(queried, false);
  assert.equal(lines[0].level, 'warn');
});

test('falha na conexao (ex.: usuario ainda nao criado): aviso com so name/code, nunca a mensagem', async () => {
  const provider = { getPassword: async () => 'token-secreto-abc' };
  const db = { query: async () => { throw Object.assign(new Error('password authentication failed for user "app_connect" token-secreto-abc'), { code: '28P01', name: 'error' }); } };
  const { lines, logger } = capture();
  assert.equal(await prewarm({ provider, db, logger }), false);
  const raw = JSON.stringify(lines);
  assert.equal(lines[0].level, 'warn');
  assert.deepEqual(lines[0].err, { name: 'error', code: '28P01' });
  assert.ok(!raw.includes('token-secreto-abc'), 'o token nao pode aparecer no log');
  assert.ok(!raw.includes('app_connect'), 'a mensagem do driver nao pode aparecer no log');
});
