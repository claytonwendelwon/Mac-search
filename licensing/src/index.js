/**
 * Beacon license server — Cloudflare Worker.
 *
 * Endpoints:
 *   POST /claim    {transactionId}  -> verifies the Paddle transaction and
 *                                      mints (or re-returns) a license key
 *   POST /validate {key}            -> checks the key's subscription is active
 *
 * The Paddle API key lives in the PADDLE_API_KEY secret (wrangler secret put),
 * never in this repo or the app. KV layout:
 *   license:<KEY>          -> {subscriptionId, customerId, email, createdAt}
 *   txn:<TRANSACTION_ID>   -> <KEY>            (idempotent re-claims)
 *   status:<KEY>           -> {valid, expiresAt} (24h cache of Paddle status)
 */

const PADDLE_API = "https://api.paddle.com";
// Unambiguous alphabet: no 0/O/1/I/L.
const KEY_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function generateKey() {
  const groups = [];
  const bytes = new Uint8Array(15);
  crypto.getRandomValues(bytes);
  for (let g = 0; g < 3; g++) {
    let group = "";
    for (let i = 0; i < 5; i++) {
      group += KEY_ALPHABET[bytes[g * 5 + i] % KEY_ALPHABET.length];
    }
    groups.push(group);
  }
  return `BEACON-${groups.join("-")}`;
}

async function paddle(env, path) {
  const res = await fetch(`${PADDLE_API}${path}`, {
    headers: { Authorization: `Bearer ${env.PADDLE_API_KEY}` },
  });
  if (!res.ok) {
    throw new Error(`paddle ${path} -> ${res.status}`);
  }
  const body = await res.json();
  return body.data;
}

async function handleClaim(request, env) {
  const { transactionId } = await request.json().catch(() => ({}));
  if (!transactionId || !/^txn_[a-z0-9]+$/.test(transactionId)) {
    return json({ error: "missing or malformed transactionId" }, 400);
  }

  // Idempotent: a refresh of the thanks page returns the same key.
  const existing = await env.LICENSES.get(`txn:${transactionId}`);
  if (existing) {
    return json({ key: existing });
  }

  let txn;
  try {
    txn = await paddle(env, `/transactions/${transactionId}`);
  } catch {
    return json({ error: "transaction not found" }, 404);
  }
  const paidStates = ["completed", "paid"];
  if (!paidStates.includes(txn.status)) {
    return json({ error: `transaction not completed (${txn.status})` }, 402);
  }
  const boughtBeacon = (txn.items || []).some(
    (item) => item.price?.id === env.PADDLE_PRICE_ID
  );
  if (!boughtBeacon) {
    return json({ error: "transaction is not for Beacon" }, 402);
  }

  let email = "";
  try {
    if (txn.customer_id) {
      const customer = await paddle(env, `/customers/${txn.customer_id}`);
      email = customer.email || "";
    }
  } catch {
    // Email is a nicety for support lookups; never block the claim on it.
  }

  const key = generateKey();
  const record = {
    subscriptionId: txn.subscription_id || null,
    customerId: txn.customer_id || null,
    transactionId,
    email,
    createdAt: new Date().toISOString(),
  };
  await env.LICENSES.put(`license:${key}`, JSON.stringify(record));
  await env.LICENSES.put(`txn:${transactionId}`, key);
  return json({ key });
}

async function subscriptionStatus(env, record) {
  // No subscription id (one-off transaction): treat as perpetual for the
  // year covered by the purchase; Paddle subscriptions are the normal path.
  if (!record.subscriptionId) {
    return { valid: true, expiresAt: null };
  }
  const sub = await paddle(env, `/subscriptions/${record.subscriptionId}`);
  const activeStates = ["active", "trialing", "past_due"];
  const valid = activeStates.includes(sub.status);
  const expiresAt = sub.current_billing_period?.ends_at || null;
  return { valid, expiresAt };
}

async function handleValidate(request, env) {
  const { key } = await request.json().catch(() => ({}));
  if (!key || !/^BEACON(-[23456789A-HJKMNP-Z]{5}){3}$/.test(key.trim())) {
    return json({ valid: false, error: "malformed key" }, 400);
  }
  const normalized = key.trim().toUpperCase();

  const recordRaw = await env.LICENSES.get(`license:${normalized}`);
  if (!recordRaw) {
    return json({ valid: false, error: "unknown key" }, 404);
  }

  // Serve a cached verdict for a day so app launches don't hammer Paddle.
  const cached = await env.LICENSES.get(`status:${normalized}`, "json");
  if (cached) {
    return json(cached);
  }

  const record = JSON.parse(recordRaw);
  let verdict;
  try {
    verdict = await subscriptionStatus(env, record);
  } catch {
    // Paddle briefly unreachable: fail open for known keys. The 24h cache
    // and the app's own offline grace keep abuse uninteresting.
    verdict = { valid: true, expiresAt: null, degraded: true };
  }
  await env.LICENSES.put(`status:${normalized}`, JSON.stringify(verdict), {
    expirationTtl: 60 * 60 * 24,
  });
  return json(verdict);
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/claim") {
      return handleClaim(request, env);
    }
    if (request.method === "POST" && url.pathname === "/validate") {
      return handleValidate(request, env);
    }
    return json({ error: "not found" }, 404);
  },
};
