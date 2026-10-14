#!/usr/bin/env bash
# Teste LOCAL do laboratorio Kubernetes em kind (custo zero): manifests, probes, metrics-server, HPA, PDB,
# Pod Security e rolling update sem falhas. Nada toca a AWS. (07-eks-lab.md: "kind ou k3d LOCAL primeiro")
# Requisitos: docker (daemon ligado), kind, kubectl. Uso: tools/k8s-local-test.sh   (KEEP=1 mantem o cluster)
# Codigo de saida: 0 = todos os testes passaram; 1 = algum falhou; 2 = nao foi possivel montar o ambiente.
set -uo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash (Windows) converteria argumentos que comecam com "/"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER="simple-api-local"
CTX="kind-${CLUSTER}"
METRICS_SERVER_VERSION="v0.9.0" # a mesma do add-on metrics-server do EKS (v0.9.0-eksbuild)
PASS=0
FAIL=0

ok()   { echo "OK    $1"; PASS=$((PASS+1)); }
bad()  { echo "FALHA $1"; [ $# -gt 1 ] && echo "      | $2" | head -6; FAIL=$((FAIL+1)); }
die()  { echo "ERRO: $*" >&2; exit 2; }
k()    { kubectl --context "$CTX" "$@"; }
# docker.exe e kubectl.exe (Windows) nao entendem /c/Users/...: converte para C:/Users/... quando ha cygpath (Git Bash).
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf "%s" "$1"; fi; }

for t in docker kind kubectl; do command -v "$t" >/dev/null 2>&1 || die "$t nao encontrado"; done
docker info >/dev/null 2>&1 || die "o daemon do Docker nao esta rodando"

cleanup() {
  if [ "${KEEP:-0}" = "1" ]; then echo "KEEP=1: cluster $CLUSTER mantido (kind delete cluster --name $CLUSTER para apagar)"; return; fi
  kind delete cluster --name "$CLUSTER" >/dev/null 2>&1
}
trap cleanup EXIT

echo "== 1) cluster kind e imagem"
kind delete cluster --name "$CLUSTER" >/dev/null 2>&1
kind create cluster --name "$CLUSTER" --wait 180s >/dev/null 2>&1 || die "nao consegui criar o cluster kind"
docker build -q -t simple-api:local "$(winpath "$ROOT/application")" >/dev/null || die "docker build falhou"
kind load docker-image simple-api:local --name "$CLUSTER" >/dev/null 2>&1 || die "kind load falhou"
ok "cluster $CLUSTER (Kubernetes $(k version -o json 2>/dev/null | grep -o '"gitVersion": *"[^"]*"' | tail -1 | grep -o 'v[0-9.]*')) e imagem simple-api:local carregada"

echo "== 2) metrics-server ${METRICS_SERVER_VERSION} (patch --kubelet-insecure-tls so no kind)"
k apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml" >/dev/null || die "metrics-server: apply falhou"
k -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
k -n kube-system rollout status deployment/metrics-server --timeout=180s >/dev/null 2>&1 && ok "metrics-server pronto" || bad "metrics-server nao ficou pronto"

echo "== 3) namespaces, segredo local (aleatorio, fora do Git) e overlay local"
DBPASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
for ns in simple-api db-local loadtest; do k create namespace "$ns" --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1; done
for ns in simple-api db-local; do k -n "$ns" create secret generic db-local --from-literal=password="$DBPASS" >/dev/null || die "secret em $ns"; done
k apply -k "$(winpath "$ROOT/k8s/overlays/local")" >/dev/null || die "apply -k falhou"
k -n db-local rollout status deployment/postgres --timeout=240s >/dev/null 2>&1 || die "postgres nao ficou pronto"
k -n simple-api rollout status deployment/simple-api --timeout=240s >/dev/null 2>&1 && ok "Deployment simple-api pronto (1 replica, readiness /health)" || bad "Deployment simple-api nao ficou pronto" "$(k -n simple-api get pods 2>&1)"

BASE="http://simple-api.simple-api.svc.cluster.local"
# Sonda de dentro do cluster. Repete se a saida vier vazia (o primeiro pod pode estar baixando a imagem).
probe() {
  local out i
  for i in 1 2 3; do
    out="$(k -n loadtest run "probe-$RANDOM" --rm -i --restart=Never --quiet --image=busybox:1.37 -- sh -c "$1" 2>&1)"
    [ -n "$out" ] && break
    sleep 2
  done
  printf '%s
' "$out"
}

k -n loadtest run warm --restart=Never --image=busybox:1.37 -- true >/dev/null 2>&1; k -n loadtest wait --for=jsonpath='{.status.phase}'=Succeeded pod/warm --timeout=120s >/dev/null 2>&1; k -n loadtest delete pod warm --ignore-not-found >/dev/null 2>&1
echo "== 4) contrato HTTP (de dentro do cluster)"
for p in / /health /connect; do
  code="$(probe "wget -q -S -O /dev/null $BASE$p 2>&1 | grep -m1 -o 'HTTP/[0-9.]* [0-9]*'" | tail -1)"
  case "$code" in *" 200") ok "GET $p = 200";; *) bad "GET $p = 200" "$code";; esac
done
probe "wget -q -O- $BASE/" | grep -q 'API OK!' && ok 'GET / devolve "API OK!"' || bad 'GET / devolve "API OK!"'

echo "== 5) seguranca em runtime"
uid="$(k -n simple-api exec deploy/simple-api -- id -u 2>&1)"; [ "$uid" = "1000" ] && ok "processo roda como uid 1000 (nao-root)" || bad "uid esperado 1000" "$uid"
ro="$(k -n simple-api exec deploy/simple-api -- sh -c 'touch /zz-teste 2>&1' 2>&1)"; grep -qi 'read-only' <<<"$ro" && ok "sistema de arquivos raiz somente leitura" || bad "root FS deveria ser read-only" "$ro"
cat <<'EOF' | k -n simple-api apply --dry-run=server -f - >/tmp/psa.txt 2>&1
apiVersion: v1
kind: Pod
metadata: {name: psa-teste}
spec:
  containers:
    - name: x
      image: busybox
      securityContext: {privileged: true}
EOF
grep -qi 'violates PodSecurity' /tmp/psa.txt && ok "Pod Security restricted barra um pod privilegiado no namespace da app" || bad "PSA deveria barrar o pod privilegiado" "$(cat /tmp/psa.txt)"

echo "== 6) HPA e PDB"
k -n simple-api get hpa simple-api >/dev/null 2>&1 && ok "HPA existe (min 1, max 3, CPU 60%)" || bad "HPA ausente"
k -n simple-api get pdb simple-api >/dev/null 2>&1 && ok "PDB existe (minAvailable 1)" || bad "PDB ausente"
cur=""
for i in $(seq 1 24); do cur="$(k -n simple-api get hpa simple-api -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)"; [ -n "$cur" ] && break; sleep 5; done
[ -n "$cur" ] && ok "HPA le a CPU pelo metrics-server (uso atual ${cur}%)" || bad "HPA sem metrica de CPU (<unknown>)" "$(k -n simple-api describe hpa simple-api 2>&1 | tail -5)"

echo "== 7) rolling update sem nenhuma requisicao falhada (maxUnavailable 0 + readiness + preStop), 3 restarts seguidos"
k -n loadtest delete pod roll --ignore-not-found >/dev/null 2>&1
k -n loadtest run roll --restart=Never --image=busybox:1.37 -- sh -c "
f=0; t=0; end=\$(( \$(date +%s) + 150 ))
while [ \$(date +%s) -lt \$end ]; do t=\$((t+1)); wget -q -T 2 -O /dev/null $BASE/health || f=\$((f+1)); sleep 0.2; done
echo \"TOTAL=\$t FALHAS=\$f\"" >/dev/null
sleep 10
for r in 1 2 3; do
  k -n simple-api rollout restart deployment/simple-api >/dev/null
  k -n simple-api rollout status deployment/simple-api --timeout=180s >/dev/null 2>&1
  sleep 5
done
k -n loadtest wait --for=jsonpath='{.status.phase}'=Succeeded pod/roll --timeout=200s >/dev/null 2>&1
res="$(k -n loadtest logs roll 2>&1 | tail -1)"
tot="$(grep -o 'TOTAL=[0-9]*' <<<"$res" | cut -d= -f2)"; fal="$(grep -o 'FALHAS=[0-9]*' <<<"$res" | cut -d= -f2)"
if [ -n "${tot:-}" ] && [ "${tot:-0}" -gt 100 ] && [ "${fal:-1}" = "0" ]; then ok "3 rolling restarts com $tot requisicoes e 0 falhas"; else bad "rolling update com falhas ($res)"; fi

echo "== 8) HPA escala sob carga (carga em /connect por pods temporarios)"
for i in 1 2 3; do
  k -n loadtest run "load-$i" --restart=Never --image=busybox:1.37 -- sh -c "while true; do wget -q -T 2 -O /dev/null $BASE/connect; done" >/dev/null 2>&1
done
desired=1; peak=0
for i in $(seq 1 60); do
  desired="$(k -n simple-api get hpa simple-api -o jsonpath='{.status.desiredReplicas}' 2>/dev/null)"; desired="${desired:-1}"
  cpu="$(k -n simple-api get hpa simple-api -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)"
  [ "${cpu:-0}" -gt "$peak" ] && peak="${cpu:-0}"
  [ "$desired" -ge 2 ] && break
  sleep 6
done
[ "$desired" -ge 2 ] && ok "HPA escalou para $desired replicas (CPU de pico ${peak}%)" || bad "HPA nao escalou (desired=$desired, CPU de pico ${peak}%)" "$(k -n simple-api describe hpa simple-api 2>&1 | tail -6)"
k -n loadtest delete pod load-1 load-2 load-3 roll --ignore-not-found --wait=false >/dev/null 2>&1

echo
echo "RESULTADO: $PASS ok, $FAIL falha(s)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
