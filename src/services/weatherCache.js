// Shared in-memory weather cache (#6c spec §6, ADR-0006).
//
// One cache for EVERY weather consumer — the push jobs, the device upsert's
// timezone resolution, and /rating (amended 2026-07-20: live dashboard traffic,
// not the hourly crons, is the largest source of duplicate provider calls).
// Do not build a second cache implementation for any of them.
//
// - TTL 60 min: owner-confirmed Meteosource flexi refreshes upstream somewhere
//   between every 10 min and every 1 hour; policy is to cache at the hourly end
//   of that range (docs/API_documentation/meteosource/README.md).
// - Key = lat/lon rounded to 2 dp (~1.1 km) so nearby devices share entries.
// - The PROMISE is cached, not the value: concurrent requests for the same key
//   share one in-flight provider call. A rejected fetch is evicted immediately —
//   failures must not be served for the rest of the TTL.

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
      // Evict only if this exact promise is still the cached one (a newer
      // fetch may already have replaced it).
      if (cache.get(key)?.promise === promise) cache.delete(key);
    });
    return promise;
  };
}

// The production singleton — the one instance every caller shares.
const getCachedWeather = createWeatherCache();

module.exports = { createWeatherCache, getCachedWeather, TTL_MS };
