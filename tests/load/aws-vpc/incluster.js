// Carga DENTRO da VPC (rotulo AWS), direto no IP da task da API (sem API Gateway).
// Roda numa task Fargate com a imagem grafana/k6; o script chega em base64 na variavel SCRIPT_B64.
// Variaveis: TARGET (ip:porta), PATH_URL (default /connect), STEPS (ex: 125,250,375,500), STEP_DUR (s),
// PROFILE = steps | breakpoint.  "steps" cobre load e stress (degraus constant-arrival-rate);
// "breakpoint" e uma rampa que ABORTA com erro > 1% ou p99 > 1 s.
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET;
const PATH_URL = __ENV.PATH_URL || '/connect';
const PROFILE = __ENV.PROFILE || 'steps';
const STEPS = (__ENV.STEPS || '').split(',').filter(Boolean).map(Number);
const STEP_DUR = Number(__ENV.STEP_DUR || 180);
const WARM_S = 10; // aquecimento descartado (tag step:warm)

const scenarios = {};
const thresholds = {};

if (PROFILE === 'breakpoint') {
  scenarios.ramp = {
    executor: 'ramping-arrival-rate',
    startRate: 100,
    timeUnit: '1s',
    preAllocatedVUs: 200,
    maxVUs: 2000,
    stages: [{ target: Number(__ENV.MAX_RATE || 1500), duration: `${__ENV.RAMP_S || 600}s` }],
  };
  thresholds.http_req_failed = [{ threshold: 'rate<0.01', abortOnFail: true, delayAbortEval: '10s' }];
  thresholds.http_req_duration = [{ threshold: 'p(99)<1000', abortOnFail: true, delayAbortEval: '10s' }];
} else {
  scenarios.warm = {
    executor: 'constant-arrival-rate',
    rate: STEPS[0],
    timeUnit: '1s',
    duration: `${WARM_S}s`,
    preAllocatedVUs: 100,
    maxVUs: 1500,
    exec: 'run',
    tags: { step: 'warm' },
  };
  STEPS.forEach((rate, i) => {
    const name = `s${rate}`;
    scenarios[name] = {
      executor: 'constant-arrival-rate',
      rate,
      timeUnit: '1s',
      duration: `${STEP_DUR}s`,
      startTime: `${WARM_S + i * STEP_DUR}s`,
      preAllocatedVUs: 100,
      maxVUs: 1500,
      exec: 'run',
      tags: { step: String(rate) },
    };
    // Thresholds triviais so para o k6 expor os submetrics por degrau no resumo.
    thresholds[`http_req_duration{step:${rate}}`] = ['max>=0'];
    thresholds[`http_req_failed{step:${rate}}`] = ['rate>=0'];
    thresholds[`http_reqs{step:${rate}}`] = ['count>=0'];
    thresholds[`dropped_iterations{scenario:${name}}`] = ['count>=0'];
  });
}

export const options = {
  scenarios,
  thresholds,
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};

export function run() {
  const r = http.get(`http://${TARGET}${PATH_URL}`, { timeout: '5s' });
  check(r, { ok: (x) => x.status === 200 });
}
export default run;

function pick(m, key) {
  return m[key] ? m[key].values : null;
}

export function handleSummary(data) {
  const m = data.metrics;
  const out = { profile: PROFILE, duration_ms: Math.round(data.state.testRunDurationMs), steps: [] };
  if (PROFILE === 'breakpoint') {
    const d = pick(m, 'http_req_duration') || {};
    const f = pick(m, 'http_req_failed') || {};
    const maxRate = Number(__ENV.MAX_RATE || 1500);
    const rampS = Number(__ENV.RAMP_S || 600);
    const elapsedS = out.duration_ms / 1000;
    out.total = {
      reqs: (pick(m, 'http_reqs') || {}).count,
      p50: d['p(50)'], p95: d['p(95)'], p99: d['p(99)'], max: d.max,
      erro_pct: 100 * (f.rate || 0),
      dropped: (pick(m, 'dropped_iterations') || {}).count || 0,
      aborted: elapsedS < rampS - 1,
      taxa_estimada_no_fim_req_s: Math.round(100 + (maxRate - 100) * Math.min(elapsedS / rampS, 1)),
    };
  } else {
    STEPS.forEach((rate) => {
      const d = pick(m, `http_req_duration{step:${rate}}`) || {};
      const f = pick(m, `http_req_failed{step:${rate}}`) || {};
      const n = pick(m, `http_reqs{step:${rate}}`) || {};
      const dr = pick(m, `dropped_iterations{scenario:s${rate}}`) || {};
      out.steps.push({
        taxa_req_s: rate, reqs: n.count, p50: d['p(50)'], p95: d['p(95)'], p99: d['p(99)'], max: d.max,
        erro_pct: 100 * (f.rate || 0), dropped: dr.count || 0,
      });
    });
  }
  return { stdout: `\nRESULT ${JSON.stringify(out)}\n` };
}
