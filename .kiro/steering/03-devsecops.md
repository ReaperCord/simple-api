---
inclusion: fileMatch
fileMatchPattern: ["infrastructure/**", ".github/**", "**/Dockerfile", "application/**", "k8s/**", "**/*.json", ".pre-commit-config.yaml"]
---

# DevSecOps — regras não negociáveis

## Segredos

- Proibido: segredo em código, `.tfvars` versionado, `environment` de task definition, log, output Terraform não-sensitive, comentário, exemplo de README.
- Senha do RDS: `manage_master_user_password = true` (Secrets Manager gerenciado pelo RDS). O módulo `parameter-store` original (F-INF-6) NÃO é usado para senha.
- **Rotação:** o segredo gerenciado pelo RDS gira a cada 7 dias por padrão. Por isso a app lê a senha do Secrets Manager ao abrir conexão (variável `DB_SECRET_ARN`; `password` do `pg` como função assíncrona, cache ≤ 5 min, releitura em erro de autenticação `28P01`). Não usar a injeção estática `secrets[].valueFrom` para a senha sem tratar a rotação.
- State: backend S3 com `encrypt = true`, versionamento, bloqueio de acesso público e `use_lockfile = true` (Terraform ≥ 1.11). O state local do root `bootstrap` também é sensível: nunca versionar, nunca abrir.
- Gitleaks: no CI, `gitleaks git` (histórico) e `gitleaks dir` (arquivos); local, o hook oficial do gitleaks no `pre-commit`. Os comandos `detect` e `protect` estão depreciados desde a v8.19.

## IAM — least privilege

Cada workflow que assume role roda num **GitHub environment próprio** (`deploy`, `infra`, `eks-lab`). Assim o `sub` do token OIDC é diferente por workflow e um não consegue assumir a role do outro (sem environment, um workflow agendado na `main` teria o mesmo `sub` do deploy). Cada environment aceita só a branch `main` (deployment branch policy). `infra` exige aprovação; `deploy` e `eks-lab` não — o `eks-lab` precisa rodar o destroy agendado sozinho, e só quem tem escrita no repo dispara o `up` manual.

| Identidade | Permitido | Trust (`sub` do OIDC) |
|---|---|---|
| `gha-plan` | leitura (`Describe*`, `List*`, `Get*`), leitura do state, e `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject` só no objeto `<key>.tflock` (a trava nativa do S3 grava esse arquivo também no `plan`) | `repo:<GITHUB_OWNER>/simple-api:pull_request` |
| `gha-deploy` | ECR push só no repo do projeto; `ecs:UpdateService` + `ecs:DescribeServices` no ARN do service; `iam:PassRole` só nas 2 roles da task; com `Resource: "*"` (a AWS não aceita ARN nestas): `ecr:GetAuthorizationToken`, `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition` | `repo:<GITHUB_OWNER>/simple-api:environment:deploy` |
| `gha-infra` | aplicar a stack, com `aws:RequestedRegion=us-east-1` e tag `Project=simple-api` onde o serviço aceita | `repo:<GITHUB_OWNER>/simple-api:environment:infra` (com aprovação manual) |
| `gha-eks-lab` | criar/destruir só o root `eks-lab` (EKS, node group, NLB via controller, IAM do lab) em `us-east-1`; ler o state da stack principal | `repo:<GITHUB_OWNER>/simple-api:environment:eks-lab` |
| Execution role ECS | ECR pull, `logs:CreateLogStream`/`PutLogEvents` no log group | sem acesso a segredos |
| Task role ECS | `secretsmanager:GetSecretValue` só no ARN do segredo do RDS | nada mais |
| LB Controller (EKS) | `config/policies/alb_controller_policy.json` via Pod Identity (ou IRSA), só na SA do controller | nunca no ECS |
| Agente de IA (local) | perfil AWS somente leitura (ex.: `ReadOnlyAccess` num perfil `kxc-readonly`) | nunca credencial de escrita |

Proibido: `"Action": "*"`, `"Resource": "*"` em ação que ACEITA restrição por ARN, `AdministratorAccess`, `iam:PassRole` com `Resource: "*"`, access keys de longo prazo no GitHub. As únicas exceções de `Resource: "*"` são as da tabela (a doc do ECS diz que task definitions não suportam permissão por recurso) — cada uma comentada na policy com o motivo.

Toda policy nova: justificar cada `Action` em comentário ou no PR. Validar com `aws accessanalyzer validate-policy` quando possível (a API do IAM Access Analyzer responde nesta conta: `list-analyzers` retornou 0 analisadores em 13/10/2026; `validate-policy` ainda não foi testada)

## Container

- `node:24-alpine` (LTS ativa em out/2026 — confirmar na época) fixado por digest `@sha256:`.
- Multi-stage, `npm ci --omit=dev`, `USER node`, `CMD ["node","src/index.js"]` (nunca `npm start` como PID 1).
- `healthCheck` na task definition com o `wget` do busybox que já vem no alpine (`wget -qO- http://localhost:3000/health || exit 1`); não instalar `curl` só para isso.
- `readonlyRootFilesystem = true` na task definition / `readOnlyRootFilesystem: true` no pod.

## Scanners e gates (CI)

| Ferramenta | Alvo | Bloqueia |
|---|---|---|
| Gitleaks (`gitleaks git`) | repo | qualquer achado |
| Semgrep (`p/javascript`, `p/nodejs` — confirmar os nomes no Registry antes de fixar) | `application/` | severidade ERROR |
| npm audit + Trivy fs | dependências | CRITICAL/HIGH com fix |
| Hadolint | Dockerfile | error |
| Trivy image (+ SBOM CycloneDX) | imagem | CRITICAL/HIGH com fix |
| Trivy config | Terraform, K8s | HIGH+ (exceção só em `.trivyignore` com justificativa e data) |

Nunca "silenciar" um achado para o pipeline passar sem registrar a justificativa e avisar o Leandro. Upload de SARIF para a aba Security é gratuito em repositório público.

## Rede e banco

Nenhum SG com ingress `0.0.0.0/0`. RDS `publicly_accessible = false`, `storage_encrypted = true`. TLS do app até o RDS com verificação do CA bundle da AWS (`DB_SSLMODE=verify-full`). Usuário master na app é aceitável no laboratório; usuário só com `CONNECT` é pendência documentada.
