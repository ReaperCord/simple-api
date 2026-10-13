# Requisitos — Endurecimento da aplicação (fase 1)

Origem: auditoria do repo base `SuporteKXC/simple-api@25337f2` (IDs A1–A12 em `.kiro/steering/05-aplicacao.md`). Medições de referência: benchmark LOCAL de 12/10/2026.

## Requisito 1 — Pool de conexões e timeouts (A2, A3)

**História:** Como operador, quero que a API reutilize conexões com o banco para que ela não esgote o Postgres nem trave sob carga.

Critérios de aceite:
1. THE SYSTEM SHALL manter um único `Pool` do `pg` por processo, com tamanho máximo definido por `DB_POOL_MAX` (padrão 5; na AWS a task usa 3).
2. WHEN o pool não conseguir uma conexão em 2 s THE SYSTEM SHALL responder `GET /connect` com 503 e corpo genérico, sem travar a requisição.
3. WHEN uma consulta exceder 3 s THE SYSTEM SHALL abortá-la no servidor (`statement_timeout`) e no cliente (`query_timeout`) e responder 503.
4. THE SYSTEM SHALL devolver toda conexão ao pool, inclusive quando a consulta falhar.

## Requisito 2 — TLS até o RDS (A4)

**História:** Como responsável por segurança, quero conexão cifrada e verificada com o banco (o RDS PostgreSQL 15+ exige TLS por padrão).

1. WHEN `DB_SSLMODE=verify-full` THE SYSTEM SHALL conectar com TLS e verificar o certificado e o hostname contra o CA bundle da RDS.
2. WHEN `DB_SSLMODE=disable` THE SYSTEM SHALL conectar sem TLS (uso local apenas).
3. IF o certificado não for válido THEN THE SYSTEM SHALL recusar a conexão.
4. IF `DB_SSLMODE` tiver valor desconhecido THEN THE SYSTEM SHALL falhar no startup com mensagem clara.

## Requisito 3 — Observabilidade (A5, A6)

1. THE SYSTEM SHALL escrever um log JSON por requisição com `ts, level, msg, method, path, status, duration_ms, request_id`.
2. WHEN a requisição trouxer `x-request-id` THE SYSTEM SHALL reutilizá-lo; caso contrário SHALL gerar um UUID.
3. THE SYSTEM SHALL NOT registrar senha, string de conexão ou objeto de erro bruto do driver.

## Requisito 4 — Ciclo de vida (A7, A11)

1. THE SYSTEM SHALL expor `GET /health` respondendo 200 sem consultar o banco.
2. WHEN receber `SIGTERM` THE SYSTEM SHALL parar de aceitar conexões, concluir as requisições em andamento, fechar o pool e sair com código 0 em até 10 s.

## Requisito 5 — Dependências e container (A8, A9, A10)

1. THE SYSTEM SHALL ter `npm audit --omit=dev` sem vulnerabilidades CRITICAL ou HIGH.
2. THE SYSTEM SHALL ser empacotado em imagem multi-stage, multi-arch (amd64 e arm64), rodando como usuário não-root, com `node` como PID 1.
3. THE SYSTEM SHALL NOT enviar o cabeçalho `X-Powered-By`.

## Requisito 6 — Contrato preservado

1. THE SYSTEM SHALL manter `GET /` respondendo 200 com `message: "API OK!"`.
2. THE SYSTEM SHALL manter os nomes e padrões das variáveis existentes (`API_PORT=3000`, `DB_PORT=5432`).

## Requisito 7 — Rotação do segredo do banco (A12)

**História:** Como operador, quero que a API continue conectando depois que o RDS girar a senha do master (a cada 7 dias por padrão).

1. WHEN `DB_SECRET_ARN` estiver definido THE SYSTEM SHALL obter a senha do Secrets Manager ao abrir conexão nova, com cache de no máximo 5 min.
2. WHEN o Postgres recusar a autenticação (`28P01`) THE SYSTEM SHALL invalidar o cache e tentar de novo uma vez com a senha atual.
3. WHEN `DB_SECRET_ARN` não estiver definido THE SYSTEM SHALL usar `DB_PASSWORD` (desenvolvimento local).
4. THE SYSTEM SHALL NOT registrar o valor do segredo em log ou erro.
