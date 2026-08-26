// Shared in-memory weather cache — the one instance every weather consumer
// uses (/rating, device upsert, push jobs); do not build a second one.
// Key = lat/lon at 2 dp, TTL 60 min (the Meteosource upstream refresh cadence
// — docs/API_documentation/meteosource/README.md). The promise is cached, so
// concurrent callers share one in-flight fetch; a rejected fetch is evicted
// immediately.

const { getWeather: defaultGetWeather } = require('../weather');

const TTL_MS = 60 * 60 * 1000;

function createWeatherCache({ getWeather = defaultGetWeather, ttlMs = TTL_MS, now = Date.now } = {}) {
  const cache = new Map();

  return async function getCachedWeather(lat, lon) {
    const key = `${lat.toFixed(2)},${lon.toFixed(2)}`;
    const entry = cache.get(key);
    if (entry && now() - entry.fetchedAt < ttlMs) return entry.promise;

    const promise = getWeather(lat, lon);
    cache.set(key, { fetchedAt: now(), promise });
    promise.catch(() => {
      if (cache.get(key)?.promise === promise) cache.delete(key);
    });
    return promise;
  };
}

// Production singleton.
const getCachedWeather = createWeatherCache();

module.exports = { createWeatherCache, getCachedWeather, TTL_MS };
