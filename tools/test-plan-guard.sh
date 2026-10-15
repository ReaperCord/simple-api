#!/usr/bin/env bash
# Teste de tools/plan-guard.sh com planos JSON sinteticos (formato de `terraform show -json`). Nao usa Terraform nem AWS.
# Uso: tools/test-plan-guard.sh   (exige jq, presente nos runners ubuntu do GitHub)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# rc <acoes...>: um resource_change com as acoes dadas (JSON). Ex.: rc '"delete","create"' aws_db_instance.this
rc() { printf '{"address":"%s","change":{"actions":[%s]}}' "${2//\"/\\\"}" "$1"; } # escapa as aspas do endereco
plano() { local IFS=,; printf '{"format_version":"1.2","resource_changes":[%s]}' "$*"; }

FALHAS=0
caso() {
  local nome="$1" json="$2" rc_esperado="$3" deve_saida="$4" deve_resumo="$5" nao_resumo="${6:-}"
  local saida rc ok=1
  printf '%s' "$json" >"$TMP/plan.json"
  saida=$(bash "$ROOT/tools/plan-guard.sh" "$TMP/plan.json" "$TMP/resumo.md" 2>&1); rc=$?
  [ "$rc" -eq "$rc_esperado" ] || ok=0
  if [ -n "$deve_saida" ] && ! grep -Ezq "$deve_saida" <<<"$saida"; then ok=0; fi
  if [ -n "$deve_resumo" ] && ! grep -Eq "$deve_resumo" "$TMP/resumo.md" 2>/dev/null; then ok=0; fi
  if [ -n "$nao_resumo" ] && grep -Eq "$nao_resumo" "$TMP/resumo.md" 2>/dev/null; then ok=0; fi
  if [ "$ok" -eq 1 ]; then echo "OK    $nome"; else
    echo "FALHA $nome (exit $rc, esperado $rc_esperado)"; echo "$saida" | sed 's/^/      | /'
    sed 's/^/      md| /' "$TMP/resumo.md" 2>/dev/null; FALHAS=$((FALHAS + 1)); fi
  rm -f "$TMP/resumo.md"
}

caso "sem mudancas (no-op e read): nada a aplicar" \
  "$(plano "$(rc '"no-op"' aws_vpc.this)" "$(rc '"read"' data.aws_caller_identity.this)")" \
  0 'has_changes=false.*destructive=false' 'Sem mudancas'

caso "resource_changes ausente (stack vazia, destroy sem nada)" \
  '{"format_version":"1.2"}' \
  0 'create=0.*delete=0.*has_changes=false' 'Sem mudancas'

caso "so create e update: nao destrutivo" \
  "$(plano "$(rc '"create"' aws_ecs_service.this)" "$(rc '"update"' aws_security_group.app)")" \
  0 'create=1.update=1.delete=0.replace=0.*destructive=false' 'Nenhum recurso destruido' '^- `'

caso "replace (delete,create): destrutivo e listado" \
  "$(plano "$(rc '"delete","create"' aws_db_instance.this)" "$(rc '"update"' aws_ecs_service.this)")" \
  0 'replace=1.*destructive=true' '^- `aws_db_instance.this` \(replace\)'

caso "replace na ordem create_before_destroy (create,delete)" \
  "$(plano "$(rc '"create","delete"' aws_lb.this)")" \
  0 'replace=1.*destructive=true' 'aws_lb.this` \(replace\)'

caso "destroy de tudo: conta e lista cada recurso" \
  "$(plano "$(rc '"delete"' aws_vpc.this)" "$(rc '"delete"' 'module.rds.aws_db_instance.this')" "$(rc '"delete"' 'aws_subnet.private["a"]')")" \
  0 'delete=3.*destructive=true' 'aws_subnet.private\["a"\]` \(delete\)'

caso "forget (bloco removed): muda o state, nao destroi" \
  "$(plano "$(rc '"forget"' aws_s3_bucket.old)")" \
  0 'forget=1.has_changes=true.destructive=false' 'Nenhum recurso destruido'

caso "JSON que nao e plano: exit 2" '{"foo":1}' 2 'nao e a saida' ''

caso "arquivo inexistente nao vira 'sem mudancas': exit 2" '' 2 'nao e a saida' ''

if [ "$FALHAS" -eq 0 ]; then echo "Todos os casos passaram."; exit 0; fi
echo "$FALHAS caso(s) falharam."; exit 1
