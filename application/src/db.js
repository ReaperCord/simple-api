'use strict';

const fs = require('node:fs');
const { Pool } = require('pg');

const CONNECTION_TIMEOUT_MS = 2000;
const IDLE_TIMEOUT_MS = 10000;
const STATEMENT_TIMEOUT_MS = 3000;
const QUERY_TIMEOUT_MS = 3000;
const INVALID_PASSWORD = '28P01';

// Opcoes do Pool. TLS: com DB_SSLMODE=verify-full valida o certificado com o CA
// bundle da RDS (rejectUnauthorized sempre true). O bundle vem de:
// https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
function buildPoolOptions(config, secretProvider, readFile) {
  const { db } = config;
  const options = {
    user: db.user,
    host: db.host,
    database: db.database,
    port: db.port,
    password: secretProvider ? () => secretProvider.getPassword() : db.password,
    max: db.poolMax,
    connectionTimeoutMillis: CONNECTION_TIMEOUT_MS,
    idleTimeoutMillis: IDLE_TIMEOUT_MS,
    statement_timeout: STATEMENT_TIMEOUT_MS,
    query_timeout: QUERY_TIMEOUT_MS,
  };
  if (db.sslMode === 'verify-full') {
    options.ssl = { ca: readFile(db.sslCaFile), rejectUnauthorized: true };
  }
  return options;
}

// Um unico Pool por processo. `PoolClass` e `readFile` sao injetaveis em teste.
function createDb({
  config,
  logger,
  secretProvider = null,
  PoolClass = Pool,
  readFile = (file) => fs.readFileSync(file),
}) {
  const pool = new PoolClass(buildPoolOptions(config, secretProvider, readFile));
  // Erro em cliente ocioso: registra so name/code, nunca o objeto bruto.
  pool.on('error', (err) => {
    if (logger) logger.error('erro no pool de conexoes', { err });
  });

  async function query(text) {
    try {
      return await pool.query(text);
    } catch (err) {
      // Senha rotacionada no Secrets Manager: invalida o cache e tenta UMA vez.
      if (secretProvider && err && err.code === INVALID_PASSWORD) {
        secretProvider.invalidate();
        return pool.query(text);
      }
      throw err;
    }
  }

  return { query, end: () => pool.end() };
}

module.exports = { createDb, buildPoolOptions };
