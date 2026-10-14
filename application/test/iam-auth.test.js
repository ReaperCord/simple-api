'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createIamTokenProvider } = require('../src/iam-auth');
const { createDb } = require('../src/db');
const { loadConfig, ConfigError } = require('../src/config');

const FIVE_MIN = 5 * 60 * 1000;

// SDK falso: cada getAuthToken() devolve o proximo token e guarda a configuracao recebida.
function fakeSdk(tokens) {
  const state = { calls: 0, config: null };
  class Signer {
    constructor(config) {
      state.config = config;
    }
    async getAuthToken() {
      const token = tokens[Math.min(state.calls, tokens.length - 1)];
      state.calls += 1;
      return token;
    }
  }
  return { sdk: { Signer }, state };
}

const args = { hostname: 'db.exemplo.rds.amazonaws.com', port: 5432, username: 'app_connect', region: 'us-east-1' };

test('o Signer recebe hostname, porta, usuario e regiao', async () => {
  const { sdk, state } = fakeSdk(['t1']);
  createIamTokenProvider({ ...args, loadSdk: () => sdk });
  assert.deepEqual(state.config, args);
});

test('cache: dentro de 5 min so um token', async () => {
  let t = 1000;
  const { sdk, state } = fakeSdk(['t1', 't2']);
  const p = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => t });
  assert.equal(await p.getPassword(), 't1');
  t += FIVE_MIN - 1;
  assert.equal(await p.getPassword(), 't1');
  assert.equal(state.calls, 1);
});

test('cache expira depois de 5 min: novo token', async () => {
  let t = 1000;
  const { sdk, state } = fakeSdk(['t1', 't2']);
  const p = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => t });
  assert.equal(await p.getPassword(), 't1');
  t += FIVE_MIN;
  assert.equal(await p.getPassword(), 't2');
  assert.equal(state.calls, 2);
});

test('chamadas concorrentes geram um unico token', async () => {
  const { sdk, state } = fakeSdk(['t1', 't2']);
  const p = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => 1 });
  const out = await Promise.all([p.getPassword(), p.getPassword(), p.getPassword()]);
  assert.deepEqual(out, ['t1', 't1', 't1']);
  assert.equal(state.calls, 1);
});

test('invalidate forca um token novo', async () => {
  const { sdk, state } = fakeSdk(['t1', 't2']);
  const p = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => 1 });
  assert.equal(await p.getPassword(), 't1');
  p.invalidate();
  assert.equal(await p.getPassword(), 't2');
  assert.equal(state.calls, 2);
});

test('token vazio e erro e nao entra no cache', async () => {
  const { sdk, state } = fakeSdk(['', 't2']);
  const p = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => 1 });
  await assert.rejects(p.getPassword(), /token IAM do RDS vazio/);
  assert.equal(await p.getPassword(), 't2');
  assert.equal(state.calls, 2);
});

test('erro do SDK ao gerar o token propaga, sem cachear', async () => {
  let n = 0;
  const sdk = {
    Signer: class {
      async getAuthToken() {
        n += 1;
        if (n === 1) throw new Error('sem credenciais');
        return 'ok';
      }
    },
  };
  const p = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => 1 });
  await assert.rejects(p.getPassword(), /sem credenciais/);
  assert.equal(await p.getPassword(), 'ok');
});

test('pacote ausente: mensagem clara, sem vazar nada', () => {
  const loadSdk = () => {
    throw Object.assign(new Error("Cannot find module '@aws-sdk/rds-signer'"), { code: 'MODULE_NOT_FOUND' });
  };
  assert.throws(
    () => createIamTokenProvider({ ...args, loadSdk }),
    /DB_AUTH_MODE=iam, mas @aws-sdk\/rds-signer nao esta instalado/,
  );
});

test('outro erro ao carregar o SDK e repassado', () => {
  const loadSdk = () => {
    throw new Error('outro problema');
  };
  assert.throws(() => createIamTokenProvider({ ...args, loadSdk }), /outro problema/);
});

// --- integracao com o db.js: o token e a "senha" do Pool e 28P01 invalida e repete UMA vez.
function poolFactory(validToken, seen) {
  return class FakePool {
    constructor(options) { this.options = options; }
    on() { return this; }
    async query() {
      const used = await this.options.password();
      seen.push(used);
      if (used !== validToken) {
        throw Object.assign(new Error('falha de autenticacao'), { code: '28P01' });
      }
      return { rows: [{ version: 'v' }] };
    }
    async end() {}
  };
}

const iamEnv = {
  DB_AUTH_MODE: 'iam', DB_HOST: 'h', DB_USER: 'app_connect', DB_DATABASE: 'd',
  DB_SSLMODE: 'verify-full', DB_SSL_CA_FILE: '/certs/ca.pem', AWS_REGION: 'us-east-1',
};

test('db.js usa o token IAM como senha e refaz uma vez em 28P01', async () => {
  const seen = [];
  const { sdk, state } = fakeSdk(['expirado', 'valido']);
  const secretProvider = createIamTokenProvider({ ...args, loadSdk: () => sdk, now: () => 1 });
  const db = createDb({
    config: loadConfig(iamEnv),
    secretProvider,
    PoolClass: poolFactory('valido', seen),
    readFile: () => 'ca',
  });
  const result = await db.query('SELECT 1');
  assert.equal(result.rows[0].version, 'v');
  assert.deepEqual(seen, ['expirado', 'valido']);
  assert.equal(state.calls, 2);
});

// --- configuracao
test('config iam: valores validos', () => {
  const c = loadConfig(iamEnv);
  assert.equal(c.db.authMode, 'iam');
  assert.equal(c.db.region, 'us-east-1');
  assert.equal(c.db.password, undefined);
  assert.equal(c.db.secretArn, undefined);
});

test('config: DB_AUTH_MODE invalido falha', () => {
  assert.throws(() => loadConfig({ ...iamEnv, DB_AUTH_MODE: 'kerberos' }), ConfigError);
});

test('config iam: exige verify-full', () => {
  assert.throws(() => loadConfig({ ...iamEnv, DB_SSLMODE: 'disable' }), /exige DB_SSLMODE=verify-full/);
});

test('config iam: exige DB_HOST, DB_USER e regiao', () => {
  assert.throws(() => loadConfig({ ...iamEnv, DB_HOST: '' }), /DB_HOST e DB_USER/);
  assert.throws(() => loadConfig({ ...iamEnv, DB_USER: '' }), /DB_HOST e DB_USER/);
  assert.throws(() => loadConfig({ ...iamEnv, AWS_REGION: '' }), /AWS_REGION e obrigatoria/);
  assert.equal(loadConfig({ ...iamEnv, AWS_REGION: '', AWS_DEFAULT_REGION: 'sa-east-1' }).db.region, 'sa-east-1');
});

test('config iam: DB_SECRET_ARN ou DB_PASSWORD junto e erro (sem vazar o valor)', () => {
  assert.throws(() => loadConfig({ ...iamEnv, DB_SECRET_ARN: 'arn:x' }), /nao usa DB_SECRET_ARN nem DB_PASSWORD/);
  assert.throws(
    () => loadConfig({ ...iamEnv, DB_PASSWORD: 'segredo-123' }),
    (err) => err instanceof ConfigError && !err.message.includes('segredo-123'),
  );
});

test('config: modo padrao continua password e o comportamento antigo nao muda', () => {
  const c = loadConfig({ DB_HOST: 'h', DB_USER: 'u', DB_DATABASE: 'd', DB_PASSWORD: 'p', DB_SSLMODE: 'disable' });
  assert.equal(c.db.authMode, 'password');
  assert.equal(c.db.password, 'p');
  assert.equal(c.db.region, undefined);
});
