import { afterEach, describe, expect, it, vi } from 'vitest';
import { createTour } from '../src/scripts/tour';

afterEach(() => vi.useRealTimers());

describe('createTour', () => {
  it('runs scheduled steps', () => {
    vi.useFakeTimers();
    const t = createTour();
    const fn = vi.fn();
    t.later(fn, 1000);
    vi.advanceTimersByTime(1000);
    expect(fn).toHaveBeenCalledTimes(1);
  });
  it('cancel stops queued steps and refuses new ones (user took over)', () => {
    vi.useFakeTimers();
    const t = createTour();
    const fn = vi.fn();
    t.later(fn, 1000);
    t.cancel();
    t.later(fn, 10);
    vi.advanceTimersByTime(5000);
    expect(fn).not.toHaveBeenCalled();
    expect(t.cancelled).toBe(true);
  });
});
