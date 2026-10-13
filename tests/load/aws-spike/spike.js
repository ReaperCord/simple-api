// Spike pelo API GATEWAY com autoscaling LIGADO (rotulo AWS). Gerador: task Fargate com grafana/k6 em us-east-1.
// Fases: 100 req/s por 60 s, salto para 1.500 req/s em 10 s, mantem 10 min, volta a 100 req/s por 20 min.
// Cada requisicao leva a tag bucket=mNN (minuto desde o inicio do teste) para ver a reacao do autoscaling no tempo.
// Variaveis: BASE (URL do API Gateway), QUICK=1 (validacao curta: 20 req/s por 10 s).
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';
import exec from 'k6/execution';

const BASE = __ENV.BASE;
const QUICK = __ENV.QUICK === '1';
const stages = QUICK
  ? [{ target: 20, duration: '10s' }]
  : [
      { target: 100, duration: '60s' },
      { target: 1500, duration: '10s' },
      { target: 1500, duration: '600s' },
      { target: 100, duration: '10s' },
      { target: 100, duration: '1200s' },
    ];
const totalS = stages.reduce((a, s) => a + Number(s.duration.replace('s', '')), 0);
const buckets = Math.ceil(totalS / 60);
const name = (i) => `m${String(i).padStart(2, '0')}`;

const s429 = new Counter('status_429');
const s5xx = new Counter('status_5xx');

const thresholds = {};
for (let i = 0; i < buckets; i++) {
  const b = name(i);
  thresholds[`http_req_duration{bucket:${b}}`] = ['max>=0'];
  thresholds[`http_req_failed{bucket:${b}}`] = ['rate>=0'];
  thresholds[`http_reqs{bucket:${b}}`] = ['count>=0'];
  thresholds[`status_429{bucket:${b}}`] = ['count>=0'];
  thresholds[`status_5xx{bucket:${b}}`] = ['count>=0'];
}

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: QUICK ? 20 : 100,
      timeUnit: '1s',
      preAllocatedVUs: 300,
      maxVUs: 3000,
      stages,
    },
  },
  thresholds,
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const m = Math.min(Math.floor(exec.instance.currentTestRunDuration / 60000), buckets - 1);
  const b = name(m);
  const r = http.get(`${BASE}/connect`, { timeout: '5s', tags: { bucket: b } });
  if (r.status === 429) s429.add(1, { bucket: b });
  if (r.status >= 500) s5xx.add(1, { bucket: b });
  check(r, { ok: (x) => x.status === 200 });
}

export function handleSummary(data) {
  const m = data.metrics;
  const v = (k) => (m[k] ? m[k].values : {});
  const out = { duration_ms: Math.round(data.state.testRunDurationMs), buckets: [] };
  for (let i = 0; i < buckets; i++) {
    const b = name(i);
    const d = v(`http_req_duration{bucket:${b}}`);
    out.buckets.push({
      b,
      reqs: v(`http_reqs{bucket:${b}}`).count || 0,
      p50: d['p(50)'], p95: d['p(95)'], p99: d['p(99)'], max: d.max,
      erro_pct: 100 * (v(`http_req_failed{bucket:${b}}`).rate || 0),
      s429: v(`status_429{bucket:${b}}`).count || 0,
      s5xx: v(`status_5xx{bucket:${b}}`).count || 0,
    });
  }
  out.dropped = (m.dropped_iterations ? m.dropped_iterations.values.count : 0);
  return { stdout: `\nRESULT ${JSON.stringify(out)}\n` };
}
