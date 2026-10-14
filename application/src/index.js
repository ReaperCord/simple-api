'use strict';

const { createApp } = require('./app');
const { loadConfig, ConfigError } = require('./config');
const { createDb } = require('./db');
const { createIamTokenProvider } = require('./iam-auth');
const { prewarm } = require('./prewarm');
const { createLogger } = require('./logger');
const { createSecretProvider, createAwsSecretFetcher } = require('./secret');

// Encerramento ordenado: para de aceitar conexoes, fecha o pool e sai com 0.
// O timer de seguranca (unref) forca saida 1 se algo travar.
async function shutdown({ server, db, logger, timeoutMs, exit = process.exit }) {
  const timer = setTimeout(() => {
    logger.error('shutdown excedeu o tempo limite', { timeout_ms: timeoutMs });
    exit(1);
  }, timeoutMs);
  timer.unref();
  try {
    await new Promise((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
      if (typeof server.closeIdleConnections === 'function') server.closeIdleConnections();
    });
    await db.end();
    clearTimeout(timer);
    exit(0);
  } catch (err) {
    clearTimeout(timer);
    logger.error('falha no shutdown', { err });
    exit(1);
  }
}

function main() {
  let config;
  try {
    config = loadConfig();
  } catch (err) {
    if (!(err instanceof ConfigError)) throw err;
    createLogger().error('configuracao invalida', { reason: err.message });
    process.exit(1);
  }

  const logger = createLogger({ level: config.logLevel });

  // Provedor da "senha": token IAM do RDS (DB_AUTH_MODE=iam) ou segredo do Secrets Manager (DB_SECRET_ARN).
  let secretProvider = null;
  if (config.db.authMode === 'iam') {
    try {
      secretProvider = createIamTokenProvider({
        hostname: config.db.host,
        port: config.db.port,
        username: config.db.user,
        region: config.db.region,
      });
    } catch (err) {
      logger.error('gerador de token IAM indisponivel', { reason: err.message });
      process.exit(1);
    }
  } else if (config.db.secretArn) {
    try {
      secretProvider = createSecretProvider({
        fetchSecret: createAwsSecretFetcher(config.db.secretArn),
      });
    } catch (err) {
      logger.error('leitor de segredo indisponivel', { reason: err.message });
      process.exit(1);
    }
  }

  const db = createDb({ config, logger, secretProvider });
  const app = createApp({ db, logger, config });

  // listen DEPOIS de montar todas as rotas.
  const server = app.listen(config.port, () => {
    logger.info(`API iniciada. Escutando PORT ${config.port}`);
  });

  // Modo IAM: aquece o token e a primeira conexao sem bloquear a partida nem derrubar o processo (src/prewarm.js).
  if (config.db.authMode === 'iam') {
    prewarm({ provider: secretProvider, db, logger });
  }

  let stopping = false;
  const onSignal = (signal) => {
    if (stopping) return;
    stopping = true;
    logger.info('sinal recebido, encerrando', { signal });
    shutdown({ server, db, logger, timeoutMs: config.shutdownTimeoutMs });
  };
  process.on('SIGTERM', () => onSignal('SIGTERM'));
  process.on('SIGINT', () => onSignal('SIGINT'));
}

if (require.main === module) main();

module.exports = { shutdown };
