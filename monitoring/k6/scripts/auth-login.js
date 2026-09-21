import http from "k6/http";
import { check, sleep } from "k6";

/**
 * Authenticated login + dashboard-ish hit.
 * Set env:
 *   LOGIN_EMAIL / LOGIN_PHONE
 *   LOGIN_PASSWORD
 *   BASE_URL (default host.docker.internal:8081)
 */
const BASE_URL = __ENV.BASE_URL || "http://host.docker.internal:8081";
const LOGIN_ID = __ENV.LOGIN_EMAIL || __ENV.LOGIN_PHONE || "admin@example.com";
const LOGIN_PASSWORD = __ENV.LOGIN_PASSWORD || "password";

export const options = {
  vus: 10,
  duration: "2m",
  thresholds: {
    http_req_failed: ["rate<0.2"],
    http_req_duration: ["p(95)<3000"],
  },
};

export default function () {
  const payload = JSON.stringify({
    email: LOGIN_ID,
    phone: LOGIN_ID,
    password: LOGIN_PASSWORD,
  });

  const login = http.post(`${BASE_URL}/api/v1/auth/login`, payload, {
    headers: { "Content-Type": "application/json", Accept: "application/json" },
  });

  check(login, {
    "login not 5xx": (r) => r.status < 500,
  });

  let token = null;
  try {
    token = login.json("token") || login.json("data.token") || login.json("access_token");
  } catch (e) {}

  if (token) {
    const me = http.get(`${BASE_URL}/api/v1/me`, {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
      },
    });
    check(me, { "me ok-ish": (r) => r.status < 500 });
  }

  sleep(1);
}
