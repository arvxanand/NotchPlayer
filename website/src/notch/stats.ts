// The stats page's numbers: a port of Stats.summary in Data/Listening.swift.
export type Range = 'today' | 'week' | 'month' | 'all';
export const RANGES: { id: Range; title: string }[] = [
  { id: 'today', title: 'Today' }, { id: 'week', title: 'Week' }, { id: 'month', title: 'Month' }, { id: 'all', title: 'All' },
];
export interface Play { id: string; name: string; artist: string; started: number; seconds: number } // started: ms epoch
export interface Entry { name: string; seconds: number; plays: number }
export interface Summary { seconds: number; songs: number; artists: Entry[]; tracks: Entry[] }

export const PLAYED_AFTER = 30;

/** Range starts as the app's Calendar.current gives them: local midnight, the week (Sunday start,
 *  en_US), the month. ponytail: Sunday-start weeks; a Monday-start locale differs on Sundays. */
export function rangeStart(range: Range, now: number): number | null {
  const d = new Date(now);
  if (range === 'all') return null;
  if (range === 'month') return new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  if (range === 'week') day.setDate(day.getDate() - day.getDay());
  return day.getTime();
}

export function summary(plays: Play[], range: Range, now: number, top = 3): Summary {
  const start = rangeStart(range, now);
  const inRange = plays.filter((p) => start === null || p.started >= start);
  const counted = inRange.filter((p) => p.seconds >= PLAYED_AFTER);
  const artists = new Map<string, Entry>();
  for (const p of inRange) {
    if (!p.artist) continue;
    const e = artists.get(p.artist) ?? { name: p.artist, seconds: 0, plays: 0 };
    e.seconds += p.seconds;
    if (p.seconds >= PLAYED_AFTER) e.plays++;
    artists.set(p.artist, e);
  }
  const tracks = new Map<string, Entry>();
  for (const p of counted) {
    const e = tracks.get(p.id) ?? { name: p.name, seconds: 0, plays: 0 };
    e.seconds += p.seconds; e.plays++;
    tracks.set(p.id, e);
  }
  return {
    seconds: inRange.reduce((a, p) => a + p.seconds, 0),
    songs: counted.length,
    artists: [...artists.values()].filter((e) => e.seconds >= 1)
      .sort((a, b) => b.seconds - a.seconds || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)).slice(0, top),
    tracks: [...tracks.values()].sort((a, b) => b.plays - a.plays || b.seconds - a.seconds).slice(0, top),
  };
}

export function duration(seconds: number): string {
  const minutes = Math.floor(seconds / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes}m`;
}
