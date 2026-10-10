// Views' Clock.swift: "0:23", "-3:58", "1:02:03".
export function mmss(seconds: number): string {
  if (!Number.isFinite(seconds)) return '--:--';
  const neg = seconds <= -1;
  const total = Math.floor(Math.abs(seconds));
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60;
  const body = h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`;
  return neg ? '-' + body : body;
}
export const remaining = (position: number, duration: number) => (duration > 0 ? mmss(-Math.max(0, duration - position)) : '--:--');
