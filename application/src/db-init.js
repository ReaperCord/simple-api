'use strict';

// Cria (uma vez, de forma idempotente) o usuario do banco usado pela app com autenticacao IAM:
// login sem senha, membro de rds_iam e SOMENTE com CONNECT no banco. Roda com a credencial MASTER
// (segredo gerenciado pelo RDS ou DB_PASSWORD), nunca dentro do servico da app:
//   node src/db-init.js      (variaveis: DB_HOST, DB_DATABASE, DB_USER=master, DB_SECRET_ARN, DB_SSL*, DB_APP_USER)
// Saida: uma linha "DBINIT {json}" com o que o banco REALMENTE concede ao usuario; exit 0 so se tudo bate.

const { loadConfig, ConfigError } = require('./config');
const { createDb } = require('./db');
const { createLogger } = require('./logger');
const { createSecretProvider, createAwsSecretFetcher } = require('./secret');

// DDL nao aceita parametros: o nome entra na SQL, entao so passa o que casa com este padrao estrito.
const IDENT = /^[a-z_][a-z0-9_]{0,62}$/;

function ident(name, label) {
  if (typeof name !== 'string' || !IDENT.test(name)) {
    throw new Error(`${label} invalido: use letras minusculas, digitos e _ (ate 63 caracteres)`);
  }
  return name;
}

// `db.query(texto)` e a mesma interface do db.js (injetavel para teste).
async function ensureAppUser({ db, appUser, database }) {
  const u = ident(appUser, 'DB_APP_USER');
  const d = ident(database, 'DB_DATABASE');

  const found = await db.query(`SELECT 1 FROM pg_roles WHERE rolname = '${u}'`);
  if (found.rows.length === 0) {
    await db.query(`CREATE ROLE "${u}" WITH LOGIN`);
  }
  await db.query(`GRANT rds_iam TO "${u}"`);
  await db.query(`GRANT CONNECT ON DATABASE "${d}" TO "${u}"`);

  const res = await db.query(
    `SELECT r.rolcanlogin AS login, r.rolsuper AS superuser, r.rolcreatedb AS createdb,
            r.rolcreaterole AS createrole, r.rolreplication AS replication, r.rolbypassrls AS bypassrls,
            pg_has_role('${u}', 'rds_iam', 'MEMBER') AS rds_iam,
            has_database_privilege('${u}', '${d}', 'CONNECT') AS db_connect,
            has_database_privilege('${u}', '${d}', 'CREATE') AS db_create,
            has_schema_privilege('${u}', 'public', 'CREATE') AS schema_create
       FROM pg_roles r WHERE r.rolname = '${u}'`,
  );
  const row = res.rows[0] || {};
  const ok =
    row.login === true &&
    row.rds_iam === true &&
    row.db_connect === true &&
    row.superuser === false &&
    row.createdb === false &&
    row.createrole === false &&
    row.replication === false &&
    row.bypassrls === false &&
    row.db_create === false &&
    row.schema_create === false;
  return { user: u, database: d, created: found.rows.length === 0, privileges: row, ok };
}

async function main(env = process.env) {
  let config;
  try {
    config = loadConfig(env);
    if (config.db.authMode === 'iam') {
      throw new ConfigError('db-init usa a credencial master: nao rode com DB_AUTH_MODE=iam');
    }
  } catch (err) {
    if (!(err instanceof ConfigError)) throw err;
    createLogger().error('configuracao invalida', { reason: err.message });
    return 1;
  }
  const logger = createLogger({ level: config.logLevel });
  const secretProvider = config.db.secretArn
    ? createSecretProvider({ fetchSecret: createAwsSecretFetcher(config.db.secretArn) })
    : null;
  const db = createDb({ config, logger, secretProvider });
  try {
    const out = await ensureAppUser({ db, appUser: env.DB_APP_USER, database: config.db.database });
    console.log(`DBINIT ${JSON.stringify(out)}`);
    return out.ok ? 0 : 1;
  } catch (err) {
    // So name/code: a mensagem do pg pode citar trechos da consulta.
    console.log(`DBINIT_ERRO ${JSON.stringify({ name: err.name, code: err.code, message: String(err.message).slice(0, 200) })}`);
    return 1;
  } finally {
    await db.end();
  }
}

if (require.main === module) {
  main().then((code) => process.exit(code));
}

module.exports = { ensureAppUser, main, ident };
