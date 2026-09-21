import http from "k6/http";
import { check, sleep } from "k6";
import { Rate } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://host.docker.internal:8081";
const TRACKING = __ENV.TRACKING_NUMBER || "";

const failRate = new Rate("client_errors");

// Rough stand-in for ~10k DAU: short peak of concurrent browsers hitting public surfaces.
export const options = {
  scenarios: {
    peak_browsing: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "1m", target: 20 },
        { duration: "3m", target: 50 },
        { duration: "1m", target: 0 },
      ],
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.1"],
    http_req_duration: ["p(95)<3000"],
    client_errors: ["rate<0.1"],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/v1/public/pricing/quote`, {
    headers: { Accept: "application/json" },
  });

  // GET may 405 — still useful as latency/error signal on the public prefix.
  const ok = check(res, {
    "public prefix reachable": (r) => r.status !== 0,
  });
  failRate.add(!ok);

  if (TRACKING) {
    const track = http.get(`${BASE_URL}/api/v1/shipments/${TRACKING}`, {
      headers: { Accept: "application/json" },
    });
    check(track, { "tracking responded": (r) => r.status !== 0 });
  }

  sleep(1);
}
