#!/usr/bin/env bash
# Cria o usuario da app no banco (autenticacao IAM, so CONNECT) rodando a task efemera "<nome>-dbinit".
# Rode UMA vez depois do `infra.yml apply` (modo db_iam_auth = true). Idempotente: pode repetir.
# Escreve na AWS (run-task): exige o perfil de escrita e a aprovacao do Leandro (AGENTS.md, regras 7 e 12).
# Uso: tools/run-db-init.sh [ambiente]      (padrao: dev; regiao: AWS_REGION ou us-east-1)
# Saida: a linha "DBINIT {...}" do container. Codigos: 0 = usuario criado/confirmado com os privilegios esperados;
#   1 = a task terminou com erro ou o banco revelou privilegio a mais; 2 = nao foi possivel rodar/ler a task.
set -uo pipefail
ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROJECT="simple-api"
NAME="${PROJECT}-${ENVIRONMENT}"
export AWS_REGION="$REGION" AWS_PAGER=""

fail() { echo "ERRO: $*" >&2; exit 2; }
command -v aws >/dev/null 2>&1 || fail "AWS CLI nao encontrada."

# Rede: a mesma do service da API (subnets publicas e o SG das tasks, que ja alcanca o RDS na 5432).
NET=$(aws ecs describe-services --cluster "$NAME" --services "$NAME" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.[join(`,`,subnets),join(`,`,securityGroups),assignPublicIp]' \
  --output text 2>&1) || fail "nao consegui ler o service $NAME: $NET"
read -r SUBNETS SGS PUBIP <<<"$NET"
{ [ -n "${SUBNETS:-}" ] && [ "$SUBNETS" != "None" ]; } || fail "service $NAME sem configuracao de rede (a stack esta no ar?)"

ARN=$(aws ecs run-task --cluster "$NAME" --task-definition "${NAME}-dbinit" --launch-type FARGATE --count 1 \
  --started-by "run-db-init" \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SGS}],assignPublicIp=${PUBIP}}" \
  --query 'tasks[0].taskArn' --output text 2>&1) || fail "run-task falhou: $ARN"
[ -n "$ARN" ] && [ "$ARN" != "None" ] || fail "run-task nao devolveu a task (sem a task definition ${NAME}-dbinit? so existe com db_iam_auth = true)"
TID="${ARN##*/}"
echo "task $TID iniciada; aguardando terminar..."

aws ecs wait tasks-stopped --cluster "$NAME" --tasks "$TID" || fail "a task nao parou no tempo do waiter"
EXIT=$(aws ecs describe-tasks --cluster "$NAME" --tasks "$TID" --query 'tasks[0].containers[0].exitCode' --output text 2>&1) \
  || fail "nao consegui ler o resultado da task: $EXIT"
sleep 8 # o awslogs entrega o fim do log com pequeno atraso
# filter-log-events pagina corretamente (get-log-events pode devolver o log incompleto).
OUT=$(aws logs filter-log-events --log-group-name "/ecs/${NAME}" --log-stream-names "dbinit/db-init/${TID}" \
  --filter-pattern DBINIT --query 'events[].message' --output text 2>&1) || fail "nao consegui ler o log: $OUT"
echo "$OUT" | tr '\t' '\n' | grep -E '^DBINIT' || echo "(sem linha DBINIT no log da task)"
echo "exit code da task: $EXIT"
[ "$EXIT" = "0" ] && grep -q '^DBINIT ' <<<"$(echo "$OUT" | tr '\t' '\n')" && exit 0
exit 1
