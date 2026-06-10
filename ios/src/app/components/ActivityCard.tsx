import { Fish, Star, Settings, Thermometer, Sun, Wind, Droplets, Cloud } from 'lucide-react';

interface Activity {
  id: string;
  name: string;
  icon: string;
  bestTimeStart: number;
  bestTimeEnd: number;
  condition: 'perfect' | 'good' | 'none';
  displayMetrics: string[];
  metrics: Record<string, number>;
  isPro?: boolean;
}

interface ActivityCardProps {
  activity: Activity;
}

const sfText = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';

function VolleyballIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9.5" />
      <path d="M12 2.5c-2.2 3.5-2.2 7.5 0 11" />
      <path d="M12 10.5c2.2-3.5 2.2-7.5 0-11" />
      <path d="M2.5 12c3.5 2.2 7.5 2.2 11 0" />
    </svg>
  );
}

const iconMap: Record<string, React.ComponentType<{ className?: string }>> = {
  fish: Fish,
  star: Star,
  volleyball: VolleyballIcon,
};

const green  = { bg: 'rgba(52,199,89,0.12)',  text: '#1a7a35' };
const orange = { bg: 'rgba(255,149,0,0.12)',  text: '#b85c00' };
const red    = { bg: 'rgba(255,59,48,0.12)',   text: '#c0392b' };

function getMetricChipStyle(key: string, value: number): { bg: string; text: string; label: string } {
  switch (key) {
    case 'temp':
      return { ...(value >= 38 ? red : value >= 33 ? orange : green), label: `${value}°C` };
    case 'uV':
      return { ...(value >= 7 ? red : value >= 4 ? orange : green), label: `UV ${value}` };
    case 'windSpeed':
      return { ...(value >= 36 ? red : value >= 21 ? orange : green), label: `${value} km/h` };
    case 'humidity':
      return { ...(value >= 76 ? red : value >= 61 ? orange : green), label: `${value}%` };
    case 'cloudCover':
      return { ...(value >= 61 ? red : value >= 21 ? orange : green), label: `${value}%` };
    default:
      return { bg: 'rgba(142,142,147,0.12)', text: '#636366', label: `${value}` };
  }
}

function getMetricIcon(key: string) {
  switch (key) {
    case 'temp':       return <Thermometer className="w-3 h-3" />;
    case 'uV':         return <Sun className="w-3 h-3" />;
    case 'windSpeed':  return <Wind className="w-3 h-3" />;
    case 'humidity':   return <Droplets className="w-3 h-3" />;
    case 'cloudCover': return <Cloud className="w-3 h-3" />;
    default:           return null;
  }
}

const HOUR_COUNT = 18;
const START_HOUR = 6;

export function ActivityCard({ activity }: ActivityCardProps) {
  const Icon = iconMap[activity.icon];

  const windowColor =
    activity.condition === 'perfect' ? '#34c759' :
    activity.condition === 'good'    ? '#ff9500' : null;

  const winStart = Math.max(activity.bestTimeStart, START_HOUR);
  const winEnd   = Math.min(activity.bestTimeEnd, START_HOUR + HOUR_COUNT);
  const leftPct  = ((winStart - START_HOUR) / HOUR_COUNT) * 100;
  const widthPct = Math.max(0, ((winEnd - winStart) / HOUR_COUNT) * 100);

  const chips = activity.displayMetrics.slice(0, 3);

  return (
    <div
      style={{
        background: '#ffffff',
        borderRadius: 16,
        padding: '14px 16px 12px',
        boxShadow: '0 1px 3px rgba(0,0,0,0.08), 0 0 0 0.5px rgba(0,0,0,0.06)',
        fontFamily: sfText,
      }}
    >
      {/* Top row */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ color: '#1c1c1e', opacity: 0.75 }}>
            {Icon && <Icon className="w-[18px] h-[18px]" />}
          </div>
          <span style={{ fontSize: 15, fontWeight: 500, color: '#1c1c1e', letterSpacing: '-0.1px' }}>
            {activity.name}
          </span>
          {activity.isPro && (
            <span style={{
              fontSize: 9,
              fontWeight: 700,
              color: '#ff9500',
              background: 'rgba(255,149,0,0.12)',
              borderRadius: 4,
              padding: '2px 5px',
              letterSpacing: '0.5px',
              lineHeight: 1.4,
            }}>
              PRO
            </span>
          )}
        </div>
        <button
          style={{ color: '#8e8e93', padding: 4, background: 'none', border: 'none', cursor: 'pointer', lineHeight: 0 }}
          aria-label="Settings"
        >
          <Settings className="w-[15px] h-[15px]" />
        </button>
      </div>

      {/* Timeline */}
      <div style={{ marginBottom: 10 }}>
        <div
          style={{
            position: 'relative',
            height: 22,
            borderRadius: 6,
            background: '#f2f2f7',
            overflow: 'hidden',
          }}
        >
          {windowColor && (
            <div
              style={{
                position: 'absolute',
                top: 0,
                left: `${leftPct}%`,
                width: `${widthPct}%`,
                height: '100%',
                background: windowColor,
                borderRadius: 5,
                opacity: 0.85,
              }}
            />
          )}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4, paddingInline: 2 }}>
          {['6am', '12pm', '6pm', '12am'].map((label) => (
            <span key={label} style={{ fontSize: 10, color: '#8e8e93', letterSpacing: '0.1px' }}>
              {label}
            </span>
          ))}
        </div>
      </div>

      {/* Metric chips */}
      <div style={{ display: 'flex', gap: 6 }}>
        {chips.map((metric) => {
          const value = activity.metrics[metric] ?? 0;
          const { bg, text, label } = getMetricChipStyle(metric, value);
          const icon = getMetricIcon(metric);
          return (
            <div
              key={metric}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 4,
                background: bg,
                color: text,
                borderRadius: 20,
                paddingInline: 8,
                paddingBlock: 3,
                fontSize: 11.5,
                fontWeight: 500,
                letterSpacing: '0.05px',
              }}
            >
              {icon}
              <span>{label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export type { Activity };
