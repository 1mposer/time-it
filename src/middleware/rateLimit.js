// Per-client request limits for /api/v1/* — fixed windows, in memory (the
// service runs as a single replica; a restart resets the counts).
//
// RATE_LIMIT_MODE: `observe` (default) only logs when a client goes over a
// limit; `enforce` answers 429 with the uniform { errors } envelope and a
// Retry-After header. The per-client provider-miss limit in the weather cache
// follows the same switch. Clients are keyed on req.ip (Express `trust proxy`
// is set in server.js); IPv6 addresses are keyed on their /64.
//
// Nothing here ever logs an IP address: the window summaries carry counts
// only, and the proxy self-check reports only the X-Forwarded-For entry count
// and whether req.ip is a private address (which would mean the proxy hop
// count is wrong and every client shares one key).

const net = require('node:net');
const { errorBody } = require('../routes/errorEnvelope');

const TOO_MANY_MESSAGE = 'Too many requests — try again shortly';

function rateLimitMode(env = process.env) {
  return String(env.RATE_LIMIT_MODE ?? '').trim().toLowerCase() === 'enforce' ? 'enforce' : 'observe';
}

// A positive integer from the environment (or 0, where `allowZero` — e.g. an
// outside provider budget of 0 sends all outside traffic to the last good
// forecast or 502), else the default.
function readLimit(name, fallback, env = process.env, { allowZero = false } = {}) {
  const raw = env[name];
  if (raw === undefined || String(raw).trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value)) return fallback;
  return value > 0 || (allowZero && value === 0) ? value : fallback;
}

// IPv6 text → its eight 16-bit groups (handles `::` and an IPv4 tail).
function ipv6Groups(ip) {
  let addr = ip.split('%')[0];
  if (addr.includes('.')) {
    const cut = addr.lastIndexOf(':');
    const [a, b, c, d] = addr.slice(cut + 1).split('.').map(Number);
    addr = `${addr.slice(0, cut + 1)}${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  const [head, tail] = addr.split('::');
  const headGroups = head ? head.split(':') : [];
  const tailGroups = tail ? tail.split(':') : [];
  const fill = tail === undefined ? [] : Array(8 - headGroups.length - tailGroups.length).fill('0');
  return [...headGroups, ...fill, ...tailGroups].map((g) => parseInt(g, 16));
}

// `::ffff:a.b.c.d` → `a.b.c.d`; anything else unchanged.
function unmapIPv4(ip) {
  const lower = ip.toLowerCase();
  if (lower.startsWith('::ffff:') && net.isIPv4(ip.slice(7))) return ip.slice(7);
  return ip;
}

// The bucket key for a client address: IPv4 as-is (IPv4-mapped IPv6
// unwrapped), IPv6 on its /64 — one subscriber usually holds a whole /64.
// No address → null (the caller skips per-client counting).
function clientKeyFor(ip) {
  if (typeof ip !== 'string' || ip.length === 0) return null;
  const addr = unmapIPv4(ip);
  if (net.isIPv4(addr)) return addr;
  if (net.isIPv6(addr)) {
    return `${ipv6Groups(addr).slice(0, 4).map((g) => g.toString(16)).join(':')}::/64`;
  }
  return addr;
}

// Loopback, private, link-local and carrier-grade-NAT ranges. Anything that
// is not an IP at all also counts (it cannot be a client's public address).
function isPrivateAddress(ip) {
  if (typeof ip !== 'string') return true;
  const addr = unmapIPv4(ip);
  if (net.isIPv4(addr)) {
    const [a, b] = addr.split('.').map(Number);
    return a === 0 || a === 10 || a === 127
      || (a === 100 && b >= 64 && b <= 127)
      || (a === 169 && b === 254)
      || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168);
  }
  if (net.isIPv6(addr)) {
    const g = ipv6Groups(addr);
    const allZeroHead = g.slice(0, 7).every((x) => x === 0);
    if (allZeroHead && (g[7] === 0 || g[7] === 1)) return true; // :: and ::1
    if ((g[0] & 0xfe00) === 0xfc00) return true; // fc00::/7 unique local
    if ((g[0] & 0xffc0) === 0xfe80) return true; // fe80::/10 link local
    return false;
  }
  return true;
}

// Fixed-window per-client limiter. At each window rollover it logs the count
// of distinct client keys it saw and how many requests went over the limit.
function createRateLimiter({
  name,
  limit,
  windowMs,
  mode = rateLimitMode(),
  now = Date.now,
  log = console.log,
  keyFor = (req) => clientKeyFor(req.ip),
}) {
  let windowStart = null;
  let counts = new Map();
  let over = 0;

  function roll(t) {
    const start = Math.floor(t / windowMs) * windowMs;
    if (start === windowStart) return;
    if (windowStart !== null && counts.size > 0) {
      log(`rate limit ${name}: window closed — ${counts.size} distinct client keys, ${over} requests over the limit of ${limit} (${mode})`);
    }
    windowStart = start;
    counts = new Map();
    over = 0;
  }

  return function rateLimit(req, res, next) {
    const t = now();
    roll(t);
    const key = keyFor(req) ?? 'unknown';
    const count = (counts.get(key) ?? 0) + 1;
    counts.set(key, count);
    if (count <= limit) return next();

    over += 1;
    if (over === 1) log(`rate limit ${name}: a client went over ${limit} requests in this window (${mode})`);
    if (mode !== 'enforce') return next();

    const retryAfter = Math.max(1, Math.ceil((windowStart + windowMs - t) / 1000));
    res.set('Retry-After', String(retryAfter));
    return res.status(429).json(errorBody(TOO_MANY_MESSAGE));
  };
}

// Logs, for the first `samples` requests after boot, how many
// X-Forwarded-For entries arrived and whether req.ip is a private address.
// Never logs an address.
function createProxySelfCheck({ samples = 50, log = console.log } = {}) {
  let seen = 0;
  return function proxySelfCheck(req, _res, next) {
    if (seen < samples) {
      seen += 1;
      const header = req.get('x-forwarded-for');
      const entries = header ? header.split(',').filter((s) => s.trim().length > 0).length : 0;
      log(`proxy self-check ${seen}/${samples}: x-forwarded-for entries=${entries}, req.ip private=${isPrivateAddress(req.ip)}`);
    }
    next();
  };
}

module.exports = {
  createRateLimiter,
  createProxySelfCheck,
  clientKeyFor,
  isPrivateAddress,
  rateLimitMode,
  readLimit,
  TOO_MANY_MESSAGE,
};
