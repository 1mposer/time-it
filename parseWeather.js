function parseWeather(rawResponse, adapter) {
  const phase = adapter.extractMoonPhase(rawResponse);
  const moon = phase ? [phase] : [];

  return adapter.extractHours(rawResponse).slice(0, 24).map((row) => ({
    hour:         adapter.hour(row),
    temp:         adapter.temp(row),
    humidity:     adapter.humidity(row),
    windSpeed:    adapter.windSpeed(row),
    rainFall:     adapter.rainFall(row),
    cloudCover:   adapter.cloudCover(row),
    visibility:   adapter.visibility(row),
    moon,
    uV:           adapter.uV(row),
    dustAlert:    adapter.dustAlert(row),
    darkness:     0,
    douglasScale: 0,
    swellHeight:  0,
    swellLength:  0,
    tide:         0,
    seaWarning:   false,
  }));
}

module.exports = { parseWeather };
