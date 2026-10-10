// The scripted player behind the demo notch: a queue of the demo songs, a position that advances,
// and the transport. `step` and `act` are pure so they can be tested; `createPlayer` drives them.
import type { Track } from '../data/tracks';
import type { Action, NotchTrack, Repeat, Source } from './notch';
import { demo, envelope, silent } from './bands';

export interface PlayerState {
  order: number[]; // indexes into the tracks, in play order (shuffled when shuffle is on)
  at: number;      // position in `order`
  position: number;
  playing: boolean;
  shuffle: boolean;
  repeat: Repeat;
}

/** Modes.next: off, all, one, off. */
export const nextRepeat = (r: Repeat): Repeat => (r === 'off' ? 'all' : r === 'all' ? 'one' : 'off');

/** A fixed shuffle that keeps the current song first: same order every time, so a story beat or a test is reproducible. */
export function shuffled(n: number, first: number): number[] {
  const rest = Array.from({ length: n }, (_, i) => i).filter((i) => i !== first);
  for (let i = rest.length - 1; i > 0; i--) { const j = (i * 7 + 3) % (i + 1); [rest[i], rest[j]] = [rest[j], rest[i]]; }
  return [first, ...rest];
}

export const initial = (n: number, start = 0, position = 0): PlayerState =>
  ({ order: Array.from({ length: n }, (_, i) => i), at: start, position, playing: true, shuffle: false, repeat: 'off' });

const go = (s: PlayerState, at: number): PlayerState => ({ ...s, at: (at + s.order.length) % s.order.length, position: 0 });

/** Time passes. The end of a song plays the next one, or the same one again on repeat one. */
export function step(s: PlayerState, dt: number, durations: number[]): PlayerState {
  if (!s.playing) return s;
  let position = s.position + dt;
  const d = durations[s.order[s.at]];
  if (position < d) return { ...s, position };
  position -= d;
  // ponytail: off wraps to the first song like all does; the demo never stops on its own.
  const next = s.repeat === 'one' ? { ...s, position: 0 } : go(s, s.at + 1);
  return { ...next, position: Math.min(position, durations[next.order[next.at]]) };
}

export function act(s: PlayerState, a: Action): PlayerState {
  switch (a) {
    case 'playpause': return { ...s, playing: !s.playing };
    case 'next': return go(s, s.at + 1);
    // As Spotify: past the first few seconds, previous restarts the song.
    case 'previous': return s.position > 3 ? { ...s, position: 0 } : go(s, s.at - 1);
    case 'shuffle': {
      const current = s.order[s.at];
      return s.shuffle
        ? { ...s, shuffle: false, order: s.order.map((_, i) => i), at: current }
        : { ...s, shuffle: true, order: shuffled(s.order.length, current), at: 0 };
    }
    case 'repeat': return { ...s, repeat: nextRepeat(s.repeat) };
    default: return s; // save, album, track, artist: the app hands these to Spotify; the demo has nothing to open
  }
}

export const seek = (s: PlayerState, fraction: number, duration: number): PlayerState =>
  ({ ...s, position: Math.max(0, Math.min(1, fraction)) * duration });

export function notchTrack(t: Track, source: Source): NotchTrack {
  return { id: `${source}:${t.id}`, title: t.title, artist: t.artist, duration: t.duration, source, cover: t.cover, tint: t.tint, saveable: source === 'spotify' };
}

export interface Player {
  get state(): PlayerState;
  get track(): Track;
  get bands(): number[];
  act(a: Action): void;
  seek(fraction: number): void;
  set(patch: Partial<PlayerState>): void;
  start(): void;
  stop(): void;
}

/** Drives the state on requestAnimationFrame and the bars at the app's 30 frames a second. */
export function createPlayer(tracks: Track[], onChange: (p: Player) => void, init: PlayerState = initial(tracks.length)): Player {
  let s = init, bands = silent(), raf = 0, last = 0, barClock = 0;
  let settled: PlayerState | null = null;
  const durations = tracks.map((t) => t.duration);
  const emit = () => onChange(player);
  const frame = (now: number) => {
    const dt = Math.min(0.25, (now - last) / 1000); // a background tab must not skip a whole song
    last = now;
    s = step(s, dt, durations);
    barClock += dt;
    if (barClock >= 1 / 30) {
      barClock = 0;
      bands = s.playing ? envelope(bands, demo(s.position, tracks[s.order[s.at]].bpm)) : silent();
    }
    if (s.playing || settled !== s) emit(); // paused: one last frame so the bars settle, then quiet
    settled = s.playing ? null : s;
    raf = requestAnimationFrame(frame);
  };
  const player: Player = {
    get state() { return s; },
    get track() { return tracks[s.order[s.at]]; },
    get bands() { return bands; },
    act(a) { s = act(s, a); emit(); },
    seek(f) { s = seek(s, f, player.track.duration); emit(); },
    set(p) { s = { ...s, ...p }; emit(); },
    start() { if (raf) return; last = performance.now(); raf = requestAnimationFrame(frame); },
    stop() { cancelAnimationFrame(raf); raf = 0; },
  };
  return player;
}
