'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const { once } = require('node:events');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { createDb } = require('../src/db');
const { createLogger } = require('../src/logger');

// Servidor TCP que aceita a conexao e nunca responde o handshake do Postgres.
async function startBlackHole() {
  const sockets = new Set();
  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on('error', () => {});
    socket.on('close', () => sockets.delete(socket));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return {
    port: server.address().port,
    close() {
      for (const socket of sockets) socket.destroy();
      server.close();
    },
  };
}

test('GET /connect responde 503 em menos de 3 s quando o banco nunca responde', { timeout: 6000 }, async () => {
  const blackHole = await startBlackHole();
  const config = loadConfig({
    DB_HOST: '127.0.0.1',
    DB_PORT: String(blackHole.port),
    DB_USER: 'u',
    DB_DATABASE: 'd',
    DB_PASSWORD: 'senha-de-teste-xyz',
    DB_SSLMODE: 'disable',
  });
  const logger = createLogger({ write: () => {} });
  const db = createDb({ config, logger });
  const server = createApp({ db, logger, config }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const started = Date.now();
    const res = await fetch(`${base}/connect`, { signal: AbortSignal.timeout(4500) });
    const elapsed = Date.now() - started;
    assert.equal(res.status, 503);
    assert.ok(elapsed < 3000, `demorou ${elapsed} ms (limite 3000 ms)`);
    const body = await res.json();
    assert.equal(body.message, 'Erro ao se conectar ao banco');
    assert.equal(typeof body.request_id, 'string');
  } finally {
    server.closeAllConnections();
    server.close();
    await db.end();
    blackHole.close();
  }
});
