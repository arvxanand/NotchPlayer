// The colour the progress line and the stats page take from the cover: a port of Views/Accent.swift.
// Used offline by tools/resolve-covers.mjs (the covers are cross-origin, so a page can't read them).
export interface RGB { r: number; g: number; b: number }

const MIN_SAT = 0.25, MIN_BRIGHT = 0.2, MIN_SHARE = 0.08, MIN_CONTRAST = 3.1;
export const SAMPLE = 24; // the side the cover is shrunk to before counting

/** The cover's main colour, made legible on black; null for a grey cover (the line stays white). */
export const accentOf = (rgba: ArrayLike<number>): RGB | null => {
  const d = dominant(rgba);
  return d ? legible(brightened(d)) : null;
};

export function brightened(c: RGB): RGB {
  const high = Math.max(c.r, c.g, c.b);
  return high > 0 ? { r: c.r / high, g: c.g / high, b: c.b / high } : c;
}

/** Twelve hue buckets weighted by saturation and brightness; the heaviest bucket's average wins. */
export function dominant(bytes: ArrayLike<number>): RGB | null {
  const count = Math.floor(bytes.length / 4);
  if (!count) return null;
  const weight = Array(12).fill(0), sum = Array.from({ length: 12 }, () => ({ r: 0, g: 0, b: 0 }));
  let coloured = 0;
  for (let i = 0; i < count; i++) {
    const r = bytes[i * 4] / 255, g = bytes[i * 4 + 1] / 255, b = bytes[i * 4 + 2] / 255;
    const high = Math.max(r, g, b), low = Math.min(r, g, b);
    if (high < MIN_BRIGHT || high <= 0) continue;
    const sat = (high - low) / high;
    if (sat < MIN_SAT) continue;
    coloured++;
    const bucket = Math.min(11, Math.floor(hue(r, g, b, high, low) * 12));
    const w = sat * high;
    weight[bucket] += w;
    sum[bucket].r += r * w; sum[bucket].g += g * w; sum[bucket].b += b * w;
  }
  if (coloured / count < MIN_SHARE) return null;
  let best = 0;
  for (let i = 1; i < 12; i++) if (weight[i] > weight[best]) best = i; // first of equals wins, as Swift's max(by:)
  const w = weight[best], s = sum[best];
  return { r: s.r / w, g: s.g / w, b: s.b / w };
}

/** Mixed toward white in 5% steps until it clears 3.1:1 on black. */
export function legible(c: RGB): RGB {
  for (let t = 0; ; t += 0.05) {
    const m = { r: c.r + (1 - c.r) * t, g: c.g + (1 - c.g) * t, b: c.b + (1 - c.b) * t };
    if (t >= 1 || contrastOnBlack(m) >= MIN_CONTRAST) return m;
  }
}

export const luminance = (c: RGB) => {
  const lin = (v: number) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
};
export const contrastOnBlack = (c: RGB) => (luminance(c) + 0.05) / 0.05;

function hue(r: number, g: number, b: number, high: number, low: number): number {
  const d = high - low;
  if (d <= 0) return 0;
  let h = high === r ? (g - b) / d : high === g ? 2 + (b - r) / d : 4 + (r - g) / d;
  h /= 6;
  return h < 0 ? h + 1 : h;
}

export const toHex = (c: RGB) => '#' + [c.r, c.g, c.b].map((v) => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
