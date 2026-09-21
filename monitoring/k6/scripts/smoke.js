import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://host.docker.internal:8081";
const FRONTEND_URL = __ENV.FRONTEND_URL || "http://host.docker.internal:3000";

export const options = {
  vus: 5,
  duration: "30s",
  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<2000"],
  },
};

export default function () {
  const front = http.get(`${FRONTEND_URL}/`);
  check(front, { "frontend status < 500": (r) => r.status < 500 });

  const api = http.get(`${BASE_URL}/`);
  check(api, { "api gateway status < 500": (r) => r.status < 500 });

  sleep(1);
}
