import http from 'k6/http';
import { check } from 'k6';
export const options = {
  scenarios: { s: { executor: 'constant-arrival-rate', rate: __ENV.RATE, timeUnit: '1s', duration: __ENV.DUR || '20s', preAllocatedVUs: 200, maxVUs: 1000 } },
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};
export default function () {
  const r = http.get(`http://127.0.0.1:${__ENV.PORT}${__ENV.PATH}`, { timeout: '5s' });
  check(r, { ok: (x) => x.status === 200 });
}
