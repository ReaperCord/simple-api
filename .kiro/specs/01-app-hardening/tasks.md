# Tarefas — Endurecimento da aplicação (fase 1)

Agente: `kxc-app`. Revisão final: `kxc-verificador`.

- [ ] 1. Separar `app.js`, `config.js`, `db.js`, `logger.js` e `index.js` sem mudar comportamento; teste garantindo `GET /` = 200 e `message: "API OK!"`
  - _Requisitos: 6.1, 6.2_
- [ ] 2. Escrever teste que falha no código original para pool e timeouts (banco indisponível → 503 em < 3 s)
  - _Requisitos: 1.2, 1.3_
- [ ] 3. Implementar `Pool` com `DB_POOL_MAX`, `connectionTimeoutMillis`, `statement_timeout` e `query_timeout`
  - _Requisitos: 1.1–1.4_
- [ ] 4. Implementar `DB_SSLMODE` (`verify-full`/`disable`) com CA bundle; verificar a URL do bundle e citar a fonte
  - _Requisitos: 2.1–2.4_
- [ ] 5. Logger JSON + `request_id`; teste garantindo que a senha não aparece no log em caso de erro
  - _Requisitos: 3.1–3.3_
- [ ] 6. `/health`, `x-powered-by` desligado, limite de payload
  - _Requisitos: 4.1, 5.3_
- [ ] 7. Graceful shutdown com teste de `SIGTERM`
  - _Requisitos: 4.2_
- [ ] 8. Pedir OK para a dependência do Secrets Manager; implementar `secret.js` (cache ≤ 5 min, invalidação em `28P01`) e `password` como função; testes com cliente falso
  - _Requisitos: 7.1–7.4_
- [ ] 9. Atualizar dependências até `npm audit --omit=dev` limpo de CRITICAL/HIGH; mostrar antes e depois
  - _Requisitos: 5.1_
- [ ] 10. Dockerfile multi-stage + `.dockerignore`; build multi-arch; `hadolint` limpo; imagem roda como `node`
  - _Requisitos: 5.2_
- [ ] 11. `docker-compose.yml` com Postgres 16 (SCRAM) e healthcheck; `curl` em `/`, `/health`, `/connect`
  - _Requisitos: 6.1_
- [ ] 12. Pedir ao `kxc-perf` para repetir o benchmark local com a imagem final, rodando a API com `docker run --cpus=0.5` e `DB_POOL_MAX=3` (método em `tests/load/local-baseline/README.md`); registrar em `tests/load/results/` e `docs/performance/benchmark-local.md`, rotulado como LOCAL
- [ ] 13. Rodar `kxc-verificador` sobre o diff e o relatório
