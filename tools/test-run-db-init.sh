#!/usr/bin/env bash
# Teste de tools/run-db-init.sh com um "aws" falso: NAO toca na AWS. Uso: tools/test-run-db-init.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/aws" <<'EOS'
#!/usr/bin/env bash
a="$*"
case "$a" in
  *"ecs describe-services"*) if [ "${FAKE_NO_SERVICE:-0}" = 1 ]; then printf 'None\tNone\tNone\n'; else printf 'subnet-1,subnet-2\tsg-9\tENABLED\n'; fi ;;
  *"ecs run-task"*) echo "${FAKE_RUN_TASK:-arn:aws:ecs:us-east-1:000000000000:task/simple-api-dev/abc123}" ;;
  *"ecs wait tasks-stopped"*) ;;
  *"ecs describe-tasks"*) echo "${FAKE_EXIT:-0}" ;;
  *"logs filter-log-events"*) printf '%s' "${FAKE_LOG:-}" ;;
esac
exit 0
EOS
chmod +x "$TMP/aws"

FALHAS=0
caso() {
  local nome="$1" esperado="$2" deve="$3"; shift 3
  local saida rc ok=1
  saida=$(env PATH="$TMP:$PATH" "$@" bash "$ROOT/tools/run-db-init.sh" dev 2>&1); rc=$?
  [ "$rc" -eq "$esperado" ] || ok=0
  if [ -n "$deve" ] && ! grep -Eq "$deve" <<<"$saida"; then ok=0; fi
  if [ "$ok" -eq 1 ]; then echo "OK    $nome (exit $rc)"; else echo "FALHA $nome (exit $rc, esperado $esperado)"; echo "$saida" | sed 's/^/      | /' | head -20; FALHAS=$((FALHAS+1)); fi
}

caso "task ok e linha DBINIT: exit 0"                    0 '^DBINIT \{"ok":true\}'  FAKE_EXIT=0 FAKE_LOG='DBINIT {"ok":true}'
caso "task com erro (exit code 1): exit 1"               1 'DBINIT_ERRO'            FAKE_EXIT=1 FAKE_LOG='DBINIT_ERRO {"code":"28P01"}'
caso "task ok mas sem linha DBINIT no log: exit 1"       1 'sem linha DBINIT'       FAKE_EXIT=0 FAKE_LOG=''
caso "banco revelou privilegio a mais (exit 1 da task)"  1 'exit code da task: 1'   FAKE_EXIT=1 FAKE_LOG='DBINIT {"ok":false}'
caso "stack fora do ar (service sem rede): exit 2"       2 'sem configuracao de rede' FAKE_NO_SERVICE=1
caso "run-task sem task (sem task definition): exit 2"   2 'sem a task definition'  FAKE_RUN_TASK=None

if [ "$FALHAS" -eq 0 ]; then echo "Todos os casos passaram."; exit 0; fi
echo "$FALHAS caso(s) falharam."; exit 1
