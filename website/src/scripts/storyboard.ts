// Pure storyboard: scroll progress in, one frame out. Scrubbing in any order is safe.
import type { Repeat } from '../notch/notch';
import type { Range } from '../notch/stats';

export interface Frame {
  beat: number;          // 0 hero, 1 peek, 2 panel, 3 stats, 4 no notch
  grow: number;          // 0: the desktop small under the headline, 1: it fills the window
  mode: 'off' | 'peek' | 'panel';
  page: 'player' | 'stats';
  pill: boolean;         // a Mac without a notch
  position: number;      // seconds into the story's song
  shuffle: boolean;
  repeat: Repeat;
  range: Range;
}

export const GROW_END = 0.16;
const clamp = (v: number) => Math.max(0, Math.min(1, v));
const lerp = (a: number, b: number, f: number) => a + (b - a) * f;

export function storyFrame(p: number): Frame {
  const grow = clamp(p / GROW_END);
  // The song plays on as you scroll: 0:40 at the first beat to 1:40 at the end.
  const position = lerp(40, 100, clamp((p - GROW_END) / (1 - GROW_END)));
  const f: Frame = { beat: 0, grow, mode: 'peek', page: 'player', pill: false, position, shuffle: false, repeat: 'off', range: 'today' };
  if (p < 0.06) return { ...f, mode: 'off', position: 40 };   // the bare notch, nothing playing yet
  if (p < GROW_END) return { ...f, position: 40 };
  if (p < 0.36) return { ...f, beat: 1 };
  if (p < 0.58) return { ...f, beat: 2, mode: 'panel', shuffle: p >= 0.44, repeat: p >= 0.51 ? 'all' : 'off' };
  if (p < 0.78) return { ...f, beat: 3, mode: 'panel', page: 'stats', range: p >= 0.68 ? 'week' : 'today' };
  return { ...f, beat: 4, pill: true, mode: p >= 0.88 ? 'panel' : 'peek' };
}
