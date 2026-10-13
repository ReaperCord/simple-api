'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const path = require('node:path');
const { once } = require('node:events');
const { spawn } = require('node:child_process');
const { shutdown } = require('../src/index');
const { createLogger } = require('../src/logger');

const entry = path.join(__dirname, '..', 'src', 'index.js');
const logger = createLogger({ write: () => {} });

// Garante que o runner nao termine antes de um timer unref() disparar.
function keepAlive(ms) {
  const t = setTimeout(() => {}, ms);
  return () => clearTimeout(t);
}

test('shutdown: server.close -> db.end -> exit(0), nessa ordem', async () => {
  const calls = [];
  const server = {
    close: (cb) => { calls.push('server.close'); setImmediate(cb); },
    closeIdleConnections: () => calls.push('closeIdleConnections'),
  };
  const db = { end: async () => { calls.push('db.end'); } };
  const code = await new Promise((exit) => {
    shutdown({ server, db, logger, timeoutMs: 1000, exit });
  });
  assert.equal(code, 0);
  assert.deepEqual(calls, ['server.close', 'closeIdleConnections', 'db.end']);
});

test('shutdown: se algo trava, o timer de seguranca sai com codigo 1', async () => {
  const stop = keepAlive(3000);
  const server = { close: () => {} }; // nunca chama o callback
  const db = { end: async () => {} };
  const code = await new Promise((exit) => {
    shutdown({ server, db, logger, timeoutMs: 50, exit });
  });
  stop();
  assert.equal(code, 1);
});

test('shutdown: falha em db.end sai com codigo 1', async () => {
  const server = { close: (cb) => setImmediate(cb) };
  const db = { end: async () => { throw new Error('falha'); } };
  const code = await new Promise((exit) => {
    shutdown({ server, db, logger, timeoutMs: 1000, exit });
  });
  assert.equal(code, 1);
});

test('startup com DB_SSLMODE invalido sai com 1 e mensagem clara', async () => {
  const child = spawn(process.execPath, [entry], {
    env: { PATH: process.env.PATH, DB_PASSWORD: 'x', DB_SSLMODE: 'require' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d; });
  child.stderr.on('data', (d) => { out += d; });
  const [code] = await once(child, 'exit');
  assert.equal(code, 1);
  assert.match(out, /DB_SSLMODE invalido/);
});

test('startup com verify-full sem DB_SSL_CA_FILE sai com 1', async () => {
  const child = spawn(process.execPath, [entry], {
    env: { PATH: process.env.PATH, DB_PASSWORD: 'x' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d; });
  const [code] = await once(child, 'exit');
  assert.equal(code, 1);
  assert.match(out, /DB_SSL_CA_FILE/);
});

// No Windows, child.kill('SIGTERM') encerra o processo sem rodar o handler.
test('processo real: SIGTERM encerra com exit 0', { skip: process.platform === 'win32', timeout: 15000 }, async () => {
  const probe = net.createServer().listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const port = probe.address().port;
  probe.close();
  await once(probe, 'close');

  const child = spawn(process.execPath, [entry], {
    env: { PATH: process.env.PATH, API_PORT: String(port), DB_PASSWORD: 'x', DB_SSLMODE: 'disable' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  const started = new Promise((resolve) => {
    child.stdout.on('data', (d) => {
      out += d;
      if (out.includes('API iniciada')) resolve();
    });
  });
  await started;
  child.kill('SIGTERM');
  const [code] = await once(child, 'exit');
  assert.equal(code, 0);
});
