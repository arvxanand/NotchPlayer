import { describe, expect, it } from 'vitest';
import { NOTCHED, PILL, collapsed, open, frame, peekLayout, panelLayout, shellPath, fitScale } from '../src/notch/geometry';

// Expected numbers are the app's own, read off design/refs/refs.json (window 374x201, shell 352x39,
// housing 83,0,208,37) and the captures.
describe('notch geometry', () => {
  it('matches the capture sizes on a notched Mac', () => {
    expect(collapsed(NOTCHED)).toEqual({ w: 352, h: 39 });
    expect(open(NOTCHED)).toEqual({ w: 352, h: 185 });
    expect(frame(NOTCHED)).toEqual({ w: 374, h: 201 });
  });
  it('grows a 144pt pill into a 352pt panel without a notch', () => {
    expect(collapsed(PILL)).toEqual({ w: 144, h: 24 });
    expect(open(PILL)).toEqual({ w: 352, h: 172 });
  });
  it('puts the peek where the app does', () => {
    const p = peekLayout(NOTCHED, true);
    expect(p.art).toMatchObject({ x: 39, y: 7, w: 25, r: 5 });
    expect(p.mark).toMatchObject({ x: 20, y: 13.5, w: 12 });
    expect(p.bars).toMatchObject({ x: 288, y: 8.5, w: 54, max: 22 });
    // Nothing between the wings: the cutout is 72..280.
    expect(p.art.x + p.art.w).toBeLessThanOrEqual(72);
    expect(p.bars.x).toBeGreaterThanOrEqual(280);
  });
  it('hides the standalone mark when there is no cover', () => {
    expect(peekLayout(NOTCHED, false).mark).toBeNull();
    expect(peekLayout(NOTCHED, false).art.x).toBe(39);
  });
  it('centres and shrinks the pill peek', () => {
    const p = peekLayout(PILL, true);
    expect(p.art.w).toBe(16);
    const left = p.mark!.x, right = p.bars.x + p.bars.w;
    expect(left + right).toBeCloseTo(144, 5);
  });
  it('lays the panel out from the same constants as the app', () => {
    const l = panelLayout(NOTCHED);
    expect(l.art).toEqual({ x: 16, y: 51, w: 72, h: 72 });
    expect(l.text).toMatchObject({ x: 102, w: 234 });
    expect(l.progressY + 1.5).toBe(103);
    expect(l.transport).toEqual({ x: 80, y: 131, w: 192, h: 44 });
    expect(l.stats.x + l.stats.w).toBe(344);
  });
  it('draws one path shape for every size, so CSS can animate between them', () => {
    const a = shellPath(collapsed(NOTCHED), 11, 8, 374), b = shellPath(open(NOTCHED), 11, 22, 374);
    const shape = (s: string) => s.replace(/[\d.-]+/g, '#');
    expect(shape(a)).toBe(shape(b));
    expect(a.startsWith('M0 0Q11 0 11 11')).toBe(true);
  });
  it('fits narrow containers and never scales up', () => {
    expect(fitScale(2000, 374)).toBe(1);
    expect(fitScale(219, 374)).toBeCloseTo(0.5);
  });
});
