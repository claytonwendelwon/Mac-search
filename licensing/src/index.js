/**
 * Beacon license server — Cloudflare Worker.
 *
 * Endpoints:
 *   POST /validate {key}            -> validates a Lemon Squeezy license key and
 *                                      confirms it belongs to Beacon's store.
 *   POST /claim    {transactionId}  -> [DORMANT] Paddle mint path, kept so we
 *                                      can flip back to Paddle once approved.
 *
 * Lemon Squeezy generates and delivers the license key itself (on the post-
 * purchase screen and receipt email), so there's no minting to do here — the
 * app just pastes the key and we validate it. Validation is keyless (LS's
 * validate endpoint is authenticated by the key), but we MUST confirm the key
 * came from OUR store/product, because LS's endpoint validates any key from any
 * store. KV layout:
 *   status:<KEY>           -> {valid, expiresAt} (24h cache of LS status)
 *   (Paddle-era keys) license:<KEY>, txn:<ID>    (unused going forward)
 */

const LS_API = "https://api.lemonsqueezy.com/v1/licenses/validate";
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
  // LS keys are lowercase UUIDs; the app uppercases before sending, so undo it.
  const normalized = (key || "").trim().toLowerCase();
  // Loose sanity check (UUID-ish); the real check is LS + store match below.
  if (!/^[a-f0-9-]{16,64}$/.test(normalized)) {
    return json({ valid: false, error: "malformed key" }, 400);
  }

  // Serve a cached verdict for a day so app launches don't hammer LS.
  const cached = await env.LICENSES.get(`status:${normalized}`, "json");
  if (cached) {
    return json(cached);
  }

  let ls;
  try {
    const res = await fetch(LS_API, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ license_key: normalized }),
    });
    ls = await res.json();
  } catch {
    // LS briefly unreachable and no cached verdict: fail closed but DON'T cache
    // it. The app keeps its prior state (background revalidation ignores
    // failures) and its 14-day offline grace covers transient outages.
    return json({ valid: false, error: "validator unreachable", degraded: true }, 503);
  }

  const lk = ls.license_key || {};
  const meta = ls.meta || {};
  // Product match is the primary guard (LS product IDs are globally unique).
  // Store match is an optional extra check, enforced only if LS_STORE_ID is set.
  const productOK = String(meta.product_id) === String(env.LS_PRODUCT_ID);
  const storeOK =
    !env.LS_STORE_ID || String(meta.store_id) === String(env.LS_STORE_ID);
  // `inactive` = purchased but not yet activated on a device — still a paid,
  // legitimate key. `expired`/`disabled` = lapsed subscription or revoked.
  const statusOK = lk.status === "active" || lk.status === "inactive";
  const valid = ls.valid === true && statusOK && storeOK && productOK;

  const verdict = { valid, expiresAt: lk.expires_at || null };
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
