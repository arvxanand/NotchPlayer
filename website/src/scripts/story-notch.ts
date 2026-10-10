// What the story's notch shows for a frame. Pure, so a still (static stack) and the scrolling
// story draw the same thing for the same beat.
import type { Frame } from './storyboard';
import type { NotchState } from '../notch/notch';
import { NOTCHED, PILL } from '../notch/geometry';
import { notchTrack } from '../notch/player';
import { demo } from '../notch/bands';
import { tracks } from '../data/tracks';
import { demoPlays } from '../data/plays';

/** The story's song: True, whose warm cover tint suits the page. */
export const STORY_TRACK = tracks.findIndex((t) => t.artist === 'Spandau Ballet');

export function notchFor(f: Frame, now: number): Partial<NotchState> {
  const t = tracks[STORY_TRACK];
  return {
    mac: f.pill ? PILL : NOTCHED, mode: f.mode, page: f.page, track: notchTrack(t, 'spotify'),
    position: f.position, playing: true, shuffle: f.shuffle, repeat: f.repeat, range: f.range,
    plays: demoPlays(now), now, bands: demo(f.position, t.bpm),
  };
}
