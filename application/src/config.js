'use strict';

const LOG_LEVELS = ['debug', 'info', 'warn', 'error'];
const SSL_MODES = ['verify-full', 'disable'];

class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}

function readInt(env, name, def, min, max) {
  const raw = env[name];
  if (raw === undefined || raw === '') return def;
  if (!/^\d+$/.test(raw)) {
    throw new ConfigError(`${name} deve ser um inteiro entre ${min} e ${max}`);
  }
  const value = Number(raw);
  if (value < min || value > max) {
    throw new ConfigError(`${name} deve ser um inteiro entre ${min} e ${max}`);
  }
  return value;
}

// Le e valida as variaveis de ambiente. Mensagens de erro citam so o NOME da
// variavel (e valores nao sensiveis), nunca a senha.
function loadConfig(env = process.env) {
  const sslMode = env.DB_SSLMODE || 'verify-full';
  if (!SSL_MODES.includes(sslMode)) {
    throw new ConfigError(
      `DB_SSLMODE invalido: "${sslMode}". Use ${SSL_MODES.join(' ou ')}`,
    );
  }
  const sslCaFile = env.DB_SSL_CA_FILE || undefined;
  if (sslMode === 'verify-full' && !sslCaFile) {
    throw new ConfigError('DB_SSL_CA_FILE e obrigatorio quando DB_SSLMODE=verify-full');
  }

  const logLevel = env.LOG_LEVEL || 'info';
  if (!LOG_LEVELS.includes(logLevel)) {
    throw new ConfigError(`LOG_LEVEL invalido: "${logLevel}". Use ${LOG_LEVELS.join(', ')}`);
  }

  // DB_SECRET_ARN presente: a senha vem do Secrets Manager e DB_PASSWORD e ignorada.
  const secretArn = env.DB_SECRET_ARN || undefined;
  const password = secretArn ? undefined : env.DB_PASSWORD;
  if (!secretArn && !password) {
    throw new ConfigError('DB_PASSWORD e obrigatoria quando DB_SECRET_ARN nao esta definido');
  }

  return {
    port: readInt(env, 'API_PORT', 3000, 0, 65535),
    logLevel,
    shutdownTimeoutMs: readInt(env, 'SHUTDOWN_TIMEOUT_MS', 8000, 1, 600000),
    db: {
      user: env.DB_USER,
      host: env.DB_HOST,
      database: env.DB_DATABASE,
      password,
      port: readInt(env, 'DB_PORT', 5432, 1, 65535),
      poolMax: readInt(env, 'DB_POOL_MAX', 5, 1, 20),
      sslMode,
      sslCaFile,
      secretArn,
    },
  };
}

module.exports = { loadConfig, ConfigError, LOG_LEVELS, SSL_MODES };
