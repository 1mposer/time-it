# time-it

A backend engine that tells UAE outdoor hobbyists exactly when to go outside.

## What it does

time-it monitors hourly weather forecasts and sends a push notification when conditions match a user's activity preferences. "Tomorrow, 7am-9am: perfect conditions for cycling."

Users pick an activity, set their thresholds (max temperature, max humidity, wind range, etc.), and the backend handles the rest: fetching forecasts, evaluating conditions, and delivering the alert. The iOS app is a thin interface for preferences and notifications.

## How it works

1. **Fetch** - pulls hourly forecast data from a weather API
2. **Parse** - normalizes the response into a unified schema (temp, humidity, wind, rainfall, UV, cloud cover, visibility, dust alerts, moon phase, sea conditions)
3. **Match** - compares each hour against the user's activity thresholds
4. **Notify** - sends a push notification when a qualifying window is found

The weather layer uses an adapter pattern, allowing additional data sources to be swapped in without touching the core logic.

## Activities

Each activity ships with two preset threshold profiles:

- **Lite** uses standard weather metrics from free-tier APIs
- **Pro** unlocks richer data (atmospheric transparency, swell height, Douglas scale, moon phase) sourced from premium APIs, reflected in the subscription price

Activities at launch:

- Cycling
- Hiking
- Padel
- Volleyball
- Shore Fishing
- Boat Fishing
- Stargazing


## Stack

- **Runtime**: Node.js
- **Weather**: Meteosource API (adapter layer supports expansion)
- **Notifications**: Apple Push Notification service (APNs)
- **Client**: iOS (App Store)

## Setup

```bash
cp .env.example .env
# Add your API_KEY to .env
npm install
npm start
```
