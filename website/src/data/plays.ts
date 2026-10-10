// The stats page's listening history for the demo: made up, deterministic, and relative to now so
// "Today" is never empty. Shape only: which of the demo songs, how often, how long.
import { tracks } from './tracks';
import type { Play } from '../notch/stats';

const H = 3_600_000;
// [track index, hours ago, minutes listened]: today, earlier this week, this month, before.
const LOG: [number, number, number][] = [
  [1, 0.2, 3.8], [3, 0.5, 3.6], [1, 0.9, 3.8], [0, 1.4, 4.2], [2, 2, 6.5], [1, 2.6, 3.8], [3, 3.1, 3.6],
  [0, 26, 4.2], [0, 27, 4.2], [2, 30, 6.5], [1, 50, 3.8], [3, 52, 1.2], [3, 53, 3.6],
  [2, 9 * 24, 6.5], [2, 9 * 24 + 1, 6.5], [0, 12 * 24, 4.2], [1, 14 * 24, 3.8],
  [3, 40 * 24, 3.6], [3, 41 * 24, 3.6], [0, 60 * 24, 4.2], [2, 90 * 24, 6.5],
];

export function demoPlays(now: number): Play[] {
  return LOG.map(([i, hoursAgo, minutes]) => ({
    id: tracks[i].id, name: tracks[i].title, artist: tracks[i].artist,
    started: now - hoursAgo * H, seconds: minutes * 60,
  }));
}

