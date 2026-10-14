#!/usr/bin/env bash
# Teste de tools/residual-check.sh com um "aws" falso: NÃO toca na AWS e não precisa de credencial.
# Foco: a classificação de ECS marcado por tag pelo STATUS real (cluster/service ativo é resíduo; INACTIVE não é).
# Uso: tools/test-residual-check.sh     (código 0 = todos os casos passaram)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/aws" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  "sts get-caller-identity"*) echo "arn:aws:iam::000000000000:user/teste" ;;
  *"resourcegroupstaggingapi get-resources"*"--resource-type-filters"*) printf '%s' "${FAKE_TAG_ECS:-}" ;;
  *"resourcegroupstaggingapi get-resources"*) printf '%s' "${FAKE_TAG_GENERIC:-}" ;;
  *"ecs describe-clusters"*)
    if [ "${FAKE_FAIL_CLUSTER:-0}" = 1 ]; then echo "AccessDeniedException" >&2; exit 255; fi
    echo "${FAKE_CLUSTER_STATUS:-INACTIVE}" ;;
  *"ecs describe-services"*) echo "${FAKE_SERVICE_STATUS:-INACTIVE}" ;;
  *"ecs describe-task-definition"*) echo "${FAKE_TD_STATUS:-INACTIVE}" ;;
  *"guardduty"*) echo "SubscriptionRequiredException" >&2; exit 254 ;;
  *) ;;
esac
exit 0
EOF
chmod +x "$TMP/aws"

A="arn:aws:ecs:us-east-1:000000000000"
CL="$A:cluster/simple-api-dev"
SV="$A:service/simple-api-dev/simple-api-dev"
SV_OLD="$A:service/simple-api-dev"
TD="$A:task-definition/simple-api-dev:1"
TAB=$'\t'
FALHAS=0

# caso <nome> <exit esperado> <regex que DEVE aparecer ('' = não checar)> <regex que NÃO pode aparecer ('' = não checar)> VAR=valor...
caso() {
  local nome="$1" esperado="$2" deve="$3" nao="$4"; shift 4
  local saida rc ok=1
  saida=$(env PATH="$TMP:$PATH" "$@" bash "$ROOT/tools/residual-check.sh" 2>&1); rc=$?
  [ "$rc" -eq "$esperado" ] || ok=0
  if [ -n "$deve" ] && ! grep -Eq "$deve" <<<"$saida"; then ok=0; fi
  if [ -n "$nao" ] && grep -Eq "$nao" <<<"$saida"; then ok=0; fi
  if [ "$ok" -eq 1 ]; then echo "OK    $nome (exit $rc)"; else echo "FALHA $nome (exit $rc, esperado $esperado)"; echo "$saida" | sed 's/^/      | /' | head -30; FALHAS=$((FALHAS+1)); fi
}

caso "nada marcado por tag"                                   0 'ok: nenhuma'            'status (ACTIVE|DRAINING)'
caso "cluster ECS ATIVO marcado por tag e resíduo"            1 'cluster ECS, status ACTIVE' ''  FAKE_TAG_ECS="$CL" FAKE_CLUSTER_STATUS=ACTIVE
caso "cluster ECS INACTIVE e ignorado"                        0 ''                       'cluster ECS, status' FAKE_TAG_ECS="$CL" FAKE_CLUSTER_STATUS=INACTIVE
caso "cluster que a API já não encontra (None) e ignorado"    0 ''                       'cluster ECS, status' FAKE_TAG_ECS="$CL" FAKE_CLUSTER_STATUS=None
caso "service ECS ATIVO marcado por tag e resíduo"            1 'service ECS, status ACTIVE' '' FAKE_TAG_ECS="$SV" FAKE_SERVICE_STATUS=ACTIVE
caso "service ECS INACTIVE e ignorado"                        0 ''                       'service ECS, status' FAKE_TAG_ECS="$SV" FAKE_SERVICE_STATUS=INACTIVE
caso "service em formato antigo de ARN nao e classificavel"   1 'não classificável'      ''  FAKE_TAG_ECS="$SV_OLD"
caso "cluster ativo + service INACTIVE + task def: resíduo"   1 'cluster ECS, status ACTIVE' '' FAKE_TAG_ECS="$CL$TAB$SV$TAB$TD" FAKE_CLUSTER_STATUS=ACTIVE FAKE_SERVICE_STATUS=INACTIVE FAKE_TD_STATUS=ACTIVE
caso "task definition ACTIVE so informa, nao muda o exit"     0 "$TD"                    'status ACTIVE' FAKE_TAG_ECS="$TD" FAKE_TD_STATUS=ACTIVE
caso "task definition INACTIVE nao aparece"                   0 'ok: nenhuma'           "$TD" FAKE_TAG_ECS="$TD" FAKE_TD_STATUS=INACTIVE
caso "erro ao descrever o cluster = exit 2 (nao e 'limpo')"   2 'ERRO na consulta'       ''  FAKE_TAG_ECS="$CL" FAKE_FAIL_CLUSTER=1
caso "outro tipo no indice geral de tags continua resíduo"    1 'rds:'                   ''  FAKE_TAG_GENERIC="arn:aws:rds:us-east-1:000000000000:db:simple-api-dev-db"

if [ "$FALHAS" -eq 0 ]; then echo "Todos os casos passaram."; exit 0; fi
echo "$FALHAS caso(s) falharam."; exit 1
