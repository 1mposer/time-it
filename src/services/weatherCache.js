// Shared in-memory weather cache — the one instance every weather consumer
// uses (/rating, device upsert, push jobs); do not build a second one.
//
// Key = lat/lon rounded to 2 dp (~1.1 km); the provider is called with the
// same rounded coordinates. TTL 60 min (the Meteosource upstream refresh
// cadence — docs/API_documentation/meteosource/README.md). The in-flight
// promise is shared, so concurrent callers make one provider call.
//
// getCachedWeather(lat, lon, { origin = 'outside', allowStale = false, clientKey })
// - origin 'outside' (the default, so a caller that passes nothing is
//   limited): each provider miss counts against a global hourly budget and a
//   concurrency cap; with a clientKey (the caller's IP) it also counts against
//   a per-client hourly miss limit, which follows RATE_LIMIT_MODE (observe
//   only logs). No clientKey = no per-client count.
// - origin 'job': never counted, never refused, never served stale.
// - A provider failure blocks new provider calls for that cell for 60 s.
// - On a refusal or a failure, an outside caller with allowStale gets the
//   cell's last good forecast, unchanged, if it is at most 6 h old and its
//   forecastStart falls on the location's current local day; otherwise the
//   call rejects (UpstreamError → 502).
// - At most WEATHER_CACHE_MAX_ENTRIES cells; an entry whose last good
//   forecast is past the 6 h ceiling is swept, its forecast with it.
// All windows and sweeps run lazily off `now` — there are no timers.

const { getWeather: defaultGetWeather } = require('../weather');
const { UpstreamError } = require('../weather/UpstreamError');
const { localDay } = require('../weather/timeBoundary');
const { clientKeyFor, rateLimitMode, readLimit } = require('../middleware/rateLimit');

const TTL_MS = 60 * 60 * 1000;
const NEGATIVE_TTL_MS = 60 * 1000;
const STALE_MAX_MS = 6 * 60 * 60 * 1000;
const BUDGET_WINDOW_MS = 60 * 60 * 1000;

const DEFAULT_OUTSIDE_BUDGET_PER_HOUR = 60;
const DEFAULT_OUTSIDE_CONCURRENCY = 8;
const DEFAULT_MISSES_PER_CLIENT_PER_HOUR = 20;
const DEFAULT_MAX_ENTRIES = 1000;

const round2 = (x) => Math.round(x * 100) / 100;

function createWeatherCache({
  getWeather = defaultGetWeather,
  now = Date.now,
  outsideBudgetPerHour = readLimit('PROVIDER_OUTSIDE_BUDGET_PER_HOUR', DEFAULT_OUTSIDE_BUDGET_PER_HOUR),
  outsideConcurrency = readLimit('PROVIDER_OUTSIDE_CONCURRENCY', DEFAULT_OUTSIDE_CONCURRENCY),
  missesPerClientPerHour = readLimit('PROVIDER_MISSES_PER_CLIENT_PER_HOUR', DEFAULT_MISSES_PER_CLIENT_PER_HOUR),
  maxEntries = readLimit('WEATHER_CACHE_MAX_ENTRIES', DEFAULT_MAX_ENTRIES),
  clientLimitMode = rateLimitMode(),
  log = console.log,
} = {}) {
  // key → { promise, fetchedAt, inFlight, lastGood: { value, fetchedAt } | null, failedUntil, lastError }
  const cache = new Map();

  let outsideInFlight = 0;
  let windowStart = null;
  let outsideMisses = 0;
  let clientMisses = new Map();
  let clientOver = 0;
  const loggedThisWindow = new Set();

  function rollWindow(t) {
    const start = Math.floor(t / BUDGET_WINDOW_MS) * BUDGET_WINDOW_MS;
    if (start === windowStart) return;
    if (windowStart !== null && (outsideMisses > 0 || clientMisses.size > 0)) {
      log(`weather cache: hour closed — ${outsideMisses} outside provider misses, `
        + `${clientMisses.size} distinct client keys, ${clientOver} misses over the per-client limit (${clientLimitMode})`);
    }
    windowStart = start;
    outsideMisses = 0;
    clientMisses = new Map();
    clientOver = 0;
    loggedThisWindow.clear();
  }

  function logOnce(kind, line) {
    if (loggedThisWindow.has(kind)) return;
    loggedThisWindow.add(kind);
    log(line);
  }

  function staleValue(entry, t) {
    const good = entry?.lastGood;
    if (!good || t - good.fetchedAt > STALE_MAX_MS) return undefined;
    const { forecastStart, timezone } = good.value;
    const start = Date.parse(forecastStart);
    if (!Number.isFinite(start)) return undefined;
    if (localDay(start, timezone) !== localDay(t, timezone)) return undefined;
    return good.value;
  }

  const servesStale = (origin, allowStale) => allowStale && origin !== 'job';

  function refuse(entry, error, origin, allowStale, t) {
    const value = servesStale(origin, allowStale) ? staleValue(entry, t) : undefined;
    if (value !== undefined) return Promise.resolve(value);
    return Promise.reject(error);
  }

  function join(entry, promise, origin, allowStale) {
    if (!servesStale(origin, allowStale)) return promise;
    return promise.catch((err) => {
      const value = staleValue(entry, now());
      if (value !== undefined) return value;
      throw err;
    });
  }

  function removable(entry, t) {
    if (entry.inFlight) return false;
    if (entry.lastGood) return t - entry.lastGood.fetchedAt > STALE_MAX_MS;
    return entry.failedUntil <= t;
  }

  function makeRoom(t) {
    for (const [key, entry] of cache) {
      if (removable(entry, t)) cache.delete(key);
    }
    while (cache.size >= maxEntries) {
      let victim = null;
      for (const [key, entry] of cache) {
        if (!entry.inFlight) { victim = key; break; }
      }
      cache.delete(victim ?? cache.keys().next().value);
    }
  }

  function getCachedWeather(lat, lon, { origin = 'outside', allowStale = false, clientKey } = {}) {
    const rLat = round2(lat);
    const rLon = round2(lon);
    const key = `${rLat.toFixed(2)},${rLon.toFixed(2)}`;
    const t = now();
    let entry = cache.get(key);

    if (entry?.inFlight || (entry?.promise && t - entry.fetchedAt < TTL_MS)) {
      return join(entry, entry.promise, origin, allowStale);
    }

    if (entry && entry.failedUntil > t) {
      return refuse(entry, entry.lastError, origin, allowStale, t);
    }

    const outside = origin !== 'job';
    const client = outside ? clientKeyFor(clientKey) : null;
    if (outside) {
      rollWindow(t);
      if (outsideMisses >= outsideBudgetPerHour) {
        logOnce('budget', `weather cache: outside provider budget of ${outsideBudgetPerHour}/h reached`);
        return refuse(entry, new UpstreamError('Outside provider budget reached'), origin, allowStale, t);
      }
      if (outsideInFlight >= outsideConcurrency) {
        logOnce('concurrency', `weather cache: outside concurrency cap of ${outsideConcurrency} reached`);
        return refuse(entry, new UpstreamError('Outside provider concurrency cap reached'), origin, allowStale, t);
      }
      if (client !== null && (clientMisses.get(client) ?? 0) >= missesPerClientPerHour) {
        clientOver += 1;
        logOnce('client', `weather cache: a client went over the per-client limit of ${missesPerClientPerHour} misses/h (${clientLimitMode})`);
        if (clientLimitMode === 'enforce') {
          return refuse(entry, new UpstreamError('Per-client provider miss limit reached'), origin, allowStale, t);
        }
      }
    }

    if (entry) {
      cache.delete(key); // re-insert: Map order tracks the most recent fetch
    } else {
      makeRoom(t);
      entry = { promise: null, fetchedAt: 0, inFlight: false, lastGood: null, failedUntil: 0, lastError: null };
    }
    cache.set(key, entry);

    if (outside) {
      outsideMisses += 1;
      outsideInFlight += 1;
      if (client !== null) clientMisses.set(client, (clientMisses.get(client) ?? 0) + 1);
    }

    let promise;
    try {
      promise = Promise.resolve(getWeather(rLat, rLon));
    } catch (err) {
      promise = Promise.reject(err);
    }
    entry.promise = promise;
    entry.fetchedAt = t;
    entry.inFlight = true;
    // Bookkeeping is attached before any caller's handlers, so it has run by
    // the time a caller sees the result.
    const settle = () => {
      entry.inFlight = false;
      if (outside) outsideInFlight -= 1;
    };
    promise.then(
      (value) => {
        settle();
        entry.lastGood = { value, fetchedAt: t };
        entry.failedUntil = 0;
        entry.lastError = null;
      },
      (err) => {
        settle();
        if (entry.promise === promise) entry.promise = null;
        entry.failedUntil = now() + NEGATIVE_TTL_MS;
        entry.lastError = err;
      },
    );

    return join(entry, promise, origin, allowStale);
  }

  getCachedWeather.size = () => cache.size;
  return getCachedWeather;
}

// Production singleton.
const getCachedWeather = createWeatherCache();

module.exports = {
  createWeatherCache,
  getCachedWeather,
  TTL_MS,
  NEGATIVE_TTL_MS,
  STALE_MAX_MS,
  DEFAULT_MAX_ENTRIES,
};
