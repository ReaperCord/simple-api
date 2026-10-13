#!/usr/bin/env bash
# Benchmark LOCAL usado em 12/10/2026 (referência; não mede a AWS).
# Uso: BENCH_DIR=/caminho bench.sh <variante> <rota> <quota_us> <series> <duracao> <taxa_aquecimento> <taxas...>
#   BENCH_DIR contém <variante>/src/index.js (app), load.js e recebe results.csv
#   Requer: cgroup v1 de CPU em $CGROUP_DIR (cpu.cfs_period_us=100000), Postgres em 127.0.0.1, k6 e taskset.
#   quota_us 25000 = 0,25 vCPU; 50000 = 0,5 vCPU. A API roda no núcleo 0 e o k6 no núcleo 1.
#   Só funciona com cgroup v1 e root. Sem isso, rode a API num container com 'docker run --cpus=0.25' e aponte o k6 para ele.
#   Os logs da app vão para /dev/null: o custo do log medido aqui é um limite INFERIOR (num container real o stdout vai para um pipe).
set -uo pipefail
S="${BENCH_DIR:?defina BENCH_DIR}"
K6="${K6:-k6}"
CG="${CGROUP_DIR:-/sys/fs/cgroup/cpu/fargate}"
V=$1; P=$2; Q=$3; N=$4; DUR=$5; WARM=$6; shift 6
echo "$Q" > "$CG/cpu.cfs_quota_us"
OUT="$S/results.csv"
[ -f "$OUT" ] || echo "variant,path,vcpu,sweep,rate,rps,ok_pct,p50,p95,p99,max,dropped,throttled_pct,k6_cpu_pct" > "$OUT"
thr() { awk '/^nr_periods/{p=$2}/^nr_throttled/{t=$2}END{print p, t}' "$CG/cpu.stat"; }
for sw in $(seq 1 "$N"); do
  if [ "$V" = orig ]; then LOG="$S/app-$V-${P//\//_}-q$Q-$sw.log"; else LOG=/dev/null; fi
  (cd "$S/$V" && DB_HOST=127.0.0.1 DB_USER=postgres DB_DATABASE=simpleapi DB_PASSWORD="${DB_PASSWORD:-x}" API_PORT=3100 \
     exec taskset -c 0 node src/index.js >"$LOG" 2>>"$S/stderr-$V.log") &
  PID=$!; sleep 1.5; echo "$PID" > "$CG/cgroup.procs"   # cgroup.procs move TODAS as threads (tasks moveria só a principal)
  taskset -c 1 "$K6" run -q -e RATE="$WARM" -e PORT=3100 -e PATH="$P" -e DUR=10s "$S/load.js" >/dev/null 2>&1
  for R in "$@"; do
    read -r p0 t0 < <(thr)
    rm -f "$S/out.json"
    TIMEFORMAT='%R %U %S'
    { time taskset -c 1 "$K6" run -q --summary-export="$S/out.json" -e RATE="$R" -e PORT=3100 -e PATH="$P" -e DUR="$DUR" "$S/load.js" >/dev/null 2>&1 ; } 2> "$S/time.txt"
    rc=$?
    read -r p1 t1 < <(thr)
    if [ $rc -ne 0 ] || [ ! -s "$S/out.json" ]; then
      echo "$V,$P,$Q,$sw,$R,ERRO_k6_rc_$rc,,,,,,,," >> "$OUT"; tail -1 "$OUT"; sleep 2; continue
    fi
    python3 -I - "$V" "$P" "$Q" "$sw" "$R" "$p0" "$t0" "$p1" "$t1" "$S/out.json" "$S/time.txt" >> "$OUT" <<'PY'
import json, sys
V, P, Q, sw, R, p0, t0, p1, t1, js, tf = sys.argv[1:]
d = json.load(open(js))['metrics']; t = d['http_req_duration']; c = d['checks']
real, user, sysc = map(float, open(tf).read().split())
dp = int(p1) - int(p0); dt = int(t1) - int(t0)
print(f"{V},{P},{int(Q)/100000:.2f},{sw},{R},{d['http_reqs']['rate']:.0f},{100*c['passes']/(c['passes']+c['fails']):.2f},"
      f"{t['p(50)']:.2f},{t['p(95)']:.2f},{t['p(99)']:.2f},{t['max']:.0f},{d.get('dropped_iterations',{}).get('count',0)},"
      f"{(100*dt/dp if dp else 0):.0f},{100*(user+sysc)/real:.0f}")
PY
    tail -1 "$OUT"; sleep 2
  done
  kill "$PID"; wait "$PID" 2>/dev/null
done
