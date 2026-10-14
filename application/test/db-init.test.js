'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { ensureAppUser, ident } = require('../src/db-init');

const SEGURO = {
  login: true, superuser: false, createdb: false, createrole: false, replication: false, bypassrls: false,
  rds_iam: true, db_connect: true, db_create: false, schema_create: false,
};

// Banco falso: responde pela forma da SQL e registra tudo o que foi executado.
function fakeDb({ existe, privilegios = SEGURO }) {
  const sql = [];
  return {
    sql,
    async query(text) {
      sql.push(text.replace(/\s+/g, ' ').trim());
      if (/FROM pg_roles WHERE rolname = '[^']+'$/.test(sql[sql.length - 1]) && /^SELECT 1/.test(sql[sql.length - 1])) {
        return { rows: existe ? [{ '?column?': 1 }] : [] };
      }
      if (/^SELECT r\.rolcanlogin/.test(sql[sql.length - 1])) return { rows: [privilegios] };
      return { rows: [] };
    },
  };
}

test('cria o usuario quando nao existe, concede rds_iam e CONNECT, e confere o resultado', async () => {
  const db = fakeDb({ existe: false });
  const out = await ensureAppUser({ db, appUser: 'app_connect', database: 'appdb' });
  assert.equal(out.created, true);
  assert.equal(out.ok, true);
  assert.ok(db.sql.includes('CREATE ROLE "app_connect" WITH LOGIN'));
  assert.ok(db.sql.includes('GRANT rds_iam TO "app_connect"'));
  assert.ok(db.sql.includes('GRANT CONNECT ON DATABASE "appdb" TO "app_connect"'));
});

test('idempotente: se o usuario existe nao tenta criar de novo, mas reaplica os grants', async () => {
  const db = fakeDb({ existe: true });
  const out = await ensureAppUser({ db, appUser: 'app_connect', database: 'appdb' });
  assert.equal(out.created, false);
  assert.equal(out.ok, true);
  assert.ok(!db.sql.some((s) => s.startsWith('CREATE ROLE')));
  assert.ok(db.sql.includes('GRANT rds_iam TO "app_connect"'));
});

test('nao concede nada alem de CONNECT: nenhuma outra instrucao GRANT, nem senha', async () => {
  const db = fakeDb({ existe: false });
  await ensureAppUser({ db, appUser: 'app_connect', database: 'appdb' });
  const grants = db.sql.filter((s) => /^(GRANT|ALTER|CREATE ROLE)/.test(s));
  assert.deepEqual(grants, [
    'CREATE ROLE "app_connect" WITH LOGIN',
    'GRANT rds_iam TO "app_connect"',
    'GRANT CONNECT ON DATABASE "appdb" TO "app_connect"',
  ]);
  // So as instrucoes que ALTERAM o banco (a SELECT de verificacao cita colunas como rolcreatedb).
  const ddl = db.sql.filter((s) => !s.startsWith('SELECT'));
  assert.ok(!ddl.some((s) => /PASSWORD|SUPERUSER|CREATEDB|CREATEROLE/i.test(s)));
});

test('ok = false se o banco revelar privilegio a mais (ex.: pode criar no schema public)', async () => {
  const db = fakeDb({ existe: true, privilegios: { ...SEGURO, schema_create: true } });
  const out = await ensureAppUser({ db, appUser: 'app_connect', database: 'appdb' });
  assert.equal(out.ok, false);
});

test('ok = false se o usuario for superuser ou nao estiver em rds_iam', async () => {
  for (const extra of [{ superuser: true }, { rds_iam: false }, { db_connect: false }, { login: false }]) {
    const db = fakeDb({ existe: true, privilegios: { ...SEGURO, ...extra } });
    const out = await ensureAppUser({ db, appUser: 'app_connect', database: 'appdb' });
    assert.equal(out.ok, false, JSON.stringify(extra));
  }
});

test('ok = false se a consulta de verificacao nao devolver a linha do usuario', async () => {
  const db = fakeDb({ existe: true, privilegios: undefined });
  db.query = async (text) => ({ rows: /^\s*SELECT r\.rolcanlogin/.test(text) ? [] : [] });
  const out = await ensureAppUser({ db, appUser: 'app_connect', database: 'appdb' });
  assert.equal(out.ok, false);
});

test('nome invalido e recusado antes de qualquer SQL (sem injecao)', async () => {
  const db = fakeDb({ existe: false });
  for (const ruim of ['app"; DROP DATABASE appdb; --', 'App', '1abc', '', 'a'.repeat(64), "x' OR '1'='1", undefined]) {
    await assert.rejects(ensureAppUser({ db, appUser: ruim, database: 'appdb' }), /DB_APP_USER invalido/);
  }
  await assert.rejects(ensureAppUser({ db, appUser: 'app_connect', database: 'a"b' }), /DB_DATABASE invalido/);
  assert.equal(db.sql.length, 0);
});

test('ident aceita so minusculas, digitos e _', () => {
  assert.equal(ident('app_connect', 'x'), 'app_connect');
  assert.equal(ident('_a1', 'x'), '_a1');
  assert.throws(() => ident('a-b', 'x'));
});
