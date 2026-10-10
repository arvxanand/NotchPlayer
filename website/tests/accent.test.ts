import { describe, expect, it } from 'vitest';
import { accentOf, contrastOnBlack } from '../src/notch/accent';

const fill = (r: number, g: number, b: number, n = 576) => Array.from({ length: n }, () => [r, g, b, 255]).flat();

describe('cover accent', () => {
  it('gives null for a grey cover', () => expect(accentOf(fill(120, 120, 120))).toBeNull());
  it('brightens a dark red to full red', () => {
    const c = accentOf(fill(120, 10, 10))!;
    expect(c.r).toBe(1);
    expect(contrastOnBlack(c)).toBeGreaterThanOrEqual(3.1);
  });
  it('mixes pure blue toward white until it clears 3.1:1 on black', () => {
    const c = accentOf(fill(0, 0, 255))!;
    expect(c.r).toBeGreaterThan(0);
    expect(contrastOnBlack(c)).toBeGreaterThanOrEqual(3.1);
  });
  it('picks the bigger hue, not an average', () => {
    const px = [...fill(250, 20, 20, 400), ...fill(20, 20, 250, 176)];
    const c = accentOf(px)!;
    expect(c.r).toBeGreaterThan(c.b);
  });
  it('ignores one small logo on a grey cover', () => expect(accentOf([...fill(120, 120, 120, 560), ...fill(255, 0, 0, 16)])).toBeNull());
});
