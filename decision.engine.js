// ============================================================
// TIME-IT — Decision Engine v0.1
// Run with: node decision-engine.js
// ============================================================

// ── SYNTAX NOTE: const vs let ────────────────────────────────
// const  → value won't be reassigned (like a "locked" variable)
// let    → value can change (like a normal Python variable)
// You'll use const for most things — JS devs prefer immutability by default.


// ── 1. ACTIVITY LIBRARY ──────────────────────────────────────
// In Python you'd use a dict. In JS, this is an "object literal" — same idea, 
// different brackets. Keys don't need quotes unless they have special characters.

const activities = {

  cycling: {
    label: "Cycling",
    thresholds: {
      tempMin: 15,       // °C
      tempMax: 32,
      humidityMax: 70,   // %
      windMax: 25,       // km/h
      uvMax: 6,          // UV index
      dustAlert: false,  // no dust storms allowed
    },
  },

  stargazing: {
    label: "Stargazing",
    thresholds: {
      tempMin: 10,
      tempMax: 35,
      humidityMax: 60,
      windMax: 20,
      uvMax: 0,          // must be night (UV = 0)
      dustAlert: false,
      cloudCoverMax: 20, // % sky coverage
    },
  },

  bbq: {
    label: "BBQ",
    thresholds: {
      tempMin: 18,
      tempMax: 40,
      humidityMax: 80,
      windMax: 30,
      uvMax: 8,
      dustAlert: false,
    },
  },
};


// ── 2. MOCK WEATHER DATA ─────────────────────────────────────
// A real API returns something shaped like this.
// This is an array [] of objects {} — one per hour of the day.
// In Python: a list of dicts. Same concept.

const mockForecast = [
  // hour 0 = midnight
  { hour: 0,  temp: 27, humidity: 55, wind: 12, uv: 0, dust: false, cloud: 10 },
  { hour: 1,  temp: 26, humidity: 57, wind: 10, uv: 0, dust: false, cloud: 15 },
  { hour: 2,  temp: 25, humidity: 58, wind: 9,  uv: 0, dust: false, cloud: 20 },
  { hour: 3,  temp: 25, humidity: 60, wind: 8,  uv: 0, dust: false, cloud: 18 },
  { hour: 4,  temp: 24, humidity: 61, wind: 8,  uv: 0, dust: false, cloud: 12 },
  { hour: 5,  temp: 24, humidity: 62, wind: 7,  uv: 0, dust: false, cloud: 10 },
  { hour: 6,  temp: 25, humidity: 60, wind: 10, uv: 1, dust: false, cloud: 5  },
  { hour: 7,  temp: 27, humidity: 58, wind: 12, uv: 3, dust: false, cloud: 5  },
  { hour: 8,  temp: 29, humidity: 55, wind: 14, uv: 5, dust: false, cloud: 8  },
  { hour: 9,  temp: 31, humidity: 52, wind: 18, uv: 7, dust: false, cloud: 10 },
  { hour: 10, temp: 33, humidity: 50, wind: 22, uv: 9, dust: false, cloud: 10 },
  { hour: 11, temp: 36, humidity: 48, wind: 25, uv: 10,dust: false, cloud: 15 },
  { hour: 12, temp: 38, humidity: 45, wind: 28, uv: 11,dust: false, cloud: 20 },
  { hour: 13, temp: 40, humidity: 43, wind: 30, uv: 10,dust: true,  cloud: 25 },
  { hour: 14, temp: 41, humidity: 42, wind: 32, uv: 9, dust: true,  cloud: 30 },
  { hour: 15, temp: 40, humidity: 44, wind: 28, uv: 8, dust: true,  cloud: 28 },
  { hour: 16, temp: 39, humidity: 46, wind: 25, uv: 6, dust: false, cloud: 20 },
  { hour: 17, temp: 37, humidity: 50, wind: 20, uv: 4, dust: false, cloud: 15 },
  { hour: 18, temp: 35, humidity: 54, wind: 16, uv: 2, dust: false, cloud: 10 },
  { hour: 19, temp: 33, humidity: 57, wind: 14, uv: 0, dust: false, cloud: 8  },
  { hour: 20, temp: 31, humidity: 58, wind: 12, uv: 0, dust: false, cloud: 5  },
  { hour: 21, temp: 30, humidity: 57, wind: 11, uv: 0, dust: false, cloud: 8  },
  { hour: 22, temp: 29, humidity: 56, wind: 10, uv: 0, dust: false, cloud: 10 },
  { hour: 23, temp: 28, humidity: 55, wind: 9,  uv: 0, dust: false, cloud: 12 },
];


// ── 3. THE CHECK FUNCTION ────────────────────────────────────
// An "arrow function" — JS's version of def in Python.
// const fnName = (params) => { body }
// It takes one hour's data + one activity's thresholds and returns true/false.

const isHourValid = (hourData, thresholds) => {
  // Destructuring — pulls keys out of an object into variables.
  // Python equivalent: temp = hourData["temp"], etc.
  const { temp, humidity, wind, uv, dust, cloud } = hourData;
  const { tempMin, tempMax, humidityMax, windMax, uvMax, dustAlert, cloudCoverMax } = thresholds;

  // Standard conditionals — same as Python
  if (temp < tempMin || temp > tempMax) return false;
  if (humidity > humidityMax) return false;
  if (wind > windMax) return false;
  if (uv > uvMax) return false;
  if (dust === true && dustAlert === false) return false;

  // cloudCoverMax is optional — not every activity has it
  // The "!==" is JS strict not-equal (prefer this over !=)
  if (cloudCoverMax !== undefined && cloud > cloudCoverMax) return false;

  return true; // all checks passed
};


// ── 4. THE WINDOW FINDER ─────────────────────────────────────
// This is the engine's core. It scans the 24-hour forecast and
// groups consecutive valid hours into "windows".

const findWindows = (forecast, thresholds) => {
  const windows = []; // will hold our result objects
  let windowStart = null;

  // for...of — loops over an array like Python's "for item in list"
  for (const hourData of forecast) {
    const valid = isHourValid(hourData, thresholds);

    if (valid && windowStart === null) {
      // A new valid window is starting
      windowStart = hourData.hour;
    }

    if (!valid && windowStart !== null) {
      // Window just ended — save it
      windows.push({
        start: windowStart,
        end: hourData.hour, // exclusive end
      });
      windowStart = null;
    }
  }

  // Edge case: window runs through midnight
  if (windowStart !== null) {
    windows.push({ start: windowStart, end: 24 });
  }

  return windows;
};


// ── 5. FORMATTING HELPER ─────────────────────────────────────
// Template literals use backticks ` ` and ${ } for interpolation.
// Python equivalent: f"string {variable}"

const formatHour = (hour) => {
  if (hour === 0 || hour === 24) return "12:00am";
  if (hour === 12) return "12:00pm";
  const suffix = hour < 12 ? "am" : "pm";
  const displayHour = hour % 12;
  return `${displayHour}:00${suffix}`;
};

const formatWindow = (window) =>
  `${formatHour(window.start)} – ${formatHour(window.end)}`;


// ── 6. THE MAIN ENGINE ───────────────────────────────────────
// Object.entries() — converts an object into an array of [key, value] pairs.
// Python equivalent: dict.items()

const runEngine = (forecast, activityLibrary) => {
  console.log("=== TIME-IT · Today's Windows ===\n");

  for (const [activityKey, activity] of Object.entries(activityLibrary)) {
    const windows = findWindows(forecast, activity.thresholds);

    if (windows.length === 0) {
      console.log(`${activity.label}: ✗ No suitable window today`);
    } else {
      // .map() transforms every item in an array — like Python's list comprehension
      const formatted = windows.map(formatWindow).join(", ");
      console.log(`${activity.label}: ✓ ${formatted}`);
    }
  }
};


// ── 7. RUN IT ────────────────────────────────────────────────
runEngine(mockForecast, activities);
