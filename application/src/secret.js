'use strict';

const DEFAULT_TTL_MS = 5 * 60 * 1000;

// Cache da senha do banco lida do Secrets Manager. `fetchSecret` devolve o
// SecretString (JSON com campo `password`) e e injetavel para teste. O valor
// do segredo nunca entra em mensagem de erro nem em log.
function createSecretProvider({ fetchSecret, ttlMs = DEFAULT_TTL_MS, now = Date.now }) {
  let cached = null;
  let expiresAt = 0;
  let inflight = null;

  async function load() {
    const raw = await fetchSecret();
    let password;
    try {
      password = JSON.parse(raw).password;
    } catch {
      // Sem repassar o erro original: a mensagem do JSON.parse cita trechos do texto.
      throw new Error('segredo do banco nao e um JSON valido');
    }
    if (typeof password !== 'string' || password === '') {
      throw new Error('segredo do banco sem o campo password');
    }
    cached = password;
    expiresAt = now() + ttlMs;
    return password;
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

// Leitor real. O SDK e carregado so quando DB_SECRET_ARN existe (require
// preguicoso). `loadSdk` e injetavel para teste.
function createAwsSecretFetcher(secretArn, { loadSdk = () => require('@aws-sdk/client-secrets-manager') } = {}) {
  let sdk;
  try {
    sdk = loadSdk();
  } catch (err) {
    if (err && err.code === 'MODULE_NOT_FOUND') {
      throw new Error(
        'DB_SECRET_ARN definido, mas @aws-sdk/client-secrets-manager nao esta instalado',
      );
    }
    throw err;
  }
  const client = new sdk.SecretsManagerClient({});
  return async () => {
    const out = await client.send(new sdk.GetSecretValueCommand({ SecretId: secretArn }));
    return out.SecretString;
  };
}

module.exports = { createSecretProvider, createAwsSecretFetcher, DEFAULT_TTL_MS };
