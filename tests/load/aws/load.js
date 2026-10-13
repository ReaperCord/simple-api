// Carga PELO API GATEWAY (rotulo AWS). Gerador: maquina do Leandro, fora da AWS.
// Uso: k6 run -e BASE=https://<api-id>.execute-api.<regiao>.amazonaws.com -e RATE=40 -e DUR=300s -e PATHS=/connect load.js
// constant-arrival-rate (nunca VUs fixos para medir capacidade); PATHS alterna as rotas em ordem.
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const status429 = new Counter('status_429');
const status5xx = new Counter('status_5xx');
const paths = (__ENV.PATHS || '/connect').split(',');

export const options = {
  scenarios: {
    s: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE),
      timeUnit: '1s',
      duration: __ENV.DUR,
      preAllocatedVUs: 50,
      maxVUs: 300,
    },
  },
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const r = http.get(`${__ENV.BASE}${paths[__ITER % paths.length]}`, { timeout: '5s' });
  if (r.status === 429) status429.add(1);
  if (r.status >= 500) status5xx.add(1);
  check(r, { ok: (x) => x.status === 200 });
}
