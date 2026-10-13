'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig, ConfigError } = require('../src/config');

const base = { DB_PASSWORD: 'senha-de-teste-xyz', DB_SSLMODE: 'disable' };

test('defaults: porta 3000, DB_PORT 5432, pool 5, log info', () => {
  const cfg = loadConfig(base);
  assert.equal(cfg.port, 3000);
  assert.equal(cfg.db.port, 5432);
  assert.equal(cfg.db.poolMax, 5);
  assert.equal(cfg.logLevel, 'info');
  assert.equal(cfg.shutdownTimeoutMs, 8000);
});

test('DB_SSLMODE padrao e verify-full e exige DB_SSL_CA_FILE', () => {
  assert.throws(
    () => loadConfig({ DB_PASSWORD: 'x' }),
    (err) => err instanceof ConfigError && /DB_SSL_CA_FILE/.test(err.message),
  );
  const cfg = loadConfig({ DB_PASSWORD: 'x', DB_SSL_CA_FILE: '/certs/ca.pem' });
  assert.equal(cfg.db.sslMode, 'verify-full');
  assert.equal(cfg.db.sslCaFile, '/certs/ca.pem');
});

test('DB_SSLMODE desconhecido (inclusive require) falha com mensagem clara', () => {
  for (const mode of ['require', 'prefer', 'verify-ca', 'qualquer']) {
    assert.throws(
      () => loadConfig({ ...base, DB_SSLMODE: mode }),
      (err) => err instanceof ConfigError && /DB_SSLMODE invalido/.test(err.message),
    );
  }
});

test('DB_POOL_MAX valida inteiro entre 1 e 20', () => {
  assert.equal(loadConfig({ ...base, DB_POOL_MAX: '3' }).db.poolMax, 3);
  for (const bad of ['0', '21', 'abc', '2.5', '-1']) {
    assert.throws(() => loadConfig({ ...base, DB_POOL_MAX: bad }), /DB_POOL_MAX/);
  }
});

test('LOG_LEVEL e SHUTDOWN_TIMEOUT_MS invalidos falham', () => {
  assert.throws(() => loadConfig({ ...base, LOG_LEVEL: 'verbose' }), /LOG_LEVEL/);
  assert.throws(() => loadConfig({ ...base, SHUTDOWN_TIMEOUT_MS: '0' }), /SHUTDOWN_TIMEOUT_MS/);
});

test('DB_PASSWORD e obrigatoria sem DB_SECRET_ARN; com ARN e ignorada', () => {
  assert.throws(() => loadConfig({ DB_SSLMODE: 'disable' }), /DB_PASSWORD/);
  const cfg = loadConfig({ ...base, DB_SECRET_ARN: 'arn:aws:secretsmanager:us-east-1:<AWS_ACCOUNT_ID>:secret:x' });
  assert.equal(cfg.db.password, undefined);
  assert.match(cfg.db.secretArn, /^arn:aws:secretsmanager:/);
  assert.doesNotThrow(() => loadConfig({ DB_SSLMODE: 'disable', DB_SECRET_ARN: 'arn:x' }));
});

test('a mensagem de erro nunca contem a senha', () => {
  assert.throws(
    () => loadConfig({ DB_PASSWORD: 'senha-de-teste-xyz', DB_SSLMODE: 'bogus' }),
    (err) => !err.message.includes('senha-de-teste-xyz'),
  );
});
