'use strict';

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const RESERVED = new Set(['ts', 'level', 'msg']);
const SAFE_NAME = /^[A-Za-z0-9_.]{1,64}$/;
const SAFE_CODE = /^[A-Za-z0-9_]{1,32}$/;

// Reduz um erro a {name, code}. Nunca expoe message, stack nem o objeto bruto
// (erros do pg podem carregar host, usuario e detalhes da conexao).
function sanitizeError(err) {
  const out = { name: 'Error' };
  if (err && typeof err === 'object') {
    if (typeof err.name === 'string' && SAFE_NAME.test(err.name)) out.name = err.name;
    if (typeof err.code === 'string' && SAFE_CODE.test(err.code)) out.code = err.code;
  }
  return out;
}

// Uma linha JSON por evento. `write` e `now` sao injetaveis para teste.
function createLogger({
  level = 'info',
  write = (line) => process.stdout.write(`${line}\n`),
  now = () => new Date(),
} = {}) {
  if (!Object.prototype.hasOwnProperty.call(LEVELS, level)) {
    throw new Error(`nivel de log invalido: ${level}`);
  }
  const threshold = LEVELS[level];

  function log(lvl, msg, fields = {}) {
    if (LEVELS[lvl] < threshold) return;
    const entry = { ts: now().toISOString(), level: lvl, msg };
    for (const [key, value] of Object.entries(fields)) {
      if (RESERVED.has(key)) continue;
      entry[key] = key === 'err' ? sanitizeError(value) : value;
    }
    write(JSON.stringify(entry));
  }

  return {
    debug: (msg, fields) => log('debug', msg, fields),
    info: (msg, fields) => log('info', msg, fields),
    warn: (msg, fields) => log('warn', msg, fields),
    error: (msg, fields) => log('error', msg, fields),
  };
}

module.exports = { createLogger, sanitizeError };
