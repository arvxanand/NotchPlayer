import { describe, expect, it } from 'vitest';
import { mmss, remaining } from '../src/notch/clock';
import { summary, duration, rangeStart, type Play } from '../src/notch/stats';

describe('clock', () => {
  it('formats like the app (the panel capture reads 0:23 and -3:58)', () => {
    expect(mmss(23.69)).toBe('0:23');
    expect(remaining(23.69, 261.849)).toBe('-3:58');
    expect(mmss(3723)).toBe('1:02:03');
    expect(remaining(10, 0)).toBe('--:--');
    expect(remaining(300, 200)).toBe('0:00');
  });
});

describe('stats', () => {
  const now = new Date(2026, 9, 10, 15, 0).getTime(); // Saturday 10 Oct 2026, 3pm
  const min = 60_000;
  const p = (id: string, artist: string, minutes: number, agoMin: number): Play => ({ id, name: id, artist, started: now - agoMin * min, seconds: minutes * 60 });
  const plays = [p('a', 'Drake', 48, 10), p('b', 'Spandau Ballet', 18, 60), p('a', 'Drake', 0.2, 5), p('c', 'Post Malone', 31, 60 * 24 * 3)];
  it('counts time for every play but a song only past 30s', () => {
    const s = summary(plays, 'today', now);
    expect(s.seconds).toBe((48 + 18 + 0.2) * 60);
    expect(s.songs).toBe(2);
    expect(s.artists.map((e) => e.name)).toEqual(['Drake', 'Spandau Ballet']);
    expect(s.artists[0].plays).toBe(1);
    expect(s.tracks[0]).toMatchObject({ name: 'a', plays: 1 });
  });
  it('widens with the range', () => {
    expect(summary(plays, 'today', now).songs).toBe(2);
    expect(summary(plays, 'week', now).songs).toBe(3); // Wednesday is in a Sunday-start week
    expect(summary(plays, 'all', now).songs).toBe(3);
    expect(rangeStart('week', now)).toBe(new Date(2026, 9, 4).getTime());
  });
  it('formats durations like the app', () => {
    expect(duration(59)).toBe('0m');
    expect(duration(134 * 60)).toBe('2h 14m');
  });
});
