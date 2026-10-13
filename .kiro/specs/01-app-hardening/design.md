# Design — Endurecimento da aplicação (fase 1)

## Estrutura proposta

```
application/
├── src/
│   ├── index.js        # bootstrap: cria app, inicia servidor, trata SIGTERM
│   ├── app.js          # express app (rotas, middlewares) — exportado para testes
│   ├── config.js       # lê e valida variáveis (falha cedo com mensagem clara)
│   ├── db.js           # Pool do pg, TLS, timeouts, senha via função (Secrets Manager ou env)
│   ├── secret.js       # leitura do segredo com cache curto e invalidação em 28P01
│   └── logger.js       # log JSON mínimo (sem dependência externa, salvo aprovação)
├── test/
│   ├── app.test.js     # rotas com db falso
│   ├── secret.test.js  # cache e invalidação com cliente falso
│   └── db.int.test.js  # integração com Postgres real (SCRAM)
├── Dockerfile
└── .dockerignore
```

Separar `app.js` de `index.js` permite testar as rotas sem abrir porta.

## Decisões

| Decisão | Motivo | Alternativa descartada |
|---|---|---|
| `pg.Pool` com `max` = `DB_POOL_MAX` | benchmark local: original satura em ~70 req/s ("too many clients"); pool chega a ~600 req/s com 0,25 vCPU e ~1.300 com 0,5 | `Client` por requisição (original) |
| `password` do Pool como função assíncrona | o `pg` 8.x chama a função a cada conexão nova (conferido em `pg/lib/client.js`); permite pegar a senha atual depois da rotação de 7 dias | injeção estática via `secrets` da task (quebra após a rotação) |
| `/health` sem banco para liveness | falha do banco não deve reiniciar o container | usar `/connect` como health check |
| CA bundle da RDS copiado na imagem no build, com checksum | verificação de certificado sem rede no startup | `rejectUnauthorized: false` (inseguro) |
| `DB_SSLMODE` com valores `verify-full` e `disable` | nomes iguais aos da libpq, sem ambiguidade | `DB_SSL=require` (na libpq, `require` não verifica certificado) |
| Runner de teste `node:test` | embutido, sem dependência nova | Jest/Mocha (perguntar antes) |
| Logger próprio mínimo | menos supply chain; o log custa ~15% do teto com 0,25 vCPU, aceito | pino (aceitável se o Leandro aprovar) |

## Pontos a VERIFICAR antes de implementar (não assumir)

- URL atual do CA bundle global da RDS na documentação da AWS (e o checksum publicado, se houver).
- Versão LTS ativa do Node e digest da imagem `node:<lts>-alpine`.
- Versões de `express` e `pg` sem CVEs altas (`npm view`, `npm audit`).
- Se a leitura do segredo usará `@aws-sdk/client-secrets-manager` (precisa de OK do Leandro) e o tamanho que isso adiciona à imagem.
