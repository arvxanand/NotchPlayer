// The 14 waveform bars, from a clock rather than audio: the site makes no audio or mic requests.
// `synthetic` is the app's own fallback (Data/Bands.swift), ported exactly so the lab can match its
// held `quiet` and `loud` states. `demo` adds a beat at the song's tempo so it moves like music.
import { BARS } from './geometry';

export const silent = (): number[] => Array(BARS.count).fill(0);

export function synthetic(t: number, count = BARS.count): number[] {
  if (count <= 1) return Array(Math.max(0, count)).fill(0.5);
  return Array.from({ length: count }, (_, i) => {
    const f = i / (count - 1);
    const tilt = Math.pow(1 - f, 0.8) * 0.68 + 0.32;
    const fast = Math.sin(t * (1.7 + 2.3 * f) + i * 1.1);
    const slow = Math.sin(t * (0.6 + 0.9 * f) + i * 2.7);
    const mixed = (fast * 0.6 + slow * 0.4 + 1) / 2;
    return Math.max(0, Math.min(1, mixed * tilt));
  });
}

/** Bands.envelope: fast attack so a hit lands, slow decay so a bar falls like a meter needle. */
export function envelope(prev: number[], target: number[], attack = 0.5, decay = 0.12): number[] {
  if (prev.length !== target.length) return target;
  return prev.map((was, i) => Math.max(0, Math.min(1, was + (target[i] - was) * (target[i] > was ? attack : decay))));
}

/** Deterministic bars for a song at `t` seconds in: the app's synthetic shape, pushed by a beat
 *  at `bpm` that hits the low bars hardest. ponytail: not an FFT of the real song (none is shipped). */
export function demo(t: number, bpm: number): number[] {
  const phase = ((t * bpm) / 60) % 1;
  const kick = Math.exp(-phase * 7); // 1 on the beat, decaying before the next
  return synthetic(t * 1.6).map((v, i) => {
    const low = 1 - i / (BARS.count - 1);
    return Math.max(0, Math.min(1, v * (0.7 + 0.25 * kick) + kick * 0.35 * low * low));
  });
}

export const barHeight = (v: number, min: number, max: number) => min + Math.max(0, Math.min(1, v)) * (max - min);
