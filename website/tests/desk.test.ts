import { describe, expect, it } from 'vitest';
import { deskFit, SCREEN, STRIP_W } from '../src/notch/desk';

describe('deskFit', () => {
  it('full desktop scales to the container width and keeps the screen proportion', () => {
    const f = deskFit(1386, 0);
    expect(f.s).toBeCloseTo(1386 / SCREEN.w, 6);
    expect(f.h).toBeCloseTo(SCREEN.h * f.s, 6);
    expect(f.x).toBeCloseTo(0, 6);
  });
  it('a strip keeps the notch area at full size when there is room, centred', () => {
    const f = deskFit(1200, 160);
    expect(f.s).toBe(1);
    expect(f.h).toBe(160);
    expect(f.x).toBeCloseTo((1200 - SCREEN.w) / 2, 6);
  });
  it('a strip on a phone scales so STRIP_W fits, never above 1', () => {
    const f = deskFit(343, 520);
    expect(f.s).toBeCloseTo(343 / STRIP_W, 6);
    expect(f.h).toBeCloseTo(520 * f.s, 6);
  });
  it('matches the CSS aspect-ratio heights so JS never shifts layout', () => {
    // CSS: full = aspect-ratio 1512/982; strip = aspect-ratio 560/strip capped at strip px.
    expect(deskFit(800, 0).h).toBeCloseTo(800 * SCREEN.h / SCREEN.w, 6);
    expect(deskFit(500, 300).h).toBeCloseTo(Math.min(300, 500 * 300 / STRIP_W), 6);
  });
});

describe('housing', () => {
  it('is the 208x37 cutout', async () => {
    const { housingPath } = await import('../src/notch/desk');
    // Concave 4pt shoulders either side of a 208pt cutout, 8pt bottom corners, in a 216pt box.
    expect(housingPath()).toBe('M0 0Q4 0 4 4L4 29Q4 37 12 37L204 37Q212 37 212 29L212 4Q212 0 216 0Z');
  });
});
