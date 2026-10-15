'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const { once } = require('node:events');
const { spawn } = require('node:child_process');
const { createApp } = require('../src/app');
const { createDrain } = require('../src/drain');
const { createLogger } = require('../src/logger');

const entry = path.join(__dirname, '..', 'src', 'index.js');
const logger = createLogger({ write: () => {} });
const db = { query: async () => ({ rows: [{ version: 'PostgreSQL 16 (teste)' }] }) };

// GET com agente keep-alive; devolve o header Connection da resposta (o fetch do Node o esconde).
function get(port, pathName, agent) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port, path: pathName, agent }, (res) => {
      res.resume();
      res.on('end', () => resolve({ status: res.statusCode, connection: res.headers.connection }));
    });
    req.on('error', reject);
  });
}

async function start(drain) {
  const server = createApp({ db, logger, drain }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { server, port: server.address().port };
}

test('drain: start() so devolve true na primeira chamada', () => {
  const d = createDrain();
  assert.equal(d.isActive(), false);
  assert.equal(d.start(), true);
  assert.equal(d.start(), false);
  assert.equal(d.isActive(), true);
});

test('sem drenagem: keep-alive; com drenagem: Connection: close em todas as rotas', async () => {
  const drain = createDrain();
  const { server, port } = await start(drain);
  const agent = new http.Agent({ keepAlive: true });
  try {
    const antes = await get(port, '/health', agent);
    assert.equal(antes.status, 200);
    assert.equal(antes.connection, 'keep-alive');

    drain.start();
    for (const p of ['/health', '/', '/connect', '/nao-existe']) {
      const r = await get(port, p, agent);
      assert.equal(r.connection, 'close', `rota ${p}`);
    }
  } finally {
    agent.destroy();
    server.close();
  }
});

test('createApp sem drain continua funcionando (uso fora do index, como nos outros testes)', async () => {
  const server = createApp({ db, logger }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  const agent = new http.Agent({ keepAlive: true });
  try {
    const r = await get(server.address().port, '/health', agent);
    assert.equal(r.status, 200);
    assert.equal(r.connection, 'keep-alive');
  } finally {
    agent.destroy();
    server.close();
  }
});

// No Windows nao ha SIGUSR2.
test('processo real: SIGUSR2 liga a drenagem e SIGTERM ainda encerra com exit 0', { skip: process.platform === 'win32', timeout: 15000 }, async () => {
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
  const waitFor = (text) => new Promise((resolve) => {
    const check = () => { if (out.includes(text)) resolve(); };
    child.stdout.on('data', (d) => { out += d; check(); });
    check();
  });
  await waitFor('API iniciada');
  const agent = new http.Agent({ keepAlive: true });
  try {
    assert.equal((await get(port, '/health', agent)).connection, 'keep-alive');
    child.kill('SIGUSR2');
    await waitFor('drenagem iniciada');
    const r = await get(port, '/health', agent);
    assert.equal(r.status, 200, 'continua atendendo durante a drenagem');
    assert.equal(r.connection, 'close');
  } finally {
    agent.destroy();
  }
  child.kill('SIGTERM');
  const [code] = await once(child, 'exit');
  assert.equal(code, 0);
});
