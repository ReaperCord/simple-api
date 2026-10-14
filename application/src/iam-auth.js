'use strict';

const DEFAULT_TTL_MS = 5 * 60 * 1000;

// Provedor de "senha" para o RDS com autenticacao IAM: o token e uma URL assinada
// (valida por 15 min) gerada com as credenciais da task. Mesma interface do provedor
// de segredo (getPassword/invalidate), entao o db.js nao muda. Cache de ate 5 min (bem
// abaixo dos 15 min) e invalidacao em erro de autenticacao (28P01) feita pelo db.js.
// O token nunca entra em log nem em mensagem de erro.
// `loadSdk` e `now` sao injetaveis para teste.
function createIamTokenProvider({
  hostname,
  port,
  username,
  region,
  ttlMs = DEFAULT_TTL_MS,
  now = Date.now,
  loadSdk = () => require('@aws-sdk/rds-signer'),
}) {
  let sdk;
  try {
    sdk = loadSdk();
  } catch (err) {
    if (err && err.code === 'MODULE_NOT_FOUND') {
      throw new Error('DB_AUTH_MODE=iam, mas @aws-sdk/rds-signer nao esta instalado');
    }
    throw err;
  }
  const signer = new sdk.Signer({ hostname, port, username, region });

  let cached = null;
  let expiresAt = 0;
  let inflight = null;

  async function load() {
    const token = await signer.getAuthToken();
    if (typeof token !== 'string' || token === '') {
      throw new Error('token IAM do RDS vazio');
    }
    cached = token;
    expiresAt = now() + ttlMs;
    return token;
  }

  return {
    async getPassword() {
      if (cached !== null && now() < expiresAt) return cached;
      if (!inflight) {
        inflight = load().finally(() => {
          inflight = null;
        });
      }
      return inflight;
    },
    invalidate() {
      cached = null;
      expiresAt = 0;
    },
  };
}

module.exports = { createIamTokenProvider, DEFAULT_TTL_MS };
