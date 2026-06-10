import { User, Plus, Activity } from 'lucide-react';
import { ActivityCard } from './components/ActivityCard';
import type { Activity as ActivityType } from './components/ActivityCard';

const sfDisplay = '-apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif';
const sfText = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

const activities: ActivityType[] = [
  {
    id: 'boat-fishing-pro',
    name: 'Boat Fishing Pro',
    icon: 'fish',
    bestTimeStart: 6,
    bestTimeEnd: 9,
    condition: 'perfect',
    displayMetrics: ['temp'],
    metrics: { temp: 24 },
    isPro: true,
  },
  {
    id: 'boat-fishing-lite',
    name: 'Boat Fishing Lite',
    icon: 'fish',
    bestTimeStart: 7,
    bestTimeEnd: 11,
    condition: 'good',
    displayMetrics: ['temp', 'windSpeed'],
    metrics: { temp: 26, windSpeed: 12 },
  },
  {
    id: 'shore-fishing',
    name: 'Shore Fishing',
    icon: 'fish',
    bestTimeStart: 6,
    bestTimeEnd: 8,
    condition: 'perfect',
    displayMetrics: ['temp', 'windSpeed'],
    metrics: { temp: 22, windSpeed: 8 },
  },
  {
    id: 'volleyball',
    name: 'Volleyball',
    icon: 'volleyball',
    bestTimeStart: 16,
    bestTimeEnd: 19,
    condition: 'good',
    displayMetrics: ['temp', 'windSpeed', 'humidity', 'uV'],
    metrics: { temp: 30, windSpeed: 10, humidity: 55, uV: 5 },
  },
  {
    id: 'stargazing-lite',
    name: 'Stargazing Lite',
    icon: 'star',
    bestTimeStart: 21,
    bestTimeEnd: 24,
    condition: 'perfect',
    displayMetrics: ['temp', 'cloudCover'],
    metrics: { temp: 18, cloudCover: 8 },
  },
];

function getCurrentTime() {
  return new Date().toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  });
}

export default function App() {
  const currentTime = getCurrentTime();

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: '#e5e5ea',
        fontFamily: sfText,
      }}
    >
      {/* iPhone shell */}
      <div
        style={{
          width: 390,
          height: 844,
          background: '#f2f2f7',
          borderRadius: 48,
          boxShadow: '0 24px 80px rgba(0,0,0,0.35), inset 0 0 0 1px rgba(255,255,255,0.15)',
          overflow: 'hidden',
          display: 'flex',
          flexDirection: 'column',
          position: 'relative',
          border: '9px solid #1c1c1e',
        }}
      >
        {/* ── HEADER ── */}
        <div
          style={{
            background: 'linear-gradient(160deg, #1253a4 0%, #1a78c2 38%, #29a8e0 72%, #3ec6e8 100%)',
            padding: '52px 20px 22px',
            position: 'relative',
            flexShrink: 0,
          }}
        >
          {/* Sign-in icon — top right */}
          <button
            style={{
              position: 'absolute',
              top: 16,
              right: 18,
              background: 'rgba(255,255,255,0.18)',
              border: 'none',
              borderRadius: 20,
              width: 34,
              height: 34,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer',
              color: '#fff',
            }}
            aria-label="Sign in"
          >
            <User style={{ width: 18, height: 18 }} strokeWidth={1.8} />
          </button>

          {/* Time */}
          <div style={{ textAlign: 'center' }}>
            <div
              style={{
                fontFamily: sfDisplay,
                fontSize: 60,
                fontWeight: 700,
                color: '#ffffff',
                letterSpacing: '-2.5px',
                lineHeight: 1,
              }}
            >
              {currentTime}
            </div>

            {/* Temperature — placeholder until live weather header data added */}
            <div
              style={{
                fontFamily: sfDisplay,
                fontSize: 28,
                fontWeight: 300,
                color: 'rgba(255,255,255,0.92)',
                letterSpacing: '-0.5px',
                marginTop: 8,
              }}
            >
              —°C
            </div>
          </div>

          {/* Wind + Humidity row */}
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              marginTop: 12,
              paddingInline: 4,
            }}
          >
            <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.8)', fontWeight: 400, letterSpacing: '0.1px' }}>
              💨 — km/h
            </span>
            <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.8)', fontWeight: 400, letterSpacing: '0.1px' }}>
              💧 —%
            </span>
          </div>
        </div>

        {/* ── DIVIDER ── */}
        <div
          style={{
            height: 0.5,
            background: 'rgba(60,60,67,0.18)',
            flexShrink: 0,
          }}
        />

        {/* ── ACTIVITY CARDS ── */}
        <div
          style={{
            flex: 1,
            overflowY: 'auto',
            padding: '14px 14px 0',
            display: 'flex',
            flexDirection: 'column',
            gap: 10,
            scrollbarWidth: 'none',
          }}
        >
          {activities.map((activity) => (
            <ActivityCard key={activity.id} activity={activity} />
          ))}
          {/* bottom padding above tab bar */}
          <div style={{ height: 12 }} />
        </div>

        {/* ── TAB BAR ── */}
        <div
          style={{
            flexShrink: 0,
            height: 82,
            background: 'rgba(255,255,255,0.82)',
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
            borderTop: '0.5px solid rgba(60,60,67,0.2)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-around',
            paddingBottom: 18,
            paddingInline: 20,
          }}
        >
          {/* Activities tab (active) */}
          <button
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 3,
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: '#ff9500',
              padding: '8px 16px',
              minWidth: 44,
              minHeight: 44,
            }}
            aria-label="Activities"
          >
            <Activity style={{ width: 24, height: 24 }} strokeWidth={1.8} />
          </button>

          {/* Plus tab */}
          <button
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 3,
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: '#8e8e93',
              padding: '8px 16px',
              minWidth: 44,
              minHeight: 44,
            }}
            aria-label="Add"
          >
            <Plus style={{ width: 24, height: 24 }} strokeWidth={1.8} />
          </button>

          {/* Profile tab */}
          <button
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 3,
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: '#8e8e93',
              padding: '8px 16px',
              minWidth: 44,
              minHeight: 44,
            }}
            aria-label="Profile"
          >
            <User style={{ width: 24, height: 24 }} strokeWidth={1.8} />
          </button>
        </div>
      </div>
    </div>
  );
}
