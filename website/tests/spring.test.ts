import { describe, expect, it } from 'vitest';
import { springCurve } from '../src/notch/spring';

describe('springCurve', () => {
  const s = springCurve(0.38, 0.78);
  it('is a CSS linear() easing starting at 0 and ending at 1', () => {
    expect(s.css.startsWith('linear(0.0000')).toBe(true);
    expect(s.css.endsWith('1.0000)')).toBe(true);
  });
  it('overshoots slightly (underdamped) but not wildly', () => {
    const vals = s.css.slice(7, -1).split(',').map(Number);
    const max = Math.max(...vals);
    expect(max).toBeGreaterThan(1);
    expect(max).toBeLessThan(1.1);
  });
  it('settles in roughly a third of a second', () => {
    expect(s.durationMs).toBeGreaterThan(300);
    expect(s.durationMs).toBeLessThan(450);
  });
});
