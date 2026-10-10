import { describe, expect, it } from 'vitest';
import { synthetic, envelope, demo, barHeight } from '../src/notch/bands';

describe('waveform bands', () => {
  it('is deterministic and in 0..1', () => {
    expect(synthetic(2.1)).toEqual(synthetic(2.1));
    for (const t of [0, 0.4, 2.1, 99.5]) for (const v of [...synthetic(t), ...demo(t, 120)]) { expect(v).toBeGreaterThanOrEqual(0); expect(v).toBeLessThanOrEqual(1); }
  });
  it('is bass-tilted like a real spectrum', () => {
    let low = 0, high = 0;
    for (let t = 0; t < 60; t += 0.1) { const b = demo(t, 120); low += b[0] + b[1] + b[2]; high += b[11] + b[12] + b[13]; }
    expect(low).toBeGreaterThan(high * 1.5);
  });
  it('matches the app at a known point (Bands.synthetic(at: 0), bar 0 = 0.5 * (sin 0 * .6 + sin 0 * .4 + 1) * 1)', () => {
    expect(synthetic(0)[0]).toBeCloseTo(0.5, 10);
  });
  it('attacks fast and decays slowly', () => {
    expect(envelope([0], [1])[0]).toBeCloseTo(0.5);
    expect(envelope([1], [0])[0]).toBeCloseTo(0.88);
  });
  it('maps a value to the 2..22pt range', () => {
    expect(barHeight(0, 2, 22)).toBe(2);
    expect(barHeight(1, 2, 22)).toBe(22);
    expect(barHeight(2, 2, 22)).toBe(22);
  });
});
